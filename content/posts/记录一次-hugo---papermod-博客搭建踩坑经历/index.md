---
title: "记录一次 Hugo + PaperMod 博客搭建踩坑经历"
date: 2026-02-10T20:00:00+08:00
draft: false
tags: ["Hugo", "DevOps", "PowerShell", "Blog"]
categories: ["Engineering"]
summary: "如何用 PowerShell 脚本自动化管理 Hugo 博客？这里有我的一键部署方案。"
---

## 为什么选择 Hugo？

相比于 Hexo，Hugo 的速度简直是**闪电般**的快。而且 PaperMod 主题极致简洁，非常符合黑客的审美。

## 自动化工作流

为了提高效率，我编写了一个 `manage.ps1` 脚本，涵盖了以下功能：

1.  **New**: 自动创建 Page Bundle 结构。
2.  **Preview**: 本地预览。
3.  **Deploy**: 自动推送到 GitHub。

### 脚本片段

```powershell
function Deploy-Blog {
    Write-Host "3. Pushing to GitHub..." -ForegroundColor Yellow
    git push origin main
}
```
>