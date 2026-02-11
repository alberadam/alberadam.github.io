---
title: "内网渗透：使用 Python 编写简易端口扫描器"
date: 2026-02-11T16:56:31+08:00
draft: false
tags: ["Python", "Network", "Scanner"]
categories: ["Red Team"]
summary: "在内网环境中，有时候我们需要一个轻量级的端口扫描工具。本文介绍如何用 Python 的 socket 模块实现一个多线程扫描器。"
weight: 1
---

## 0x01 前言

在内网渗透测试中，我们并不总是有权限使用 Nmap。这时候，自带环境的 Python 就成了我们的瑞士军刀。

## 0x02 核心代码实现

利用 `socket` 模块，我们可以快速探测目标端口是否开放。

```python
import socket
import threading

def scan_port(ip, port):
    try:
        # 创建 socket 对象
        sock = socket.socket(socket.socket.AF_INET, socket.socket.SOCK_STREAM)
        sock.settimeout(1)
        
        # 尝试连接
        result = sock.connect_ex((ip, port))
        if result == 0:
            print(f"[+] Port {port} is OPEN on {ip}")
        sock.close()
    except Exception as e:
        pass

# 多线程扫描示例
target_ip = "192.168.1.100"
for port in range(20, 1025):
    t = threading.Thread(target=scan_port, args=(target_ip, port))
    t.start()
```
