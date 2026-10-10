$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    try {
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
        exit $process.ExitCode
    } catch {
        Write-Host '[ERROR] Administrator permission is required to stop elevated proxy processes.' -ForegroundColor Red
        exit 1
    }
}

$knownNames = @(
    'clash.meta-windows-386', 'xray', 'hysteria-tun-windows-6.0-386',
    'sing-box', 'naive', 'hysteria2', 'juicity-client', 'mieru', 'shadowquic', 'quick'
)
$rootPrefix = $root.TrimEnd('\', '/') + '\'
$stopped = [System.Collections.Generic.List[string]]::new()

$mieruExe = Join-Path $root 'mieru\mieru.exe'
if (Test-Path -LiteralPath $mieruExe) {
    try { & $mieruExe stop 2>$null | Out-Null } catch {}
}

Get-Process -ErrorAction SilentlyContinue | Where-Object {
    if ($knownNames -notcontains $_.ProcessName) { return $false }
    try {
        return $_.MainModule.FileName.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
} | ForEach-Object {
    $description = "$($_.ProcessName) (PID: $($_.Id))"
    Stop-Process -Id $_.Id -Force -ErrorAction Stop
    $stopped.Add($description)
}

if ($stopped.Count -eq 0) {
    Write-Host '[OK] No running proxy process was found for this package.' -ForegroundColor Green
} else {
    $stopped | ForEach-Object { Write-Host "[STOPPED] $_" -ForegroundColor Green }
}
