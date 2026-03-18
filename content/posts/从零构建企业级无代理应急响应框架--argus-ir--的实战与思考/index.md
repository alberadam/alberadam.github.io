---
title: "从零构建企业级无代理应急响应框架 (Argus-IR) 的记录与思考"
date: 2026-03-18T20:06:28+08:00
draft: true
tags: ["Windows", "DevOps", "Security", "Response", "PowerShell"]
categories: ["Tech"]
description: "构建企业级无代理应急响应框架 (Argus-IR) 的记录与思考"
---

# 从零构建企业级无代理应急响应框架 (Argus-IR) 的实战与思考

## 引言：为什么还要再造一个轮子？

做应急响应（IR）和红蓝对抗时，经常会遇到这种情况：服务器被黑了，但它是隔离网的老旧系统，没装EDR；或者你只能靠人工敲命令翻日志，面对海量进程和注册表项，效率极低还容易漏掉关键线索。

市面上的开源IR工具不少，但要么太重（需要装依赖），要么不够灵活（逻辑写死），很难适配现场环境。为了彻底吃透Windows底层的那些机制，也为了给自己打造一把趁手的兵器，我决定从零开始，纯靠PowerShell和原生API写一个轻量、高隐蔽、完全解耦的自动化威胁狩猎框架——**Argus-IR**。

这篇文章会复盘Argus-IR v1.0（MVP）的架构思路，以及填坑过程中那些让人抓狂的底层细节和最终解法。

---

## 一、Argus-IR 的设计定位

Argus-IR 的目标很简单：**静默、极速、全面**。  
它不需要安装任何运行时，只要有PowerShell环境就能“即插即用”。主要用在三个场景：

- **失陷主机取证**：勒索软件爆发或后门植入后，一键提取进程、网络连接、注册表自启动、服务、高危日志的快照。
- **威胁狩猎**：结合YARA引擎和自建IOC规则库，主动扫荡无文件木马、影子账户、WMI后门。
- **基线核查**：自动对比历史“黄金快照”，抓出所有未经授权的持久化手段。

---

## 二、架构设计：数据与逻辑彻底解耦

如果所有采集命令和判断逻辑都塞在一个脚本里，后期维护绝对是灾难。所以Argus-IR采用了经典的三层漏斗模型：

1. **Collectors（采集层）**  
   只负责“搬砖”，从系统底层抓取进程树、WMI订阅、DNS缓存等数据，输出标准化的对象数组。**这里绝对不含任何判断逻辑**。

2. **Analyzers（分析层）**  
   双引擎大脑：
   - **已知威胁**：读取外挂的 `ioc_rules.csv`，对采集数据进行正则匹配。
   - **未知威胁**：通过哈希快照对比（Compare-WithBaseline）发现新增的自启动项。
   - **深度特征**：调用YARA引擎，对高危临时脚本和活动进程做内存级扫描。

3. **Exporters（导出层）**  
   把命中规则的数据打上MITRE ATT&CK标签，最后落地为：  
   - 分类CSV（方便Excel透视）  
   - JSON（机器可读）  
   - HTML战术时间线（给老板汇报用）

所有模块调度都由外部的 `Config.json` 控制，做到了框架与业务逻辑分离。

---

## 三、实战踩坑录：那些逼疯人的底层机制与解法

写安全工具，80%的时间都在处理各种异常。这里分享几个印象最深的坑和最终的“解法”。

### 1. 严格模式下的隐式陷阱

为了代码严谨，我开了 `Set-StrictMode`。结果呢？普通进程有 `ExecutablePath` 属性，但内核进程（PID 4）因为权限问题没有这个属性。一旦引擎访问不存在的属性，脚本直接崩溃。  
当时报错长这样：  
>`Property 'ExecutablePath' cannot be found`

**解法（反射探测装甲）**  
大面积引入底层反射：`$item.psobject.Properties.Name -contains '属性名'`。在提取字段前先动态探测对象是否有该属性，大大增强了采集器的健壮性。

```powershell
if ($item.psobject.Properties.Name -contains 'ExecutablePath') {
    $exePath = $item.ExecutablePath
} else {
    $exePath = $null
}
```

### 2. WMI无文件持久化的异构解析

高级APT喜欢用WMI事件订阅种后门。但黑客可能用 `CommandLineTemplate`（命令行）或 `ScriptText`（脚本）两种方式存储payload。如果只写一种解析逻辑，就会漏掉另一半。

**解法**  
通过 `try-catch` 加反射探测，写了一套高容错的解析流，不管对方用哪种方式都能提取出来：

```powershell
$consumerProps = $consumer.psobject.Properties.Name
if ($consumerProps -contains 'CommandLineTemplate') {
    $cmd = $consumer.CommandLineTemplate
} elseif ($consumerProps -contains 'ScriptText') {
    $cmd = $consumer.ScriptText
}

```

### 3. 海量日志引发的OOM

如果直接用 `Get-EventLog | Where-Object`，几百万条日志能把内存撑爆。

**解法**  
全面改用 `Get-WinEvent` 配合 `FilterHashtable`，把过滤条件（比如只看4625爆破登录、1102日志清空）下推给底层的C++ Event Log Service，高效返回结果。

```powershell
$filter = @{LogName='Security'; ID=4625,1102}
$events = Get-WinEvent -FilterHashtable $filter -MaxEvents 1000
```

### 4. CSV导出时的列丢失黑洞

当网络对象（有IP属性）和进程对象（有Path属性）混在一个数组里导出CSV时，PowerShell默认会丢弃后面对象的额外列。

**解法**  
强制每个采集对象带一个 `Type` 字段，导出前按 `Type` 分组，循环输出多个CSV文件，做到零丢失。

```powershell
$allData | Group-Object -Property Type | ForEach-Object {
    $_.Group | Export-Csv "Output/$($_.Name).csv" -NoTypeInformation
}
```

---

## 四、优缺点与适用边界

**优势**  
- **极简**：纯PowerShell脚本，不留痕，不写注册表，符合电子取证规范。  
- **高信噪比**：经过端点降噪和精准正则调优，加上ATT&CK标签，大幅降低分析师研判负担。

**局限**  
- **无实时阻断**：主要用于事后取证和狩猎，无法像EDR那样在攻击瞬间拦截。 
- **规则库不够全面**: 未引入威胁情报规则转化机制，规则库过少 
- **单点作战**：目前没有对接SIEM的流式汇聚能力。

---

## 五、未来演进：向数据驱动防御演进

Argus-IR v1.0 验证了底层引擎的健壮性。v2.0 计划向“数据驱动防御”升级：

1. **规则与引擎彻底解耦**  
   废弃代码中硬编码的ATT&CK映射表，改用外置的威胁情报字典（内联MITRE标签）。
2. **CI/CD威胁情报流水线**  
   写Python脚本定期从SigmaHQ、Florian Roth's Signature-Base拉取最新规则，编译成 `index.yar` 和 `ioc_rules.csv`。
3. **高并发与内存取证**  
   引入PowerShell `RunspacePool` 实现多线程；利用WinAPI直接读取进程内存空间，配合YARA猎杀无文件恶意软件。

---

> 造轮子的过程希望这篇文章能给同样在捣鼓蓝队开发的朋友一点启发。  
> 项目代码已在GitHub开源：[https://github.com/alberadam/Argus-IR](https://github.com/alberadam/Argus-IR)

---
