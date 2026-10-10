param(
    [ValidateRange(1,10)][int]$Core = 1,
    [switch]$InConsole
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$codex = Join-Path $root 'App/bin/codex.exe'
$terminal = Join-Path $root 'WindowsTerminal/WindowsTerminal.exe'

$coreConfigs = @{
    1 = @{
        Name        = 'Clash.Meta'
        Folder      = 'clash.meta'
        Exe         = (Join-Path $root 'clash.meta\clash.meta-windows-386.exe')
        Args        = @('-d', (Join-Path $root 'clash.meta'))
        Port        = 7890
        NeedsBridge = $false
        ProcessName = 'clash.meta-windows-386'
    }
    2 = @{
        Name        = 'Xray'
        Folder      = 'Xray'
        Exe         = (Join-Path $root 'Xray\xray.exe')
        Args        = @('-c', (Join-Path $root 'Xray\config.json'))
        Port        = 1081
        NeedsBridge = $false
        ProcessName = 'xray'
    }
    3 = @{
        Name        = 'Hysteria'
        Folder      = 'hysteria'
        Exe         = (Join-Path $root 'hysteria\hysteria-tun-windows-6.0-386.exe')
        Args        = @('-c', (Join-Path $root 'hysteria\config.json'))
        Port        = 1080
        NeedsBridge = $true
        ProcessName = 'hysteria-tun-windows-6.0-386'
    }
    4 = @{
        Name        = 'sing-box'
        Folder      = 'singbox'
        Exe         = (Join-Path $root 'singbox\sing-box.exe')
        Args        = @('run', '-c', (Join-Path $root 'singbox\config.json'))
        Port        = 1080
        NeedsBridge = $false
        ProcessName = 'sing-box'
    }
    5 = @{
        Name        = 'NaiveProxy'
        Folder      = 'naiveproxy'
        Exe         = (Join-Path $root 'naiveproxy\naive.exe')
        Args        = @((Join-Path $root 'naiveproxy\config.json'))
        Port        = 1080
        NeedsBridge = $true
        ProcessName = 'naive'
    }
    6 = @{
        Name        = 'Hysteria2'
        Folder      = 'hysteria2'
        Exe         = (Join-Path $root 'hysteria2\hysteria2.exe')
        Args        = @('-c', (Join-Path $root 'hysteria2\config.json'))
        Port        = 1080
        NeedsBridge = $true
        ProcessName = 'hysteria2'
    }
    7 = @{
        Name        = 'Juicity'
        Folder      = 'juicity'
        Exe         = (Join-Path $root 'juicity\juicity-client.exe')
        Args        = @('run', '-c', (Join-Path $root 'juicity\config.json'))
        Port        = 1080
        NeedsBridge = $true
        ProcessName = 'juicity-client'
    }
    8 = @{
        Name        = 'Mieru'
        Folder      = 'mieru'
        Exe         = (Join-Path $root 'mieru\mieru.exe')
        Args        = @('start')
        Port        = 3080
        NeedsBridge = $true
        ProcessName = 'mieru'
        IsMieru     = $true
    }
    9 = @{
        Name        = 'ShadowQUIC'
        Folder      = 'shadowquic'
        Exe         = (Join-Path $root 'shadowquic\shadowquic.exe')
        Args        = @('-c', (Join-Path $root 'shadowquic\client.yaml'))
        Port        = 4080
        NeedsBridge = $true
        ProcessName = 'shadowquic'
    }
    10 = @{
        Name        = 'Quick'
        Folder      = 'Quick'
        Exe         = (Join-Path $root 'Quick\quick.exe')
        Args        = @('-d', (Join-Path $root 'Quick'))
        Port        = 7890
        NeedsBridge = $false
        ProcessName = 'quick'
    }
}

function Stop-PackageProxies {
    param([int]$ExceptProcessId = 0)
    $knownNames = @(
        'clash.meta-windows-386', 'xray', 'hysteria-tun-windows-6.0-386',
        'sing-box', 'naive', 'hysteria2', 'juicity-client', 'mieru', 'shadowquic', 'quick'
    )
    $rootNorm = $root.TrimEnd('\', '/')
    $mieruExe = Join-Path $root 'mieru\mieru.exe'
    if (Test-Path -LiteralPath $mieruExe) {
        try { & $mieruExe stop 2>$null | Out-Null } catch {}
    }

    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $p = $_
        if ($ExceptProcessId -and $p.Id -eq $ExceptProcessId) { return $false }
        if ($knownNames -contains $p.ProcessName) {
            try {
                $path = $p.MainModule.FileName
                if ($path -and $path.StartsWith($rootNorm, [StringComparison]::OrdinalIgnoreCase)) {
                    return $true
                }
            } catch {}
        }
        return $false
    } | ForEach-Object {
        try {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

function Wait-Port {
    param(
        [Parameter(Mandatory=$true)][int]$Number,
        [System.Diagnostics.Process]$ProcessToCheck = $null,
        [int]$TimeoutSeconds = 15,
        [string]$Description = "Proxy Port"
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if ($ProcessToCheck) {
            $ProcessToCheck.Refresh()
            if ($ProcessToCheck.HasExited) {
                throw "$Description 关联进程已意外退出 (代码: $($ProcessToCheck.ExitCode))，端口 $Number 启动失败！"
            }
        }
        $client = New-Object Net.Sockets.TcpClient
        try {
            $pending = $client.BeginConnect('127.0.0.1', $Number, $null, $null)
            if ($pending.AsyncWaitHandle.WaitOne(200)) {
                $client.EndConnect($pending)
                return
            }
        } catch {} finally {
            $client.Dispose()
        }
        Start-Sleep -Milliseconds 150
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "$Description $Number 在 $TimeoutSeconds 秒内未就绪，请检查配置或节点连通性。"
}

function Test-ProxyTls {
    param(
        [Parameter(Mandatory=$true)][int]$ProxyPort,
        [string]$TargetHost = 'api.openai.com',
        [int]$TimeoutSeconds = 10
    )

    $client = $null
    $stream = $null
    $tls = $null
    try {
        $client = New-Object Net.Sockets.TcpClient
        $pending = $client.BeginConnect('127.0.0.1', $ProxyPort, $null, $null)
        if (!$pending.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
            throw "连接本地代理超时"
        }
        $client.EndConnect($pending)
        $client.ReceiveTimeout = $TimeoutSeconds * 1000
        $client.SendTimeout = $TimeoutSeconds * 1000
        $stream = $client.GetStream()

        # 先确认本地 HTTP 代理可以为 OpenAI 建立 CONNECT 隧道。
        $request = "CONNECT ${TargetHost}:443 HTTP/1.1`r`nHost: ${TargetHost}:443`r`nProxy-Connection: close`r`n`r`n"
        $requestBytes = [Text.Encoding]::ASCII.GetBytes($request)
        $stream.Write($requestBytes, 0, $requestBytes.Length)
        $stream.Flush()

        $responseBytes = New-Object System.Collections.Generic.List[byte]
        $buffer = New-Object byte[] 1
        while ($responseBytes.Count -lt 16384) {
            $read = $stream.Read($buffer, 0, 1)
            if ($read -le 0) { throw '代理在 CONNECT 响应完成前关闭了连接' }
            $responseBytes.Add($buffer[0])
            $count = $responseBytes.Count
            if ($count -ge 4 -and
                $responseBytes[$count-4] -eq 13 -and $responseBytes[$count-3] -eq 10 -and
                $responseBytes[$count-2] -eq 13 -and $responseBytes[$count-1] -eq 10) {
                break
            }
        }

        $response = [Text.Encoding]::ASCII.GetString($responseBytes.ToArray())
        $statusLine = ($response -split "`r`n", 2)[0]
        if ($statusLine -notmatch '^HTTP/\d(?:\.\d)? 200(?:\s|$)') {
            throw "代理拒绝 CONNECT 隧道: $statusLine"
        }

        # 完成与 OpenAI 的真实 TLS 握手；这正是 tls handshake eof 的故障点。
        $tls = New-Object Net.Security.SslStream($stream, $false)
        $tls.ReadTimeout = $TimeoutSeconds * 1000
        $tls.WriteTimeout = $TimeoutSeconds * 1000
        $tlsPending = $tls.BeginAuthenticateAsClient($TargetHost, $null, $null)
        if (!$tlsPending.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
            throw "与 $TargetHost 的 TLS 握手超时"
        }
        $tls.EndAuthenticateAsClient($tlsPending)
        if (!$tls.IsAuthenticated -or !$tls.IsEncrypted) {
            throw 'TLS 通道未通过认证或未加密'
        }
        return $true
    } catch {
        throw "OpenAI TLS 检查失败: $($_.Exception.Message)"
    } finally {
        if ($tls) { try { $tls.Dispose() } catch {} }
        elseif ($stream) { try { $stream.Dispose() } catch {} }
        if ($client) { try { $client.Dispose() } catch {} }
    }
}

function Wait-ProxyTls {
    param(
        [Parameter(Mandatory=$true)][int]$ProxyPort,
        [string]$ProxyName,
        [int]$Attempts = 3
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $null = Test-ProxyTls -ProxyPort $ProxyPort
            Write-Host '[网络] OpenAI HTTPS/TLS 连接正常。' -ForegroundColor Green
            return
        } catch {
            $lastError = $_.Exception.Message
            if ($attempt -lt $Attempts) { Start-Sleep -Seconds 2 }
        }
    }

    throw @"
$ProxyName 的本地端口已经启动，但无法通过该节点完成 OpenAI TLS 握手。
原因: $lastError

请先运行该核心目录下的 ip_Update 更新节点，或关闭窗口后改用另一个启动入口。
为避免再次出现 “Falling back from WebSockets ... tls handshake eof”，本次不会启动 Codex。
"@
}

if (!$InConsole -and (Test-Path -LiteralPath $terminal)) {
    $entry = $PSCommandPath.Replace("'", "''")
    $command = "& '$entry' -Core $Core -InConsole"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $terminalStartDirectory = if ($env:USERPROFILE) { $env:USERPROFILE } else { $root }
    Start-Process -FilePath $terminal -ArgumentList "-w new new-tab powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -WorkingDirectory $terminalStartDirectory
    exit 0
}

$cfg = $coreConfigs[$Core]
if (!$cfg) { throw "未知的核心编号: $Core" }

$proxyProcess = $null
$bridge = $null
$temporary = $null
$bridgeLog = $null

try {
    [AppDomain]::CurrentDomain.add_ProcessExit({
        try { Stop-PackageProxies } catch {}
    })
} catch {}

try {
    if (!(Test-Path -LiteralPath $codex)) { throw '未找到 App/bin/codex.exe，请确认文件完整。' }
    if (!(Test-Path -LiteralPath $cfg.Exe)) { throw "未找到代理核心程序: $($cfg.Exe)" }

    Stop-PackageProxies

    $staleTmp = Join-Path $root 'Data/codex/.tmp'
    if (Test-Path -LiteralPath $staleTmp) {
        try { Remove-Item -LiteralPath "$staleTmp\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }

    # 启动前检查端口是否被外部第三方程序占用
    $portsToCheck = @($cfg.Port)
    if ($cfg.Name -eq 'Xray') { $portsToCheck += 1080 }

    foreach ($chkPort in $portsToCheck) {
        $occupied = Get-NetTCPConnection -LocalPort $chkPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($occupied) {
            $holder = Get-Process -Id $occupied.OwningProcess -ErrorAction SilentlyContinue
            $holderInfo = if ($holder) { "$($holder.ProcessName) (PID: $($holder.Id), 路径: $($holder.Path))" } else { "PID: $($occupied.OwningProcess)" }
            throw "端口 $chkPort 已被外部程序占用: $holderInfo`n请先关闭冲突程序再启动 $($cfg.Name)！"
        }
    }

    $workDir = Join-Path $root $cfg.Folder
    if ($cfg.IsMieru) {
        & $cfg.Exe start
    } else {
        $argString = ($cfg.Args | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $cfg.Exe
        $psi.WorkingDirectory = $workDir
        $psi.Arguments = $argString
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        $proxyProcess = [System.Diagnostics.Process]::Start($psi)
    }

    Wait-Port -Number $cfg.Port -ProcessToCheck $proxyProcess -TimeoutSeconds 15 -Description "$($cfg.Name) 代理端口"

    $port = $cfg.Port
    if ($cfg.NeedsBridge) {
        $singboxExe = Join-Path $root 'singbox/sing-box.exe'
        if (!(Test-Path -LiteralPath $singboxExe)) {
            throw "未找到 singbox/sing-box.exe，无法为 $($cfg.Name) 提供 HTTP 协议桥接！"
        }

        $bridgeStarted = $false
        $lastBridgeError = $null

        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $reservation = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
                $reservation.Start()
                $httpPort = $reservation.LocalEndpoint.Port
                $reservation.Stop()

                $temporary = Join-Path ([IO.Path]::GetTempPath()) ('codex-bridge-' + [guid]::NewGuid().ToString('N') + '.json')
                $bridgeLog = Join-Path ([IO.Path]::GetTempPath()) ('codex-bridge-' + [guid]::NewGuid().ToString('N') + '.log')

                $bridgeConfig = @{
                    log = @{
                        level = 'warn'
                        output = $bridgeLog
                    }
                    inbounds = @(
                        @{
                            type = 'http'
                            listen = '127.0.0.1'
                            listen_port = $httpPort
                            set_system_proxy = $false
                        }
                    )
                    outbounds = @(
                        @{
                            type = 'socks'
                            server = '127.0.0.1'
                            server_port = $port
                            version = '5'
                        }
                    )
                }
                $bridgeConfig | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporary -Encoding ASCII

                $saved = @{}
                foreach ($key in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')) {
                    $saved[$key] = [Environment]::GetEnvironmentVariable($key)
                    [Environment]::SetEnvironmentVariable($key, $null)
                }

                try {
                    $psiBridge = New-Object System.Diagnostics.ProcessStartInfo
                    $psiBridge.FileName = $singboxExe
                    $psiBridge.Arguments = "run -c `"$temporary`""
                    $psiBridge.WorkingDirectory = (Join-Path $root 'singbox')
                    $psiBridge.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                    $psiBridge.CreateNoWindow = $true
                    $psiBridge.UseShellExecute = $false
                    $bridge = [System.Diagnostics.Process]::Start($psiBridge)
                } finally {
                    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key]) }
                }

                Wait-Port -Number $httpPort -ProcessToCheck $bridge -TimeoutSeconds 5 -Description "本地 HTTP 桥接端口"
                $bridge.Refresh()
                if ($bridge.HasExited) {
                    throw "本地 HTTP 代理桥退出 (代码: $($bridge.ExitCode))"
                }

                $port = $httpPort
                $bridgeStarted = $true
                break
            } catch {
                $lastBridgeError = $_.Exception.Message
                if ($bridge) {
                    try { if (!$bridge.HasExited) { $bridge.Kill(); $bridge.WaitForExit(1000) }; $bridge.Dispose() } catch {}
                    $bridge = $null
                }
                if ($temporary -and (Test-Path -LiteralPath $temporary)) {
                    try { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } catch {}
                }
                Start-Sleep -Milliseconds 200
            }
        }

        if (!$bridgeStarted) {
            $errLog = if ($bridgeLog -and (Test-Path -LiteralPath $bridgeLog)) {
                (Get-Content -LiteralPath $bridgeLog -Tail 10 -ErrorAction SilentlyContinue) -join "`n"
            } else { "" }
            throw "本地 HTTP 代理桥启动失败 (尝试 3 次)。错误: $lastBridgeError $(if($errLog){"`n日志详情: $errLog"})"
        }
    }

    $env:HTTP_PROXY = "http://127.0.0.1:$port"
    $env:HTTPS_PROXY = $env:HTTP_PROXY
    $env:ALL_PROXY = $env:HTTP_PROXY
    $env:NO_PROXY = 'localhost,127.0.0.1,::1'
    $env:CODEX_HOME = Join-Path $root 'Data/codex'
    $null = New-Item -ItemType Directory -Path $env:CODEX_HOME -Force
    $env:PATH = (Join-Path $root 'App/bin')+';'+(Join-Path $root 'App/codex-path')+';'+$env:PATH
    Set-Location -LiteralPath $root

    Wait-ProxyTls -ProxyPort $port -ProxyName $cfg.Name -Attempts 3

    & $codex
    if ($LASTEXITCODE) { throw "Codex 退出，代码: $LASTEXITCODE." }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    $null = Read-Host '按回车键关闭窗口'
    exit 1
} finally {
    if ($bridge) {
        try {
            $bridge.Refresh()
            if (!$bridge.HasExited) { $bridge.Kill(); $bridge.WaitForExit(2000) }
            $bridge.Dispose()
        } catch {}
    }
    if ($proxyProcess) {
        try {
            $proxyProcess.Refresh()
            if (!$proxyProcess.HasExited) { $proxyProcess.Kill(); $proxyProcess.WaitForExit(2000) }
            $proxyProcess.Dispose()
        } catch {}
    }
    if ($cfg.IsMieru) {
        try { & $cfg.Exe stop 2>$null | Out-Null } catch {}
    }
    Stop-PackageProxies
    if ($temporary -and (Test-Path -LiteralPath $temporary)) {
        try { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } catch {}
    }
    if ($bridgeLog -and (Test-Path -LiteralPath $bridgeLog)) {
        try { Remove-Item -LiteralPath $bridgeLog -Force -ErrorAction SilentlyContinue } catch {}
    }
}
