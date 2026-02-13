---
title: "Linux 服务器初始化与安全加固指南：从零构建高效军火库"
date: 2026-02-13T15:00:00+08:00
draft: Ture
tags: ["Linux", "DevOps", "Security", "Proxy", "Shell", "Mihomo"]
categories: ["Engineering"]
summary: "一份经过实战验证的 Ubuntu Server 初始化 SOP。涵盖源优化、SSH 密钥固化、Zsh 环境搭建，以及基于 Mihomo 的智能代理控制脚本实现。"
weight: 1
---

## 0x01 前言

这是我配置 Ubuntu Server 虚拟机时记录的**标准操作程序 (SOP)**。文章记录了部分典型问题及经过验证的解决方案。无论你是刚接触 Linux 的新手，还是需要快速搭建开发环境的老手，这份指南都能帮你**绕过深坑**，建立系统化的配置流程。

---

## 0x02 系统基础配置：地基

### 1. 源优化与更新陷阱
国内环境下，第一步必须是更换镜像源。

> **⚠️ 避坑指南：**
> * `apt update` 仅更新包列表，`upgrade` 才是真正升级软件。原则是**先 update，再 upgrade** 。
> * 如果在 update 时长时间卡住，请立即更换源 。

```bash
# 1. 备份原文件
sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak

# 2. 批量替换为阿里云源 (以 Ubuntu 22.04 为例)
sudo sed -i 's/[archive.ubuntu.com/mirrors.aliyun.com/g](https://archive.ubuntu.com/mirrors.aliyun.com/g)' /etc/apt/sources.list
sudo sed -i 's/[security.ubuntu.com/mirrors.aliyun.com/g](https://security.ubuntu.com/mirrors.aliyun.com/g)' /etc/apt/sources.list

# 3. 执行更新
sudo apt-get update && sudo apt-get upgrade -y

# 4. 安装基础工具
sudo apt-get install -y curl wget git vim htop net-tools 

```

### 2. 网络配置 (Netplan 静态 IP)

服务器IP不固定是大忌。Ubuntu 18.04+ 使用 Netplan 配置网络。

**配置文件：** `/etc/netplan/00-installer-config.yaml`

```yaml
network:
  version: 2
  ethernets:
    ens33:  # ⚠️ 请先用 ip link show 确认你的实际网卡名 
      dhcp4: no
      addresses: [192.168.1.100/24]  # ⚠️ CIDR格式，不要漏掉 /24 
      routes:
        - to: default
          via: 192.168.1.1  # 网关
      nameservers:
        addresses: [223.5.5.5, 114.114.114.114] 

```

应用配置：`sudo netplan apply` 。

---

## 0x03 SSH 安全加固：盾牌

目标：**彻底禁用密码登录，仅允许密钥认证**。

### 1. 密钥生成与上传

在 Windows 客户端（PowerShell）生成并上传：

```powershell
# 生成密钥
ssh-keygen -t rsa -b 4096 -C "admin@server"

# 上传公钥 (方法1: ssh-copy-id)
ssh-copy-id -i ~/.ssh/id_rsa.pub user@192.168.1.100

# 上传公钥 (方法2: 手动)
type ~/.ssh/id_rsa.pub | ssh user@192.168.1.100 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys" 

```

### 2. 配置文件加固 (`/etc/ssh/sshd_config`)

这是最容易踩坑的地方，很多人以为关了 `PasswordAuthentication` 就安全了，其实不然。

```ssh
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin no
# ⚠️ 关键配置：强制要求公钥认证，防止 fallback 到密码
AuthenticationMethods publickey 

```

### 3. 权限修正 (Permission is King)

权限过大是 SSH 连接被拒的常见原因：

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
sudo systemctl restart sshd 

```

---

## 0x04 网络军火库：Mihomo 透明代理 (重点)

作为开发和安全人员，拉取 Docker 镜像、Git Clone、安装 NPM 包如果网络不通是致命的。这里我们手动部署 **Mihomo (Clash Core)** 并配合自写脚本实现**全系统接管**。

### 1. 下载与安装

由于 Linux 版本的 Mihomo 只是一个二进制文件，安装非常简单。

```bash
# 1. 创建配置目录
sudo mkdir -p /etc/mihomo

# 2. 下载 Mihomo 内核 (请去 GitHub Releases 下载对应架构版本，通常是 amd64)
# 示例链接，请替换为最新版
wget [https://github.com/MetaCubeX/mihomo/releases/download/v1.18.0/mihomo-linux-amd64-v1.18.0.gz](https://github.com/MetaCubeX/mihomo/releases/download/v1.18.0/mihomo-linux-amd64-v1.18.0.gz)

# 3. 解压并重命名
gzip -d mihomo-linux-amd64-v1.18.0.gz
sudo mv mihomo-linux-amd64-v1.18.0 /usr/local/bin/mihomo

# 4. 赋予执行权限
sudo chmod +x /usr/local/bin/mihomo 

```

### 2. 配置文件 (`config.yaml`)

将你的订阅配置下载并重命名为 `config.yaml`，放入 `/etc/mihomo/` 。
确保文件中包含以下基础设置：

```yaml
port: 7890          # HTTP 代理端口
socks-port: 7891    # SOCKS5 代理端口
mixed-port: 7893    # 混合端口
allow-lan: true     # 允许局域网连接
mode: Rule          # 默认为规则模式 
external-controller: 0.0.0.0:9090 # API 端口，用于脚本控制

```

### 3. 托管为 Systemd 服务

为了让代理开机自启且后台运行，我们需要创建一个服务文件 。

创建文件：`sudo nano /etc/systemd/system/mihomo.service`

```ini
[Unit]
Description=mihomo Proxy Service
After=network.target

[Service]
Type=simple
User=root
# 指定配置文件目录
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo
Restart=on-failure

[Install]
WantedBy=multi-user.target 

```

启用并启动服务：

```bash
sudo systemctl enable mihomo
sudo systemctl start mihomo

```

### 4. 智能控制脚本 (`mc`)

为了避免每次手动敲 `export http_proxy...`，我编写了一个名为 `mc` (Mihomo Control) 的脚本。它支持**模式切换**、**系统代理注入**和**状态检查**。

创建脚本：`sudo nano /usr/local/bin/mc`

```bash
#!/bin/bash
# mihomo 智能控制脚本

# --- 配置参数 ---
MIHOMO_CONFIG="/etc/mihomo/config.yaml"
PROXY_HOST="127.0.0.1"
HTTP_PORT="7890"

# --- 功能 1: 模式切换 (Rule/Global/Direct) ---
switch_mode() {
    echo "Switching to $1 mode..."
    # 使用 sed 直接修改配置文件中的 mode 字段
    case $1 in
        global) sudo sed -i 's/^mode: .*/mode: Global/' "$MIHOMO_CONFIG" ;;
        rule)   sudo sed -i 's/^mode: .*/mode: Rule/' "$MIHOMO_CONFIG"   ;;
        direct) sudo sed -i 's/^mode: .*/mode: Direct/' "$MIHOMO_CONFIG" ;;
    esac
    # 重启服务使配置生效
    sudo systemctl restart mihomo
    echo "Done."
}

# --- 功能 2: 注入代理 (Shell/Git/APT) ---
set_local_proxy() {
    # 1. 环境变量 (当前 Shell 生效)
    export http_proxy="http://$PROXY_HOST:$HTTP_PORT"
    export https_proxy="http://$PROXY_HOST:$HTTP_PORT"
    
    # 2. Git 代理
    git config --global http.proxy "http://$PROXY_HOST:$HTTP_PORT"
    git config --global https.proxy "http://$PROXY_HOST:$HTTP_PORT"
    
    # 3. APT 代理 (系统更新用)
    echo "Acquire::http::Proxy \"http://$PROXY_HOST:$HTTP_PORT\";" | sudo tee /etc/apt/apt.conf.d/95proxy > /dev/null
    echo "Acquire::https::Proxy \"http://$PROXY_HOST:$HTTP_PORT\";" | sudo tee -a /etc/apt/apt.conf.d/95proxy > /dev/null
    
    echo "✅ Proxy set for Shell, Git, and APT."
}

# --- 功能 3: 清除代理 ---
clear_local_proxy() {
    unset http_proxy https_proxy
    git config --global --unset http.proxy
    git config --global --unset https.proxy
    sudo rm -f /etc/apt/apt.conf.d/95proxy
    echo "🚫 Proxy cleared."
}

# --- 功能 4: 测试连接 ---
test_proxy() {
    echo "Direct IP: $(curl -s --connect-timeout 2 [https://api.ipify.org](https://api.ipify.org))"
    echo "Proxy  IP: $(curl -s --connect-timeout 2 --proxy http://$PROXY_HOST:$HTTP_PORT [https://api.ipify.org](https://api.ipify.org))"
}

# --- 主逻辑 ---
case "$1" in
    start)   sudo systemctl start mihomo ;;
    stop)    sudo systemctl stop mihomo ;;
    status)  sudo systemctl status mihomo ;;
    global|rule|direct) switch_mode $1 ;; # 切换模式 
    proxy-on)  set_local_proxy ;;         # 开启代理 
    proxy-off) clear_local_proxy ;;       # 关闭代理 
    test)      test_proxy ;;              # 测试连接 
    *) echo "Usage: mc {start|stop|status|global|rule|direct|proxy-on|proxy-off|test}" ;;
esac

```

**安装脚本：**

```bash
sudo chmod +x /usr/local/bin/mc

```

**使用别名 (可选)：**
在 `~/.bashrc` 中添加：

```bash
alias proxy='source <(mc proxy-on)' # 技巧：source 才能让 export 在当前终端生效
alias unproxy='source <(mc proxy-off)'

```

---

## 0x05 打造极致终端 (Zsh + Oh My Zsh)

最后，给你的 Shell 穿上战衣。

1. **安装 Zsh 与 Oh My Zsh**:
```bash
sudo apt install zsh git curl -y
sh -c "$(curl -fsSL [https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh](https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh))" 

```


2. **安装核心插件**:
  
- **zsh-autosuggestions**: 历史命令自动补全 。


  
- **zsh-syntax-highlighting**: 语法高亮 。




```bash
git clone [https://github.com/zsh-users/zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone [https://github.com/zsh-users/zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

```


1. **配置 `.zshrc**`:
```bash
plugins=(git sudo zsh-autosuggestions zsh-syntax-highlighting extract web-search) 

```



---

## 0x06 总结

至此，一台**网络通畅、权限安全、终端高效**的 Linux 开发机就初始化完成了。

**常用操作速查：**

* 开全局代理：`mc global`
* 终端开启代理：`mc proxy-on` (或 `source /usr/local/bin/mc proxy-on`)
* 系统更新：`sudo apt update` (会自动走 APT 代理)
* 测试网络：`mc test`

希望这份 SOP 能帮你节省时间，专注于真正的技术研究。
- 此后我会考虑将上述所有操作集成到init.sh脚本中，一键自动初始化服务器配置，用户只需要按需求选择初始化配置选项，输入代理连接地址即可实现上述所有的初始化操作。

