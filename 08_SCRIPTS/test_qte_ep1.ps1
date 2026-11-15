param(
    [ValidateSet("inject", "manual")]
    [string]$Mode = "inject",
    [string]$PadStick = "128,255,128,255,190,260",
    [ValidateSet("sec", "flips")]
    [string]$PadClock = "sec",
    [switch]$PadAlwaysChange = $false,
    [switch]$SkipAutoMenus = $false,
    [string]$PadDiag = "1",
    [int]$Ep1Sec = 0,
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "env_ps3_laptop.ps1")

if (-not $env:PS3_VFS_ROOT) {
    $env:PS3_VFS_ROOT = Join-Path $env:PORT_ROOT "00_GAME_DUMP\extracted"
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $env:RSX_SHADER_CACHE_DIR) | Out-Null

# Explicit environment setup per mode (T4)
$env:SPU_MISS_FATAL = "1"
$env:PAD_DIAG = $PadDiag

# Clear all stale PAD overrides first
foreach ($v in @("PAD_STICK", "PAD_SWEEP", "PAD_SCRIPT", "PAD_AUTOPRESS", "PAD_ALWAYS_CHANGE", "PAD_CLOCK", "PAD_FILE", "PAD_NO_KEYBOARD", "SPU_MISS_DUMP_DIR")) {
    Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}

if ($Ep1Sec -le 0) {
    $Ep1Sec = if ($Mode -eq "manual") { 240 } else { 130 }
}

if (-not $OutDir) {
    $OutDir = Join-Path $env:PORT_ROOT ("05_LOGS\qte_ep1_{0}_{1}" -f $Mode, (Get-Date -Format "yyyyMMdd_HHmmss"))
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$missDir  = Join-Path $OutDir "miss_dumps"
New-Item -ItemType Directory -Force -Path $missDir | Out-Null
$env:SPU_MISS_DUMP_DIR = $missDir

$outLog   = Join-Path $OutDir "stdout.log"
$errLog   = Join-Path $OutDir "stderr.log"
$stageLog = Join-Path $OutDir "stages.log"
$auditTxt = Join-Path $OutDir "audit_summary.txt"
$padFile  = Join-Path $OutDir "pad.txt"

if ($Mode -eq "inject") {
    $env:PAD_STICK = $PadStick
    if ($PadClock -eq "flips") { $env:PAD_CLOCK = "flips" }
    if ($PadAlwaysChange) { $env:PAD_ALWAYS_CHANGE = "1" }
}

if (($Mode -eq "inject") -or (-not $SkipAutoMenus)) {
    [System.IO.File]::WriteAllText($padFile, "", [System.Text.Encoding]::ASCII)
    $env:PAD_FILE = $padFile
}

$exe = Join-Path $env:PORT_ROOT "04_BUILD\AsurasWrathRecomp.exe"
$elf = Join-Path $env:PORT_ROOT "00_GAME_DUMP\extracted\PS3_GAME\USRDIR\EBOOT.ELF"
if (-not (Test-Path $exe)) { throw "Missing exe: $exe" }
if (-not (Test-Path $elf)) { throw "Missing ELF: $elf" }

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class QteWinCap {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public const uint WM_CLOSE = 0x0010;
}
"@

function Write-Stage([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss.ff"), $msg
    Write-Host $line
    Add-Content -Path $stageLog -Value $line -Encoding UTF8
}

function Read-LogText([string]$path) {
    if (-not (Test-Path $path)) { return "" }
    $fs = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8, $true)
        return $sr.ReadToEnd()
    } finally {
        $fs.Dispose()
    }
}

function Count-Matches([string]$text, [string]$pattern) {
    if (-not $text) { return 0 }
    return ([regex]::Matches($text, $pattern)).Count
}

function Capture-Png([string]$destPath) {
    $hWnd = [QteWinCap]::FindWindow("ps3recomp_d3d12", [NullString]::Value)
    if ($hWnd -eq [IntPtr]::Zero) { return $false }
    $rc = New-Object QteWinCap+RECT
    if (-not [QteWinCap]::GetClientRect($hWnd, [ref]$rc)) { return $false }
    $w = $rc.Right - $rc.Left
    $h = $rc.Bottom - $rc.Top
    if ($w -le 0 -or $h -le 0) { return $false }
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = [IntPtr]::Zero
    try {
        $hdc = $gfx.GetHdc()
        $ok = [QteWinCap]::PrintWindow($hWnd, $hdc, 3)
        $gfx.ReleaseHdc($hdc)
        $hdc = [IntPtr]::Zero
        if (-not $ok) { return $false }
        $bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Stage ("Screenshot saved: {0} ({1} bytes)" -f (Split-Path -Leaf $destPath), (Get-Item $destPath).Length)
        return $true
    } finally {
        if ($hdc -ne [IntPtr]::Zero) { $gfx.ReleaseHdc($hdc) }
        $gfx.Dispose()
        $bmp.Dispose()
    }
}

function Send-PadButton([string]$mask, [System.Diagnostics.Process]$proc) {
    [System.IO.File]::WriteAllText($padFile, "$mask`n", [System.Text.Encoding]::ASCII)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 10 -and -not $proc.HasExited) {
        Start-Sleep -Milliseconds 50
        try {
            $cur = [System.IO.File]::ReadAllText($padFile).Trim()
            if (-not $cur) {
                Write-Stage ("PAD_FILE consumed: {0} in {1} ms" -f $mask, [int]$sw.ElapsedMilliseconds)
                return $true
            }
        } catch {}
    }
    Write-Stage ("WARNING: PAD_FILE {0} not consumed within 10s" -f $mask)
    return $false
}

function Wait-ForPattern([string]$stageName, [string]$pattern, [int]$minCount, [int]$timeoutSec, [System.Diagnostics.Process]$proc) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        if ($proc.HasExited) { throw "$stageName failed: process exited early (code=$($proc.ExitCode))" }
        $txt = Read-LogText $outLog
        $err = Read-LogText $errLog
        if ($err -match "SPU_MISS_FATAL|ERROR: dispatch of an SPU program") {
            throw "$stageName aborted: SPU dispatch MISS detected!"
        }
        $cnt = Count-Matches ($txt + "`n" + $err) $pattern
        if ($cnt -ge $minCount) {
            Write-Stage ("[{0}] Matched '{1}' ({2} >= {3}) in {4:F1}s" -f $stageName, $pattern, $cnt, $minCount, $sw.Elapsed.TotalSeconds)
            return $true
        }
        Start-Sleep -Milliseconds 300
    }
    throw "$stageName timed out after ${timeoutSec}s waiting for pattern: $pattern"
}

Write-Stage ("Starting QTE Ep1 Harness Mode={0} PadDiag={1} Ep1Sec={2} OutDir={3}" -f $Mode, $PadDiag, $Ep1Sec, $OutDir)
if ($Mode -eq "inject") {
    Write-Stage ("Inject Config: PAD_STICK='{0}' PAD_CLOCK='{1}' PAD_ALWAYS_CHANGE='{2}'" -f $PadStick, $PadClock, ([int][bool]$PadAlwaysChange))
} else {
    Write-Stage ("Manual Gamepad Mode: no PAD_STICK/PAD_SWEEP/PAD_SCRIPT; SkipAutoMenus={0}" -f $SkipAutoMenus)
}

$p = Start-Process -FilePath $exe -ArgumentList "`"$elf`"" -WorkingDirectory $env:PORT_ROOT -PassThru `
     -RedirectStandardOutput $outLog -RedirectStandardError $errLog
[void]$p.Handle

$failureReason = ""
$ep1Elapsed = 0.0
$capturedScreenshots = @()

try {
    if (($Mode -eq "inject") -or (-not $SkipAutoMenus)) {
        Write-Stage "[Stage 0] Waiting for Title Screen (TITLEMENU_BG00.BIK, timeout 90s)..."
        [void](Wait-ForPattern "Stage0:Title" "TITLEMENU_BG00\.BIK" 1 90 $p)
        Start-Sleep -Seconds 4
        if (Capture-Png (Join-Path $OutDir "stage_01_title.png")) { $capturedScreenshots += "stage_01_title.png" }

        Write-Stage "[Stage 1] Sending START (0x0008) on Title Screen..."
        [void](Send-PadButton "0x0008" $p)
        [void](Wait-ForPattern "Stage1:AutoLoad" "LOAD complete for 'BLUS30721-BCSAVEDATA'" 3 30 $p)
        Start-Sleep -Seconds 3
        if (Capture-Png (Join-Path $OutDir "stage_02_load_dialog.png")) { $capturedScreenshots += "stage_02_load_dialog.png" }

        Write-Stage "[Stage 2] Closing Load dialog (CROSS 0x4000) -> Main Menu..."
        [void](Send-PadButton "0x4000" $p)
        Start-Sleep -Seconds 3
        if (Capture-Png (Join-Path $OutDir "stage_03_main_menu.png")) { $capturedScreenshots += "stage_03_main_menu.png" }

        Write-Stage "[Stage 3] Selecting NEW GAME (CROSS 0x4000) -> Difficulty..."
        [void](Send-PadButton "0x4000" $p)
        Start-Sleep -Seconds 3
        if (Capture-Png (Join-Path $OutDir "stage_04_difficulty.png")) { $capturedScreenshots += "stage_04_difficulty.png" }

        Write-Stage "[Stage 4] Selecting EASY (CROSS 0x4000) -> UP (0x0010) -> Yes (CROSS 0x4000)..."
        [void](Send-PadButton "0x4000" $p)
        Start-Sleep -Seconds 3
        if (Capture-Png (Join-Path $OutDir "stage_05_easy_dialog.png")) { $capturedScreenshots += "stage_05_easy_dialog.png" }
        [void](Send-PadButton "0x0010" $p)
        Start-Sleep -Seconds 2
        [void](Send-PadButton "0x4000" $p)
        [void](Wait-ForPattern "Stage4:SaveDiff" "SAVE complete for 'BLUS30721-BCSAVEDATA'" 1 30 $p)
        Start-Sleep -Seconds 3
        if (Capture-Png (Join-Path $OutDir "stage_06_save_ok.png")) { $capturedScreenshots += "stage_06_save_ok.png" }

        Write-Stage "[Stage 5] Closing Save OK (CROSS 0x4000) -> waiting Episode 1 (timeout 90s)..."
        [void](Send-PadButton "0x4000" $p)
        [void](Wait-ForPattern "Stage5:Ep1Load" "BC-S000_L01_PDE_01\.XXX" 1 90 $p)
        Start-Sleep -Seconds 16
        if (Capture-Png (Join-Path $OutDir "stage_07_ep1_press_start.png")) { $capturedScreenshots += "stage_07_ep1_press_start.png" }

        Write-Stage "[Stage 6] Pressing START (0x0008) on Earth orbit -> Episode 1 QTE test (${Ep1Sec}s)..."
        [void](Send-PadButton "0x0008" $p)
        [System.IO.File]::WriteAllText($padFile, "", [System.Text.Encoding]::ASCII)
    } else {
        Write-Host ""
        Write-Host "==================================================================" -ForegroundColor Cyan
        Write-Host " MANUAL GAMEPAD TEST (-SkipAutoMenus): drive full game from boot! " -ForegroundColor Cyan
        Write-Host " Focus window 'Asura's Wrath' and test controller through Ep1 QTE. " -ForegroundColor Cyan
        Write-Host "==================================================================" -ForegroundColor Cyan
        Start-Sleep -Seconds 5
    }

    if ($Mode -eq "manual") {
        Write-Host ""
        Write-Host "========================================================================" -ForegroundColor Green
        Write-Host " [MANUAL INPUT READY] Klik/Fokuskan window 'Asura's Wrath' SEKARANG!   " -ForegroundColor Green
        Write-Host " - Gamepad XInput : Tarik LEFT STICK BAWAH + RIGHT STICK BAWAH          " -ForegroundColor Green
        Write-Host " - Keyboard PC    : Tahan PANAH BAWAH (Down Arrow) + K bersamaan        " -ForegroundColor Green
        Write-Host "   (Tombol lain   : Z=Cross, X=Circle, A=Square, S=Triangle, Enter=Start)" -ForegroundColor Green
        Write-Host " Tutup window setelah selesai, atau tunggu timeout ${Ep1Sec}s.           " -ForegroundColor Green
        Write-Host "========================================================================" -ForegroundColor Green
    }

    $ep1Sw = [System.Diagnostics.Stopwatch]::StartNew()
    $nextSnapSec = 10
    while ($ep1Sw.Elapsed.TotalSeconds -lt $Ep1Sec -and -not $p.HasExited) {
        $el = [int]$ep1Sw.Elapsed.TotalSeconds
        if ($el -ge $nextSnapSec) {
            $name = ("qte_t{0:D3}s.png" -f $nextSnapSec)
            if (Capture-Png (Join-Path $OutDir $name)) { $capturedScreenshots += $name }
            $nextSnapSec += 15
        }
        $err = Read-LogText $errLog
        if ($err -match "ERROR: dispatch of an SPU program") {
            throw "Episode 1 SPU dispatch MISS!"
        }
        Start-Sleep -Milliseconds 500
    }
    $ep1Elapsed = $ep1Sw.Elapsed.TotalSeconds
    if (-not $p.HasExited) {
        if (Capture-Png (Join-Path $OutDir "stage_08_ep1_end.png")) { $capturedScreenshots += "stage_08_ep1_end.png" }
        Write-Stage ("Episode 1 QTE window elapsed ({0:F1}s), sending WM_CLOSE..." -f $ep1Elapsed)
        $hWnd = [QteWinCap]::FindWindow("ps3recomp_d3d12", [NullString]::Value)
        if ($hWnd -ne [IntPtr]::Zero) {
            [void][QteWinCap]::PostMessage($hWnd, [QteWinCap]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
            if (-not $p.WaitForExit(15000)) {
                Write-Stage "WM_CLOSE wait timed out after 15s."
            } else {
                Write-Stage ("Process exited after WM_CLOSE (code={0})." -f $p.ExitCode)
            }
        }
    } else {
        Write-Stage ("User/game exited after {0:F1}s of Stage 6." -f $ep1Elapsed)
    }
} catch {
    $failureReason = $_.Exception.Message
    Write-Stage ("FAILURE: {0}" -f $failureReason)
} finally {
    if ($p) {
        $p.Refresh()
        if (-not $p.HasExited) {
            $p.Kill()
            [void]$p.WaitForExit(5000)
        }
        $p.WaitForExit()
        $p.Refresh()
    }
}

$exitCode = if ($p -and $p.HasExited -and $null -ne $p.ExitCode) { [int]$p.ExitCode } else { -1 }
$stdOutTxt = Read-LogText $outLog
$stdErrTxt = Read-LogText $errLog

$missCount     = Count-Matches ($stdOutTxt + "`n" + $stdErrTxt) "dispatch of an SPU program with no lifted image|dispatch MISS"
$abortCount    = Count-Matches ($stdOutTxt + "`n" + $stdErrTxt) "FATAL|ABORT|Unhandled exception"
$diagGetData   = Count-Matches $stdErrTxt "\[PAD_DIAG\]\[GetData\]"
$diagZeroDrain = Count-Matches $stdErrTxt "\[PAD_DIAG\]\[GetData\].*len=0"
$diagActData   = $diagGetData - $diagZeroDrain
$diagGetInfo2  = Count-Matches $stdErrTxt "\[PAD_DIAG\]\[GetInfo2\]"
$diagSetPort   = Count-Matches $stdErrTxt "\[PAD_DIAG\]\[SetPortSetting\]"
$diagPhys      = Count-Matches $stdErrTxt "\[PAD_DIAG\]\[PHYS\]"
$diagBackend   = Count-Matches $stdErrTxt "\[PAD_DIAG\]\[BACKEND\]"
$diagFocus     = Count-Matches $stdErrTxt "\[PAD_DIAG\]\[FOCUS\]"
$padStickArm   = @([regex]::Matches($stdErrTxt, "\[cellPad\] PAD_STICK.*") | ForEach-Object { $_.Value })
$diagSample    = @([regex]::Matches($stdErrTxt, "\[PAD_DIAG\].*") | ForEach-Object { $_.Value })

$summary = @(
    "=== ASURA'S WRATH QTE EP1 DIAGNOSTIC AUDIT ===",
    "Mode            : $Mode",
    "OutDir          : $OutDir",
    "ExitCode        : $exitCode",
    "FailureReason   : $(if ($failureReason) { $failureReason } else { 'NONE' })",
    "Ep1ElapsedSec   : $([math]::Round($ep1Elapsed, 2))",
    "PadStick        : $(if ($Mode -eq 'inject') { $PadStick } else { '(disabled - real gamepad/keyboard)' })",
    "PadClock        : $PadClock",
    "PadAlwaysChange : $([bool]$PadAlwaysChange)",
    "DispatchMiss    : $missCount",
    "FatalOrAbort    : $abortCount",
    "DiagPhysEvents  : $diagPhys (BackendChanges: $diagBackend, FocusChanges: $diagFocus)",
    "DiagGetInfo2    : $diagGetInfo2",
    "DiagSetPort     : $diagSetPort",
    "DiagGetDataTotal: $diagGetData (active len>0: $diagActData, drain len=0: $diagZeroDrain)",
    "Screenshots     : $($capturedScreenshots -join ', ')",
    "",
    "--- PAD_STICK status ---"
) + $padStickArm + @(
    "",
    "--- PAD_DIAG lines (first 40 & last 40) ---"
) + ($diagSample | Select-Object -First 40) + @("...") + ($diagSample | Select-Object -Last 40)

$summary -join "`r`n" | Set-Content -Path $auditTxt -Encoding UTF8
Write-Host ""
Get-Content $auditTxt

if ($failureReason -or $exitCode -ne 0 -or $missCount -gt 0 -or $abortCount -gt 0) { exit 1 }
exit 0

