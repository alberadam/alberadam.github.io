---
title: "安全工程师的自动化静态博客构建与踩坑实录"
date: 2026-03-18T19:51:21+08:00
draft: false
tags: ["Hugo", "DevOps", "PowerShell", "Blog", "自动化", "踩坑"]
categories: ["Engineering"]
summary: "为什么我不推荐技术人员使用传统博客平台？本文记录了我从零构建 Hugo + PaperMod 静态博客的全过程，详细复盘了环境配置、图床搭建、GitHub 部署中的所有“天坑”，并分享了一套个人自用的自动化管理脚本。"
weight: 1
---

## 0x01 引言：为什么要自己造轮子？

作为一名安全工程师，我经常需要记录漏洞复现过程、实战溯源笔记以及开发各种安全工具（如 G-Baseline-Auditor、Argus-IR）的思考。

起初，我尝试过部分泛技术社区，但很快遇到了不可忍受的痛点：
1. **充斥广告与弹窗**，阅读体验极差。
2. **数据不属于自己**，随时面临被删帖的风险，且无法通过 Git 进行版本控制。
3. **Markdown 支持度参差不齐**，对大段代码高亮极其不友好。

为了追求极致的**控制权、访问速度与美观**，我决定抛弃重型 CMS 平台，从零构建一套基于 **Hugo + GitHub Pages** 的纯静态博客体系。我的目标是：**将“写博客”变成像“写代码、提 PR”一样丝滑的工程化体验。**

---

## 0x02 基础环境搭建与“出师不利”

Hugo 是基于 Go 语言开发的极速静态网站生成器，效率非常高。我在 Windows 环境下使用 `winget` 进行安装。

```powershell
# 安装 Git
winget install --id Git.Git -e --source winget
# 安装 Hugo (注意这里的坑！)
winget install Hugo.Hugo.Extended
```

### 🧨 踩坑 1：Hugo 版本陷阱与环境变量幽灵
**症状**：一开始我只安装了普通的 Hugo 版本，结果在拉取 PaperMod 主题后，运行直接报错，提示无法处理 SCSS 文件。此外，安装完成后在终端输入 `hugo version`，直接飘红报错：
> `hugo : 无法将“hugo”项识别为 cmdlet、函数、脚本文件或可运行程序的名称...`

**解法**：
1. **必须安装 Extended 版本**：很多现代主题（如 PaperMod）依赖 C++ 编译器来处理 SCSS/SASS 样式，普通的 Hugo 版本不支持。
2. **环境变量未刷新**：Windows 的 `winget` 安装后，环境变量往往不会立即生效。**最暴力的解法是彻底关闭所有 VS Code 和 PowerShell 窗口重新打开，或者直接重启电脑**。如果仍不行，需要手动将 `%LOCALAPPDATA%\Microsoft\WinGet\Links` 添加到系统的 Path 环境变量中。

---

## 0x03 博客初始化与 GitHub Pages 部署

环境跑通后，开始生成博客结构并部署到 GitHub。

### 1. 初始化与主题配置
```bash
# 生成站点目录
hugo new site my-blog
cd my-blog

# 将 PaperMod 主题作为 Git 子模块引入
git init
git submodule add [https://github.com/adityatelange/hugo-PaperMod](https://github.com/adityatelange/hugo-PaperMod) themes/PaperMod
```

### 🧨 踩坑 2：主题克隆后的“白屏死机”与“搜索 404”
**症状 1**：在另一台电脑上 `git clone` 仓库后，本地运行 `hugo server` 发现页面一片空白。
**解法**：直接 clone 仓库不会自动拉取 `themes/PaperMod` 里的内容，必须执行 `git submodule update --init --recursive` 初始化子模块。

**症状 2**：PaperMod 顶部的搜索框点击后直接 404。
**解法**：Hugo 默认不生成搜索所需的 JSON 索引文件。必须在 `hugo.toml` 中显式声明：
```toml
[outputs]
  home = ["HTML", "RSS", "JSON"] # 必须添加 JSON
```
同时，手动在 `content` 目录下创建一个包含 `layout: "search"` 元数据的 `search.md` 文件。
```text
title: "搜索"
layout: "search"
summary: "search"
placeholder: "请输入关键词..."
---
```
### 2. 配置 GitHub Pages
1. 在 GitHub 创建一个名为 `你的用户名.github.io` 的公有仓库。
2. 将本地代码 Push 上去。
3. 进入仓库的 **Settings -> Pages**，将 `Source` 设置为 GitHub Actions（如果使用自动化流）或者指向你存放静态页面 HTML 的分支/目录。

### 🧨 踩坑 3：“薛定谔的部署”——本地有，线上无
**症状**：文章写完后，运行 `hugo server -D` 本地预览一切正常。但是通过构建命令 `hugo --minify` 生成并 Push 到 GitHub 后，线上死活看不到新文章。
**解法**：新建文章时，头部的 Front Matter 默认带有 `draft: true`。**Hugo 在正式编译时，默认会忽略所有草稿文件！** 必须将其改为 `draft: false` 才能被渲染成 HTML。

---

## 0x04 图床工作流：PicGo 

静态博客的核心原则是**“文章与图片解耦”**。图片必须存放在云端图床，并在 Markdown 中以外链形式引用。我选择了 **PicGo + SM.MS**（后期可无缝切换至 GitHub + jsDelivr）。

### 🧨 踩坑 4：DNS 污染与 VS Code 插件之殇
这是搭建过程中最折磨人的环节。
**症状 1**：PicGo 疯狂弹窗报错，查看 `picgo.log` 发现如下致命错误：
> `Error: getaddrinfo ENOTFOUND smms`
> `"url": "https://smms/api/v2/upload"`

**解法**：手残将配置文件中的域名 `sm.ms` 写成了 `smms`（少了一个点），导致计算机无法解析该域名。将其更正后，并在 PicGo 中配置本地代理（如 `127.0.0.1:7890`）解决国内网络连通性问题。(Tip:`目前sm。ms域名已变更`)

**症状 2**：在 VS Code 中使用 `vs-picgo` 插件上传图片，频繁报错 `command 'picgo.uploadImageFromClipboard' not found`。
**解法**：VS Code 的插件环境有时与本地桌面版冲突。**卸载插件，采用“桌面版 APP + 全局快捷键”的物理隔离流。** 截图 -> `Ctrl+Shift+P` 后台静默上传 -> 回到编辑器 `Ctrl+V` 粘贴 URL。

---

## 0x05 核心武器：PowerShell 自动化工作流

为了不让繁琐的命令敲击消耗写作热情，我用 PowerShell 编写了一个轻量级的 `manage.ps1` 脚本，将整个 DevOps 流程收敛为一个控制台菜单。

**脚本亮点：**
1. **自动 Page Bundle**：输入文章名，自动创建同名文件夹和 `index.md`，彻底解决图片、附件的路径管理问题。
2. **防呆设计**：自动检测环境依赖，捕捉编译异常。
3. **一键全自动部署**：执行 `hugo --minify` -> `git add` -> 自动生成带时间戳的 `commit` -> `git push` 一气呵成。

- 终端敲入 `.\manage.ps1` -> 选 1 新建 -> 写作 -> 选 4 发布。
```powershell
<#
.SYNOPSIS
    安全博客管理脚本 (Windows PowerShell 版)
    功能：新建文章、本地预览、一键发布
.DESCRIPTION
    用于管理基于Hugo的安全博客，提供文章创建、本地预览和部署功能。
    作者：Albert
    版本：1.2 
#>

# 检查必要工具是否安装
function Test-RequiredTools {
    $tools = @("hugo", "git")
    $missing = @()
    
    foreach ($tool in $tools) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            $missing += $tool
        }
    }
    
    if ($missing.Count -gt 0) {
        Write-Host "ERROR: Missing required tools: $($missing -join ', ')" -ForegroundColor Red
        Write-Host "Please install:" -ForegroundColor Yellow
        foreach ($tool in $missing) {
            switch ($tool) {
                "hugo" { Write-Host "  Hugo: https://github.com/gohugoio/hugo/releases" }
                "git"  { Write-Host "  Git: https://git-scm.com/download/win" }
            }
        }
        return $false
    }
    return $true
}

function Show-Menu {
    Clear-Host
    Write-Host "===============================" -ForegroundColor Cyan
    Write-Host "    Security Blog Manager v1.2  " -ForegroundColor Cyan
    Write-Host "===============================" -ForegroundColor Cyan
    Write-Host "Current directory: $(Get-Location)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "1. NEW - Create new post"
    Write-Host "2. PREVIEW - Live preview" 
    Write-Host "3. BUILD - Build only"
    Write-Host "4. DEPLOY - One-click deploy"
    Write-Host "5. STATUS - Blog status"
    Write-Host "6. EXIT - Exit"
    Write-Host "-------------------------------" -ForegroundColor DarkGray
}

function New-Post {
    $title = Read-Host "Enter post title"
    if (-not $title) {
        Write-Host "ERROR: Title cannot be empty" -ForegroundColor Red
        return
    }
    
    # Generate safe filename
    $filename = $title -replace '[^\w\-\.]', '-' -replace '\s+', '-'
    $filename = $filename.ToLower()
    
    # 调试信息
    Write-Host "DEBUG: Generated filename: $filename" -ForegroundColor Gray
    
    # Use Page Bundle mode (create folder)
    $postDir = Join-Path -Path "content" -ChildPath "posts"
    $postDir = Join-Path -Path $postDir -ChildPath $filename
    $postFile = Join-Path -Path $postDir -ChildPath "index.md"
    
    Write-Host "DEBUG: Post directory: $postDir" -ForegroundColor Gray
    Write-Host "DEBUG: Post file: $postFile" -ForegroundColor Gray
    
    # Create directory
    try {
        New-Item -ItemType Directory -Force -Path $postDir -ErrorAction Stop | Out-Null
        Write-Host "DEBUG: Directory created successfully" -ForegroundColor Gray
    }
    catch {
        Write-Host "ERROR: Failed to create directory: $_" -ForegroundColor Red
        return
    }
    
    # Create post content
    $date = Get-Date -Format "yyyy-MM-ddTHH:mm:ss+08:00"
    
    # Create content line by line
    $lines = @(
        "---",
        "title: `"$title`"",
        "date: $date",
        "draft: true",
        "tags: [`"Uncategorized`"]",
        "categories: [`"Tech`"]",
        "description: `"Post description...`"",
        "---",
        "",
        "## Introduction",
        "",
        "Start writing your security technical article...",
        "",
        "## Security Disclaimer",
        "All technical content is for authorized testing and security protection learning only."
    )
    
    try {
        Set-Content -Path $postFile -Value $lines -Encoding UTF8 -ErrorAction Stop
        Write-Host "SUCCESS: Post created: $postFile" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Failed to create file: $_" -ForegroundColor Red
        return
    }
    
    # Try to open with default editor
    $editor = "code"  # VS Code
    try {
        Start-Process $editor -ArgumentList $postFile -ErrorAction Stop
        Write-Host "INFO: Opened in editor" -ForegroundColor Cyan
    }
    catch {
        Write-Host "INFO: File location: $postFile" -ForegroundColor Yellow
        Write-Host "      Please open manually" -ForegroundColor Gray
    }
}

function Start-Preview {
    Write-Host "Starting local preview server..." -ForegroundColor Yellow
    Write-Host "   Access: http://localhost:1313" -ForegroundColor Cyan
    Write-Host "   Press Ctrl+C to stop" -ForegroundColor Gray
    Write-Host ""
    
    # Stop any existing Hugo process
    Get-Process hugo -ErrorAction SilentlyContinue | Stop-Process -Force
    
    # Start new preview
    hugo server -D --bind 0.0.0.0 --port 1313
}

function Build-Blog {
    Write-Host "Building blog..." -ForegroundColor Yellow
    $result = hugo --minify 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $pageCount = (Get-ChildItem "public" -Recurse -Filter "*.html" -ErrorAction SilentlyContinue).Count
        Write-Host "SUCCESS: Built $pageCount pages" -ForegroundColor Green
        Write-Host "   Output: public/" -ForegroundColor Cyan
    } else {
        Write-Host "ERROR: Build failed!" -ForegroundColor Red
        Write-Host $result -ForegroundColor Red
    }
}

function Deploy-Blog {
    # 1. Build
    Write-Host "1. Building static pages..." -ForegroundColor Yellow
    hugo --minify
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Build failed, deployment stopped" -ForegroundColor Red
        return
    }
    
    # 2. Git operations
    Write-Host "2. Committing changes..." -ForegroundColor Yellow
    
    # Check for changes
    $changes = git status --porcelain
    if (-not $changes) {
        Write-Host "   WARNING: No changes detected" -ForegroundColor Yellow
        $confirm = Read-Host "Continue push? (y/N)"
        if ($confirm -ne 'y') { return }
    }
    
    git add .
    
    $defaultMsg = "Update blog content $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $msg = Read-Host "Enter commit message (default: $defaultMsg)"
    if (-not $msg) { $msg = $defaultMsg }
    
    git commit -m $msg
    
    # 3. Push
    Write-Host "3. Pushing to GitHub..." -ForegroundColor Yellow
    git push origin main
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: Deployed!" -ForegroundColor Green
        Write-Host "   Blog URL: https://你的博客地址" -ForegroundColor Cyan
        Write-Host "   Wait 1-2 minutes for updates..." -ForegroundColor Gray
    } else {
        Write-Host "ERROR: Push failed!" -ForegroundColor Red
        Write-Host "   Check network or Git config" -ForegroundColor Yellow
    }
}

function Show-Status {
    Write-Host "Blog Status Report" -ForegroundColor Cyan
    Write-Host "==================" -ForegroundColor Cyan
    
    # Hugo version
    $hugoVersion = hugo version 2>&1 | Select-Object -First 1
    Write-Host "Hugo version: $hugoVersion" -ForegroundColor Gray
    
    # Post statistics
    $posts = Get-ChildItem "content\posts" -Recurse -Filter "*.md" -ErrorAction SilentlyContinue
    $published = Select-String -Path "content\posts\*.md" -Pattern "draft: false" | Measure-Object | Select-Object -ExpandProperty Count
    $drafts = Select-String -Path "content\posts\*.md" -Pattern "draft: true" | Measure-Object | Select-Object -ExpandProperty Count
    
    Write-Host "Post statistics:" -ForegroundColor Gray
    Write-Host "  Total: $($posts.Count)" -ForegroundColor White
    Write-Host "  Published: $published" -ForegroundColor Green
    Write-Host "  Drafts: $drafts" -ForegroundColor Yellow
    
    # Git status
    Write-Host "Git status:" -ForegroundColor Gray
    git status --short 2>$null
    
    # Last commit
    $lastCommit = git log --oneline -1 2>$null
    if ($lastCommit) {
        Write-Host "Last commit: $lastCommit" -ForegroundColor Gray
    }
}

# Main program
Clear-Host
Write-Host "Security Blog Management System" -ForegroundColor Green
Write-Host "===============================" -ForegroundColor Green

# Check required tools
if (-not (Test-RequiredTools)) {
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Check if in blog directory
if (-not (Test-Path "hugo.toml")) {
    Write-Host "WARNING: Hugo config (hugo.toml) not found" -ForegroundColor Yellow
    Write-Host "Please run this script in blog root directory" -ForegroundColor Red
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Main loop
while ($true) {
    Show-Menu
    $choice = Read-Host "Select operation [1-6]"

    switch ($choice) {
        "1" { New-Post }
        "2" { Start-Preview }
        "3" { Build-Blog }
        "4" { Deploy-Blog }
        "5" { Show-Status }
        "6" { 
            Write-Host "Goodbye!" -ForegroundColor Cyan
            exit 0 
        }
        default {
            Write-Host "ERROR: Invalid input, choose 1-6" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
    
    Write-Host ""
    Write-Host "Press any key to continue..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
```
---

## 0x06 一文多发：如何优雅地分发内容

博客是我的“根据地”，但我同样需要将技术文章分发到掘金、微信公众号等平台建立个人 IP。

由于我的 Markdown 中采用了云端图床外链：
1. **对于掘金/CSDN 等泛技术社区**：直接用正则（`^---[\s\S]*?---`）删掉头部的 YAML 元数据，全选粘贴即可，平台会自动转存图片。
2. **对于微信公众号（排版重灾区）**：放弃所有不稳定的同步插件，直接使用开发者专用的 **[Doocs/md](https://doocs.github.io/md/)** 转换器。将纯净的 Markdown 丢进去，选择极客风格的高亮主题，点击“复制”，再粘贴进公众号后台。代码块、缩进和列表层级极其稳定，从此告别排版焦虑。

---

## 0x07 结语：工具服务于内容

折腾架构、写自动化脚本固然爽，但不要陷入“差生文具多”的陷阱。

构建 Argus-IR 框架让我理解了 Windows 底层机制，而搭建这个博客系统，则让我体验了一把完整的 DevOps 流程。地基已经打好，接下来要做的，就是持续输出高质量的安全技术内容。

> “Talk is cheap, show me the code. 然后，把它写进博客里。”


