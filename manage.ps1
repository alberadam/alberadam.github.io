<#
.SYNOPSIS
    安全博客管理脚本 (Windows PowerShell 版)
    功能：新建文章、本地预览、一键发布
.DESCRIPTION
    用于管理基于Hugo的安全博客，提供文章创建、本地预览和部署功能。
    作者：Albert
    版本：1.2 (修复Join-Path参数问题)
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
    # 修复Join-Path参数顺序问题
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
        Write-Host "   Blog URL: https://alberadam.github.io" -ForegroundColor Cyan
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