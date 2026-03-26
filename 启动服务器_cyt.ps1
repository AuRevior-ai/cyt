$ErrorActionPreference = 'Stop'

# Ensure UTF-8 output in Windows terminals (VS Code, conhost, Windows Terminal).
# Without this, PowerShell 5.1 often outputs GBK/936 and Chinese text becomes garbled.
try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [Console]::InputEncoding = $utf8NoBom
    [Console]::OutputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom
} catch {
    # Best-effort: if the host forbids changing encodings, continue.
}

# Always serve from this script's folder to avoid 404
Set-Location -LiteralPath $PSScriptRoot

$port = 8001
$page = '生日快乐_cyt.html'
$url = "http://localhost:$port/$page"

Write-Host "🚀 正在启动cyt专属生日祝福服务器..." -ForegroundColor Cyan
Write-Host ""
Write-Host "📂 服务器目录: $PWD" -ForegroundColor DarkCyan
Write-Host "🌐 访问地址: http://localhost:$port" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "🎂 cyt生日快乐页面: $url" -ForegroundColor Yellow
Write-Host ""
Write-Host "⚠️  请保持此窗口打开，关闭后服务器将停止" -ForegroundColor DarkYellow
Write-Host "📝 按 Ctrl+C 可以停止服务器" -ForegroundColor DarkYellow
Write-Host ""
Write-Host "💡 使用说明：" -ForegroundColor Green
Write-Host "   1. 将cyt的照片重命名为 1.jpg, 2.jpg, 3.jpg... 等格式" -ForegroundColor Green
Write-Host "   2. 放入 图片/ 文件夹中" -ForegroundColor Green
Write-Host "   3. 页面会自动加载并显示照片" -ForegroundColor Green
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

function Start-HttpServer([string[]]$command, [string]$label) {
    Write-Host "使用 $label 启动服务器..." -ForegroundColor Cyan
    & $command[0] @($command[1..($command.Length-1)])
}

function Test-RealPython([string]$commandName) {
    $cmd = Get-Command $commandName -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return $false
    }

    # Windows "App Execution Alias" python stub (WindowsApps) is often a 0-byte file.
    try {
        if ($cmd.Source -like '*\\Microsoft\\WindowsApps\\python.exe') {
            $stub = Get-Item -LiteralPath $cmd.Source -ErrorAction SilentlyContinue
            if ($stub -and $stub.Length -eq 0) {
                return $false
            }
        }
    } catch {
        # ignore
    }

    # Smoke-test: make sure it can actually run.
    try {
        & $commandName -c "import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)" | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Get-ContentType([string]$filePath) {
    $ext = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()
    switch ($ext) {
        '.html' { 'text/html; charset=utf-8' }
        '.htm'  { 'text/html; charset=utf-8' }
        '.css'  { 'text/css; charset=utf-8' }
        '.js'   { 'application/javascript; charset=utf-8' }
        '.json' { 'application/json; charset=utf-8' }
        '.png'  { 'image/png' }
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.gif'  { 'image/gif' }
        '.svg'  { 'image/svg+xml' }
        '.ico'  { 'image/x-icon' }
        '.glb'  { 'model/gltf-binary' }
        '.gltf' { 'model/gltf+json; charset=utf-8' }
        '.bin'  { 'application/octet-stream' }
        '.mp3'  { 'audio/mpeg' }
        '.mp4'  { 'video/mp4' }
        default { 'application/octet-stream' }
    }
}

function Start-PowerShellStaticServer([int]$Port, [string]$Root, [string]$DefaultPage) {
    $listener = New-Object System.Net.HttpListener
    $prefix = "http://localhost:$Port/"
    $listener.Prefixes.Add($prefix)

    try {
        $listener.Start()
    } catch {
        Write-Host "无法启动服务器（端口可能被占用或权限不足）：$($_.Exception.Message)" -ForegroundColor Red
        Read-Host "按回车键退出" | Out-Null
        exit 1
    }

    Write-Host "使用 PowerShell 内置静态服务器启动（无需 Python）..." -ForegroundColor Cyan
    Write-Host "监听地址: $prefix" -ForegroundColor DarkCyan
    Write-Host "按 Ctrl+C 停止服务器" -ForegroundColor DarkYellow

    $rootFull = [System.IO.Path]::GetFullPath($Root)

    try {
        while ($listener.IsListening) {
            $context = $null
            try {
                $context = $listener.GetContext()
            } catch {
                break
            }

            try {
                $rawPath = $context.Request.Url.AbsolutePath
                $relPath = [Uri]::UnescapeDataString($rawPath).TrimStart('/')

                if ([string]::IsNullOrWhiteSpace($relPath)) {
                    $relPath = $DefaultPage
                }

                $relPath = $relPath -replace '/', '\\'
                $candidate = Join-Path -Path $Root -ChildPath $relPath
                $fileFull = [System.IO.Path]::GetFullPath($candidate)

                if (-not $fileFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $context.Response.StatusCode = 403
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes('403 Forbidden')
                    $context.Response.ContentType = 'text/plain; charset=utf-8'
                    $context.Response.ContentLength64 = $bytes.Length
                    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                    continue
                }

                if (Test-Path -LiteralPath $fileFull -PathType Container) {
                    $index = Join-Path -Path $fileFull -ChildPath 'index.html'
                    if (Test-Path -LiteralPath $index -PathType Leaf) {
                        $fileFull = $index
                    }
                }

                if (-not (Test-Path -LiteralPath $fileFull -PathType Leaf)) {
                    $context.Response.StatusCode = 404
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
                    $context.Response.ContentType = 'text/plain; charset=utf-8'
                    $context.Response.ContentLength64 = $bytes.Length
                    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                    continue
                }

                $bytes = [System.IO.File]::ReadAllBytes($fileFull)
                $context.Response.StatusCode = 200
                $context.Response.ContentType = Get-ContentType $fileFull
                $context.Response.ContentLength64 = $bytes.Length
                $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            } catch {
                try {
                    $context.Response.StatusCode = 500
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("500 Internal Server Error\n$($_.Exception.Message)")
                    $context.Response.ContentType = 'text/plain; charset=utf-8'
                    $context.Response.ContentLength64 = $bytes.Length
                    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                } catch {
                }
            } finally {
                try { $context.Response.OutputStream.Close() } catch {}
            }
        }
    } finally {
        try { $listener.Stop() } catch {}
        try { $listener.Close() } catch {}
    }
}

# Prefer a real Python (not the WindowsApps stub). If unavailable, use a built-in PS static server.
if (Test-RealPython 'python') {
    Start-HttpServer @('python','-m','http.server',$port) 'python'
    exit 0
}

Write-Host "检测到的 python 可能是 Windows 商店占位程序，或系统未安装 Python 3。" -ForegroundColor Yellow
Write-Host "将自动使用 PowerShell 内置静态服务器来维持服务（推荐）。" -ForegroundColor Yellow

Start-PowerShellStaticServer -Port $port -Root $PSScriptRoot -DefaultPage $page



