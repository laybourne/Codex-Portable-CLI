[CmdletBinding()]
param(
    [switch]$Force,
    [ValidateSet('All', 'Codex', 'Terminal')]
    [string]$Target = 'All'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$Host.UI.RawUI.WindowTitle = '一键事务性更新 (Codex & Windows Terminal)'

$projectRoot = Split-Path $PSScriptRoot -Parent
$appDir = Join-Path $projectRoot 'App'
$terminalDir = Join-Path $projectRoot 'WindowsTerminal'
$backupRoot = Join-Path $projectRoot '.update-backup'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$results = [System.Collections.Generic.List[string]]::new()

function Remove-TempFolderSafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    for ($i = 0; $i -lt 3; $i++) {
        try {
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            Start-Sleep -Milliseconds 300
        }
    }
}

# 启动前清理历史可能遗留的临时目录
Get-ChildItem -Path $projectRoot -Filter '.update-temp-*' -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-TempFolderSafe -Path $_.FullName
}

Write-Host '[网络] 升级器使用直连模式访问 GitHub（忽略系统代理环境变量）。' -ForegroundColor DarkCyan

function Invoke-DownloadFile {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$true)][string]$OutFile
    )
    $baseArgs = @(
        '--fail', '--location', '--silent', '--show-error',
        '--connect-timeout', '20', '--retry', '3', '--retry-delay', '1',
        '--retry-all-errors', '--user-agent', 'codex-updater'
    )
    # --noproxy '*' 可确保请求不继承 HTTP_PROXY、HTTPS_PROXY 或 ALL_PROXY。
    $pDirect = Start-Process -FilePath 'curl.exe' -ArgumentList ($baseArgs + @('--noproxy', '*', '-o', $OutFile, $Uri)) -NoNewWindow -PassThru -Wait
    if ($pDirect.ExitCode -ne 0) {
        throw "下载失败，curl 退出代码: $($pDirect.ExitCode)。URL: $Uri"
    }
    if (!(Test-Path -LiteralPath $OutFile) -or (Get-Item -LiteralPath $OutFile).Length -lt 1024) {
        throw "下载文件损坏或为空: $OutFile"
    }
}

function Get-LatestReleaseTag {
    param(
        [Parameter(Mandatory=$true)][string]$Repository
    )
    $latestUri = "https://github.com/$Repository/releases/latest"
    $curlArgs = @(
        '--fail', '--silent', '--show-error', '--location', '--output', 'NUL',
        '--write-out', '%{url_effective}',
        '--connect-timeout', '15', '--max-time', '30',
        '--retry', '2', '--retry-delay', '1', '--retry-all-errors',
        '--user-agent', 'codex-updater'
    )
    $effectiveUri = (& curl.exe @($curlArgs + @('--noproxy', '*', $latestUri)) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or !$effectiveUri) {
        throw "未能查询 GitHub 最新版本，请检查直连网络。URL: $latestUri"
    }

    $escapedRepository = [Regex]::Escape($Repository)
    if ($effectiveUri -notmatch "^https://github\.com/$escapedRepository/releases/tag/([^/?#]+)") {
        throw "GitHub 最新版本地址格式异常: $effectiveUri"
    }
    return [Uri]::UnescapeDataString($Matches[1])
}

function Update-Codex {
    Write-Host "`n==> [1/2] 检查 OpenAI Codex CLI 更新..." -ForegroundColor Cyan

    # 1. 进程安全检查
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -in @('codex', 'codex-code-mode-host', 'codex-command-runner') -and
        ($_.Path -like "$projectRoot*")
    })
    if ($running.Count -gt 0) {
        throw "检测到 Codex 正在运行中，请先退出 Codex 再执行更新！"
    }

    # 2. 读取当前版本
    $pkgJsonPath = Join-Path $appDir 'codex-package.json'
    $currentVersion = 'unknown'
    if (Test-Path -LiteralPath $pkgJsonPath) {
        try {
            $pkg = Get-Content -LiteralPath $pkgJsonPath -Raw | ConvertFrom-Json
            $currentVersion = $pkg.version
        } catch {}
    }
    Write-Host "    当前本地版本: $currentVersion"

    # 3. releases/latest 由 GitHub 保证指向最新非预发布版本，避免体积较大的 API 列表请求超时。
    $targetTag = Get-LatestReleaseTag -Repository 'openai/codex'
    $targetVersion = $targetTag -replace '^rust-v', ''
    Write-Host "    远程最新稳定版: $targetVersion ($targetTag)"

    $asset = [pscustomobject]@{
        name = 'codex-package-x86_64-pc-windows-msvc.tar.gz'
        browser_download_url = "https://github.com/openai/codex/releases/download/$targetTag/codex-package-x86_64-pc-windows-msvc.tar.gz"
    }

    if (-not $Force -and ($currentVersion -eq $targetVersion)) {
        Write-Host "    [跳过] 本地已是最新稳定版本 ($currentVersion)，无需更新。" -ForegroundColor Green
        $results.Add("OpenAI Codex: 已是最新稳定版 ($currentVersion)")
        return
    }

    # 4. 事务隔离准备与下载
    $tempDir = Join-Path $projectRoot (".update-temp-codex-" + [guid]::NewGuid().ToString('N'))
    $archiveFile = Join-Path $tempDir $asset.name
    $extractDir = Join-Path $tempDir 'extracted'
    $backupDir = Join-Path $backupRoot "App-$timestamp"
    $replaced = $false

    try {
        New-Item -ItemType Directory -Path $tempDir, $extractDir, $backupRoot -Force | Out-Null
        Write-Host "    正在下载: $($asset.name)..." -ForegroundColor Yellow
        Invoke-DownloadFile -Uri $asset.browser_download_url -OutFile $archiveFile

        Write-Host "    正在解压并验证包完整性..." -ForegroundColor Yellow
        & tar.exe -xzf $archiveFile -C $extractDir
        if ($LASTEXITCODE -ne 0) {
            throw "解压 tar.gz 失败，退出代码: $LASTEXITCODE"
        }

        # 检查提取产物
        $validRoot = $extractDir
        if (!(Test-Path -LiteralPath (Join-Path $validRoot 'bin/codex.exe'))) {
            $foundExe = Get-ChildItem -Path $extractDir -Recurse -Filter 'codex.exe' | Select-Object -First 1
            if ($foundExe) {
                $validRoot = Split-Path (Split-Path $foundExe.FullName -Parent) -Parent
            } else {
                throw "解压文件中缺失 bin/codex.exe，安装包不完整！"
            }
        }

        # 事务性原子替换：
        # 保护已存在的脚本（包括 codex_proxy.ps1, update.ps1, stop_all_proxies.ps1 等所有 .ps1 定制脚本）
        $customScripts = @{}
        Get-ChildItem -Path $appDir -Filter '*.ps1' -File | ForEach-Object {
            $customScripts[$_.Name] = Get-Content -LiteralPath $_.FullName -Raw
        }

        # 创建备份
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Get-ChildItem -Path $appDir -Force | Where-Object { $_.Extension -ne '.ps1' } | ForEach-Object {
            Move-Item -LiteralPath $_.FullName -Destination $backupDir -Force
        }
        $replaced = $true

        # 部署新文件
        Get-ChildItem -Path $validRoot -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $appDir -Recurse -Force
        }

        # 还原保护脚本
        foreach ($sName in $customScripts.Keys) {
            $dest = Join-Path $appDir $sName
            Set-Content -LiteralPath $dest -Value $customScripts[$sName] -Encoding UTF8
        }

        # 验收验证
        $deployedCodex = Join-Path $appDir 'bin/codex.exe'
        if (!(Test-Path -LiteralPath $deployedCodex)) {
            throw "部署后未检测到 bin/codex.exe，触发自动回滚！"
        }

        Write-Host "    [成功] OpenAI Codex 已成功更新至 $targetVersion！" -ForegroundColor Green
        $results.Add("OpenAI Codex: $currentVersion -> $targetVersion")
    } catch {
        Write-Host "    [错误] 更新过程发生异常: $($_.Exception.Message)" -ForegroundColor Red
        if ($replaced -and (Test-Path -LiteralPath $backupDir)) {
            Write-Host "    [回滚] 正在从备份还原旧版本 Codex..." -ForegroundColor Yellow
            try {
                Get-ChildItem -Path $appDir -Force | Where-Object { $_.Extension -ne '.ps1' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                Get-ChildItem -Path $backupDir -Force | ForEach-Object {
                    Copy-Item -LiteralPath $_.FullName -Destination $appDir -Recurse -Force
                }
                Write-Host "    [回滚] 已成功恢复原有版本，数据未受损坏。" -ForegroundColor Green
            } catch {
                Write-Host "    [严重] 回滚异常: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        throw
    } finally {
        Remove-TempFolderSafe -Path $tempDir
    }
}

function Update-WindowsTerminal {
    Write-Host "`n==> [2/2] 检查 Windows Terminal 更新..." -ForegroundColor Cyan

    $terminalExe = Join-Path $terminalDir 'WindowsTerminal.exe'
    $markerFile = Join-Path $terminalDir '.release-tag'

    # 1. 进程安全检查
    $running = @(Get-Process -Name 'WindowsTerminal' -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -like "$projectRoot*" } catch { $false }
    })
    if ($running.Count -gt 0) {
        throw "检测到 Windows Terminal 正在运行中，请先关闭终端窗口再执行更新！"
    }

    # 2. 读取当前版本
    $currentTag = if (Test-Path -LiteralPath $markerFile) { (Get-Content -LiteralPath $markerFile -Raw).Trim() } else { '' }
    $currentProductVersion = if (Test-Path -LiteralPath $terminalExe) { (Get-Item -LiteralPath $terminalExe).VersionInfo.ProductVersion } else { 'unknown' }
    Write-Host "    当前本地版本: $currentProductVersion $(if($currentTag){"($currentTag)"})"

    # 3. releases/latest 只指向稳定版，不会选中 Preview。
    $targetTag = Get-LatestReleaseTag -Repository 'microsoft/terminal'
    Write-Host "    远程最新稳定版: $targetTag"

    $terminalVersion = $targetTag -replace '^v', ''
    if ($terminalVersion -notmatch '^\d+(?:\.\d+)+$') {
        throw "Windows Terminal Release 标签格式异常: $targetTag"
    }
    $assetName = "Microsoft.WindowsTerminal_${terminalVersion}_x64.zip"
    $asset = [pscustomobject]@{
        name = $assetName
        browser_download_url = "https://github.com/microsoft/terminal/releases/download/$targetTag/$assetName"
    }

    if (-not $Force -and ($currentTag -eq $targetTag)) {
        Write-Host "    [跳过] 本地已是最新稳定版本 ($targetTag)，无需更新。" -ForegroundColor Green
        $results.Add("Windows Terminal: 已是最新稳定版 ($targetTag)")
        return
    }

    # 4. 事务隔离准备与下载
    $tempDir = Join-Path $projectRoot (".update-temp-wt-" + [guid]::NewGuid().ToString('N'))
    $zipFile = Join-Path $tempDir $asset.name
    $extractDir = Join-Path $tempDir 'extracted'
    $backupDir = Join-Path $backupRoot "WindowsTerminal-$timestamp"
    $movedOld = $false

    try {
        New-Item -ItemType Directory -Path $tempDir, $extractDir, $backupRoot -Force | Out-Null
        Write-Host "    正在下载: $($asset.name)..." -ForegroundColor Yellow
        Invoke-DownloadFile -Uri $asset.browser_download_url -OutFile $zipFile

        Write-Host "    正在解压并验证包完整性..." -ForegroundColor Yellow
        Expand-Archive -LiteralPath $zipFile -DestinationPath $extractDir -Force

        $downloadedExe = Get-ChildItem -LiteralPath $extractDir -Recurse -File -Filter 'WindowsTerminal.exe' | Select-Object -First 1
        if (!$downloadedExe) {
            throw "解压包中未找到 WindowsTerminal.exe！"
        }
        $payloadDir = $downloadedExe.Directory.FullName

        # 事务性原子替换
        if (Test-Path -LiteralPath $terminalDir) {
            Move-Item -LiteralPath $terminalDir -Destination $backupDir -Force
            $movedOld = $true
        }

        Move-Item -LiteralPath $payloadDir -Destination $terminalDir -Force

        # 确保便携标记 .portable 保持存在
        $portableMarker = Join-Path $terminalDir '.portable'
        if (!(Test-Path -LiteralPath $portableMarker)) {
            New-Item -ItemType File -Path $portableMarker -Force | Out-Null
        }
        Set-Content -LiteralPath (Join-Path $terminalDir '.release-tag') -Value $targetTag -Encoding ASCII

        # 验收验证
        $newTerminalExe = Join-Path $terminalDir 'WindowsTerminal.exe'
        if (!(Test-Path -LiteralPath $newTerminalExe)) {
            throw "部署后未检测到 WindowsTerminal.exe，触发自动回滚！"
        }

        Write-Host "    [成功] Windows Terminal 已成功更新至 $targetTag！" -ForegroundColor Green
        $results.Add("Windows Terminal: $currentProductVersion -> $targetTag")
    } catch {
        Write-Host "    [错误] 更新过程发生异常: $($_.Exception.Message)" -ForegroundColor Red
        if ($movedOld -and (Test-Path -LiteralPath $backupDir)) {
            Write-Host "    [回滚] 正在从备份还原旧版本 Windows Terminal..." -ForegroundColor Yellow
            try {
                if (Test-Path -LiteralPath $terminalDir) {
                    Remove-Item -LiteralPath $terminalDir -Recurse -Force -ErrorAction SilentlyContinue
                }
                Move-Item -LiteralPath $backupDir -Destination $terminalDir -Force
                Write-Host "    [回滚] 已成功恢复原有版本，数据未受损坏。" -ForegroundColor Green
            } catch {
                Write-Host "    [严重] 回滚异常: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        throw
    } finally {
        Remove-TempFolderSafe -Path $tempDir
    }
}

$anyFailed = $false
try {
    if ($Target -in @('All', 'Codex')) {
        try {
            Update-Codex
        } catch {
            $anyFailed = $true
            Write-Host "    [错误] Codex 更新失败: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    if ($Target -in @('All', 'Terminal')) {
        try {
            Update-WindowsTerminal
        } catch {
            $anyFailed = $true
            Write-Host "    [错误] Windows Terminal 更新失败: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} catch {
    $anyFailed = $true
    Write-Host "    [错误] $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n========================================================" -ForegroundColor Cyan
if ($results.Count -gt 0) {
    $results | ForEach-Object { Write-Host "  * $_" }
}
if (Test-Path -LiteralPath $backupRoot) {
    Write-Host "`n历史备份存放于: $backupRoot" -ForegroundColor DarkGray
}

if ($anyFailed) {
    exit 1
} else {
    exit 0
}
