---
title: "从零手写一套带 SOAR 能力的轻量级跨平台 SIEM 系统的记录与思考"
date: 2026-03-18T19:51:21+08:00
draft: True
tags: ["Linux", "Windows", "DevOps", "Security", "SIEM", "RabbitMQ", "Python"]
categories: ["Tech"]
description: "如何从零开始构建一份可用的轻量级SIEM平台."
---
# 从零手写一套带 SOAR 能力的轻量级跨平台 SIEM 系统的记录与思考

## 1. 为什么要造这个轮子？

- 在日常的蓝队防守和应急响应中，经常遇到这种情况：想用 SIEM，但商业版太贵，开源重型产品（比如 Wazuh）部署繁琐、资源消耗大，而且二次开发的门槛（C/C++）让不少安全工程师望而却步。

为了在靶场或中小规模资产中快速搭建一套“既能看也能用”的平台，我决定用 Python 从零开始构建一个轻量级 SIEM，核心思路就四个字：**轻量、解耦、主动响应**。

## 2. 系统架构：端云分离 + 消息总线

传统模式是探针直连数据库，并发一高就卡死。所以我彻底抛弃了这种方式，采用经典的“端云分离 + 消息总线解耦”架构。
```Text
+-------------------------------------------------------------+
|                     边缘探针 (Agent 端)                     |
|                                                             |
|  +---------+   +----------+   +---------+   +------------+  |
|  | FIM 监控 |   | 身份审计 |   | 进程监控 |   | 网络嗅探器  |  |
|  +---------+   +----------+   +---------+   +------------+  |
|       |             |              |              |         |
|       v             v              v              v         |
|  +-------------------------------------------------------+  |
|  |           事件格式化与 Pydantic 强校验引擎            |  |
|  +-------------------------------------------------------+  |
|       | (Standard JSON)             ^ (Block Command)       |
+-------|-----------------------------|-----------------------+
        |                             |
        v                             |
+-------------------------------------------------------------+
|                      消息总线 (MQ)                          |
|                                                             |
|   [ 队列: siem_events ]     [ 专属指令队列: cmd_agent-id ]  |
+-------------------------------------------------------------+
        |                             ^
        v                             |
+-------------------------------------------------------------+
|                     中央枢纽 (Server 端)                    |
|                                                             |
|  +-------------------------------------------------------+  |
|  | Ingestor (守护进程): 消费事件 -> 存库 -> SOAR 决策引擎|  |
|  +-------------------------------------------------------+  |
|       |                                            |        |
|       v                                            v        |
|  +------------------+                    +---------------+  |
|  | PostgreSQL DB    |                    | Django Web    |  |
|  | (JSONB 泛型存储) |<===================| (可视化大屏)  |  |
|  +------------------+                    +---------------+  |
+-------------------------------------------------------------+
```
### 2.1 边缘探针（Agent）
纯 Python 写，最后用 PyInstaller 打包成独立二进制（不依赖 Python 环境）。探针内置四个模块：

- **文件完整性监控（FIM）**：通过 SHA-256 哈希比对，轮询发现配置文件被篡改或 WebShell 落地。
- **身份审计**：用滑动窗口算法，能抓到跨越多天的 SSH/RDP 慢速爆破。
- **进程监控**：调用 psutil，发现 CPU 飙升（挖矿）或从可疑路径（如 /tmp）启动的进程。
- **旁路流量嗅探**：基于 Scapy 抓包，识别 Nmap 端口扫描等行为。

### 2.2 中央枢纽（Server）
- **Web 控制台**：Django 写的 API + 前端，用来管理资产、看告警、下发配置。
- **数据库**：PostgreSQL，用 JSONB 存各种格式的安全日志。
- **消息队列**：RabbitMQ，让 Agent 和 Server 完全异步。Agent 采集到事件后直接丢进 MQ，Ingestor 守护进程从 MQ 消费数据，避免并发打垮数据库。
- **SOAR 自动响应**：当 Ingestor 判定攻击 IP 为实锤（比如多次爆破命中），会向该 Agent 的专属队列下发阻断指令。Agent 收到后，Linux 调 iptables，Windows 调 netsh，直接在目标主机上封掉攻击 IP。

## 3. 遇到了什么问题

这里分享几个在打包落地、容器化部署阶段我踩过的坑：

### 坑一：RabbitMQ 的 `guest` 账户限制
- **现象**：Server 端放 Docker 里跑，Agent 在宿主机运行，突然连不上 MQ，报错 `StreamLostError (EOF)`。
- **原因**：RabbitMQ 默认的 `guest` 账号有安全限制——**只能从 localhost 登录**。Docker 的网桥做了 NAT，MQ 看到的来源 IP 不是 127.0.0.1，于是强制断开。
- **解法**：不用 `guest`，而是在 `.env` 里定义新账号密码，重建容器时注入自定义超管账号。

### 坑二：Docker Compose 重建时的 `KeyError: 'ContainerConfig'`
- **现象**：修改了 Django 容器的工作目录后，执行 `docker-compose up` 突然报错。
- **原因**：新版 Docker Engine 移除了底层 API 的 `ContainerConfig` 字段，但老版本的 `docker-compose` 在重建容器时会尝试读取它，导致崩溃。
- **解法**：直接 `docker-compose down` 炸掉旧容器，然后重新 `up --build`，绕过了那个字段检查。

### 坑三：环境硬编码导致的可交付性问题
- **现象**：早期把 IP、密码直接写死在代码里，导致打包出的 EXE 换台机器就跑不通。
- **解法**：  
  - **Agent 端**：实现自适应主机指纹（自动抓取 MAC、主机名作为唯一标识），所有可配项（如 MQ 地址）放 YAML 文件里。  
  - **Server 端**：用 `.env` 管理数据库密码、MQ 账号等敏感信息。  
  现在打包出来的二进制，到哪都能用，真正开箱即跑。

## 4. 优缺点复盘

**优点**
- **敏捷**：Python 生态丰富，几天内就能从零跑到原型。
- **解耦彻底**：RabbitMQ 让 Agent 和 Server 互不阻塞，Server 宕机期间，Agent 还能通过持久化队列缓存数据，保证日志不丢。
- **零依赖交付**：PyInstaller 打包 Agent，Docker Compose 编排 Server，部署成本极低。

**缺点**
- **性能瓶颈**：Python 的 GIL 和解释型特性，导致 FIM 轮询时 CPU 开销较大，不适合海量文件场景。
- **监控深度不够**：目前进程监控停留在用户态，抓不到高级 Rootkit 的进程注入。

## 5. 核心技术复盘与收获

写完这个项目，我最大的感触是：**跑通功能只是玩具，设计好底层数据流转和架构才是工程。**

### 5.1 数据结构设计与 Pydantic 强校验
安全日志的特点是“千奇百怪”。FIM 关注哈希值，网络嗅探关注 IP/Port，如果强行在关系型数据库建几十个固定的列，后期维护会让人崩溃。
因此，我采用了 **“信封结构 (Envelope) + 动态负载 (Payload)”** 的设计，并在入库前引入了 `Pydantic` 进行严苛的 Schema 校验。

```python
# 核心数据模型校验示例
from pydantic import BaseModel, Field

class BaseEventData(BaseModel):
    is_attack: bool = False
    
class LoginEventPayload(BaseEventData):
    user: str
    src_ip: str
    status: str = Field(pattern="^(success|failed)$") # 强正则校验
    message: str

# 只有通过校验的干净数据，才会被序列化投入 MQ
```
到了数据库层（PostgreSQL），我直接利用了极其强大的 **JSONB 字段**来存储这个 Payload。JSONB 不仅天然支持无 Schema 存储（Schema-free），还支持创建 GIN 索引，在 Django 大屏上做检索时，速度依然能打。

### 5.2 对 RabbitMQ 消息传递机制的再认识
以前我觉得加个 MQ 会让架构变复杂，但实战后发现它是“救命稻草”。
Agent 采集速度极快，如果没有 MQ 削峰，几百个 Agent 的并发会瞬间把数据库连接池打满。通过 RabbitMQ 的 `basic_ack` 机制，Ingestor 只有在成功把数据存入 DB 后才会向 MQ 确认签收，彻底杜绝了进程崩溃导致的安全日志丢失。

**意外的认知拓展**：在撸完这套 Agent-MQ-Server 的架构后，我突然意识到，这与红队高级 C2（Command & Control）架构中的 Beacon 通信机制如出一辙！将来如果有机会开发 C2 工具，这种基于异步队列的任务下发与回传设计的经验完全可以直接迁移。

### 5.3 跨平台 OS 交互与 SOAR 反制的落地
为了实现主动防御，Agent 必须具备与底层 OS 交互的能力。在获取系统状态时，`psutil` 模块它抹平了 Windows 和 Linux 的底层 API 差异。

而在战术接收器（Receiver）中，我实现了一个极其精简的跨平台拦截逻辑。值得注意的是，**自动化封禁最怕的就是“规则堆积”**，如果不做幂等性校验，防火墙很快就会被几万条重复规则卡死。

```python
def _execute_block(self, ip: str):
    """跨平台封禁逻辑核心（具备幂等性，防重复封禁）"""
    current_os = platform.system()
    if current_os == "Linux":
        # 拦截前先检查：如果已经在黑名单中，则静默跳过 (幂等性)
        check_cmd = f"sudo iptables -C INPUT -s {ip} -j DROP"
        if subprocess.run(check_cmd, shell=True, capture_output=True).returncode == 0:
            return
        
        # 确认无重复后，执行命令
        cmd = f"sudo iptables -I INPUT -s {ip} -j DROP"
        subprocess.run(cmd, shell=True, check=True)
```
这段代码虽然短，但它真正闭环了从“感知”到“响应”的最后一公里。

### 5.4 从用户态到内核态的边界认知
在使用 `psutil` 监控进程时，我深刻意识到了用户态 API 的局限性。它只能抓取那些“乖乖”挂在进程树上的程序，一旦遇到修改系统调用表的 Rootkit 进程隐藏，或者是稍纵即逝的短生命周期恶意进程，用户态轮询（Polling）就会立刻变成瞎子。
这也促使我将目光投向了下一代技术：**eBPF**。只有深入内核态，利用事件驱动去挂钩底层的 `sys_execve`，才是未来终端安全（EDR/SIEM）的最终解法。

## 6. 未来规划（v2.0）

- **Agent 换语言**：用 Golang 或 Rust 重写，释放性能，降低内存占用。
- **内核级采集**：Linux 端引入 eBPF，把轮询改成事件驱动，实时捕获文件操作和网络连接。
- **检测即代码**：剥离硬编码的研判逻辑，引入 Sigma 规则引擎，让系统可以动态加载新规则。

---

>造轮子的过程希望这篇文章能给同样在捣鼓蓝队开发的朋友一点启发。
>项目代码已在GitHub开源：[https://github.com/alberadam/Mini-SIEM](https://github.com/alberadam/Mini-SIEM)
---
