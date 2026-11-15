param(
    [int]$Timeout = 15,
    [string]$ExeName = "AsurasWrathRecomp.exe",
    [string]$ElfPath = "00_GAME_DUMP\extracted\PS3_GAME\USRDIR\EBOOT.ELF",
    [switch]$DebugGpu = $false
)
. (Join-Path $PSScriptRoot "env_ps3_laptop.ps1")
if (-not $env:PS3_VFS_ROOT) {
    $env:PS3_VFS_ROOT = Join-Path $env:PORT_ROOT "00_GAME_DUMP\extracted"
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $env:RSX_SHADER_CACHE_DIR) | Out-Null

if ($DebugGpu) {
    $env:RT_DISPLAY_BY_SIZE = "1"
    $env:DRAWARGS = "50"
    $env:CELLMARK_DUMP = "5"
    $env:CELLMARK_DUMP_MINDRAWS = "1"
    $env:TEX_SAVE = "1"
    $env:FLOW_FSDBG = "1"
}

$exe = Join-Path $env:PORT_ROOT "04_BUILD\$ExeName"
if (-not (Test-Path $exe)) {
    $exe = Join-Path $env:PORT_ROOT "build\$ExeName"
}
if (-not (Test-Path $exe)) { Write-Host "Exe tidak ada: $exe" -ForegroundColor Red; exit 1 }

$targetElf = Join-Path $env:PORT_ROOT $ElfPath
if (-not (Test-Path $targetElf)) { Write-Host "ELF tidak ada: $targetElf" -ForegroundColor Red; exit 1 }

$logDir = Join-Path $env:PORT_ROOT "05_LOGS"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ("run_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

$timeoutLabel = if ($Timeout -le 0) { "unlimited" } else { "$Timeout s" }
Write-Host "Running $exe on $targetElf (Timeout: $timeoutLabel)..."
Write-Host "VFS_ROOT: $env:PS3_VFS_ROOT"
if ($DebugGpu) {
    Write-Host "Debug GPU enabled (RT_DISPLAY_BY_SIZE=1, DRAWARGS=50, TEX_SAVE=1)"
}

$p = Start-Process -FilePath $exe -ArgumentList "`"$targetElf`"" -WorkingDirectory $env:PORT_ROOT -PassThru `
     -RedirectStandardOutput $log -RedirectStandardError "$log.err"
if ($Timeout -le 0) {
    $p | Wait-Process
} else {
    $p | Wait-Process -Timeout $Timeout -ErrorAction SilentlyContinue
}
$exitCode = 0
if (-not $p.HasExited) {
    Write-Host "Process running, terminating after timeout..."
    $p | Stop-Process -Force
    $exitCode = 124
} else {
    $exitCode = $p.ExitCode
    Write-Host "Process exited with code: $exitCode"
}

Write-Host "=== Log output (last 50 lines) ==="
if (Test-Path $log) { Get-Content $log -Tail 50 }
if (Test-Path "$log.err") {
    $errContent = Get-Content "$log.err" -Tail 50
    if ($errContent) {
        Write-Host "=== Stderr ===" -ForegroundColor Yellow
        $errContent
    }
}
exit $exitCode
