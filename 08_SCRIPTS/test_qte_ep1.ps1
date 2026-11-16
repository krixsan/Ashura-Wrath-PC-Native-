param(
    [ValidateSet("inject", "manual")]
    [string]$Mode = "inject",
    [string]$PadStick = "128,255,128,255,190,260",
    [ValidateSet("sec", "flips")]
    [string]$PadClock = "sec",
    [switch]$PadAlwaysChange = $false,
    [switch]$SkipAutoMenus = $false,
    [string]$PadDiag = "1",
    [int]$SaveTimeoutSec = 90,
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
    $Ep1Sec = if ($Mode -eq "manual") { 900 } else { 130 }
}

if (-not $OutDir) {
    $OutDir = Join-Path $env:PORT_ROOT ("05_LOGS\qte_ep1_{0}_{1}" -f $Mode, (Get-Date -Format "yyyyMMdd_HHmmss"))
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$missDir  = Join-Path $OutDir "miss_dumps"
New-Item -ItemType Directory -Force -Path $missDir | Out-Null
$env:SPU_MISS_DUMP_DIR = $missDir
if (-not $env:RSX_CENSUS_DIR) { $env:RSX_CENSUS_DIR = $OutDir }
if (-not $env:RSX_CENSUS_TRIG) { $env:RSX_CENSUS_TRIG = Join-Path $OutDir "census.trig" }

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
        [void](Wait-ForPattern "Stage4:SaveDiff" "SAVE complete for 'BLUS30721-BCSAVEDATA'" 1 $SaveTimeoutSec $p)
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
        Write-Host " Tutup window setelah selesai (layar Episode Clear Save),               " -ForegroundColor Green
        Write-Host " atau biarkan berjalan hingga batas waktu ${Ep1Sec}s.                    " -ForegroundColor Green
        Write-Host "========================================================================" -ForegroundColor Green
    }

    # Baseline counts right at the start of Stage 6
    $initOut = Read-LogText $outLog
    $initErr = Read-LogText $errLog
    $initCombined = $initOut + "`n" + $initErr

    $stage6StartFlip = 0
    $initFlips = [regex]::Matches($initErr, "\[PAD_DIAG\][^\r\n]*?t=([0-9.]+)s\s+flip=([0-9]+)")
    if ($initFlips.Count -gt 0) {
        $stage6StartFlip = [int]$initFlips[$initFlips.Count - 1].Groups[2].Value
    }
    $prevTickFlip = $stage6StartFlip
    $prevTickWallSec = 0.0
    $lastObservedFlip = $stage6StartFlip
    $lastFlipAdvanceWallSec = 0.0
    $lastHangAlertWallSec = -999.0

    $seenBikList = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($initCombined, "\[fs\] open '([^']*\.BIK)'")) {
        $bName = Split-Path -Leaf ($m.Groups[1].Value -replace '/', '\')
        if (-not $seenBikList.Contains($bName)) { $seenBikList.Add($bName) }
    }
    $seenXxxList = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($initCombined, "\[fs\] open '([^']*\.XXX)'")) {
        $xName = Split-Path -Leaf ($m.Groups[1].Value -replace '/', '\')
        if (-not $seenXxxList.Contains($xName)) { $seenXxxList.Add($xName) }
    }
    $baselineSaveCount = Count-Matches $initCombined "SAVE complete for 'BLUS30721-BCSAVEDATA'"
    $epClearSaveNotified = 0

    $telemetryRows = @()
    $p0Hangs = @()
    $segmentRecords = @()
    $curSegName = if ($seenXxxList.Count -gt 0) { $seenXxxList[$seenXxxList.Count - 1] } else { "BC-S000_L01_PDE_01.XXX" }
    $curSegStartSec = 0.0
    $curSegStartFlip = $stage6StartFlip

    $ep1Sw = [System.Diagnostics.Stopwatch]::StartNew()
    $nextSnapSec = if ($Mode -eq "manual") { 15 } else { 10 }

    while ($ep1Sw.Elapsed.TotalSeconds -lt $Ep1Sec -and -not $p.HasExited) {
        $elWall = $ep1Sw.Elapsed.TotalSeconds
        $el = [int]$elWall

        $txt = Read-LogText $outLog
        $err = Read-LogText $errLog
        $combined = $txt + "`n" + $err

        # Track latest flip counter for hang detection (>30s without flip advancing = P0)
        $flMatches = [regex]::Matches($err, "\[PAD_DIAG\][^\r\n]*?t=([0-9.]+)s\s+flip=([0-9]+)")
        $curFlip = $lastObservedFlip
        if ($flMatches.Count -gt 0) {
            $curFlip = [int]$flMatches[$flMatches.Count - 1].Groups[2].Value
        }
        if ($curFlip -gt $lastObservedFlip) {
            $lastObservedFlip = $curFlip
            $lastFlipAdvanceWallSec = $elWall
        }
        $stallSec = $elWall - $lastFlipAdvanceWallSec
        if ($stallSec -gt 30.0 -and ($elWall - $lastHangAlertWallSec) -ge 30.0) {
            $lastHangAlertWallSec = $elWall
            $hangPng = ("p0_hang_t{0:D3}s.png" -f $el)
            if (Capture-Png (Join-Path $OutDir $hangPng)) { $capturedScreenshots += $hangPng }
            $hangMsg = ("P0 HANG DETECTED at t={0:F1}s: flip counter stalled at flip={1} for {2:F1}s (>30s) in segment '{3}'" -f $elWall, $curFlip, $stallSec, $curSegName)
            Write-Stage "[P0 HANG] $hangMsg"
            $p0Hangs += $hangMsg
        }

        if ($el -ge $nextSnapSec) {
            $snapSec = $nextSnapSec
            if ($env:RSX_CENSUS_TRIG) {
                try { Set-Content -Path $env:RSX_CENSUS_TRIG -Value ("t{0:D3}s" -f $snapSec) -Encoding Ascii } catch {}
            }
            $name = ("qte_t{0:D3}s.png" -f $snapSec)
            if (Capture-Png (Join-Path $OutDir $name)) { $capturedScreenshots += $name }

            $dtTick = [math]::Max(0.001, ($elWall - $prevTickWallSec))
            $dFlip  = $curFlip - $prevTickFlip
            $intFps = [math]::Round(($dFlip / $dtTick), 2)
            $cumFps = [math]::Round((($curFlip - $stage6StartFlip) / [math]::Max(0.001, $elWall)), 2)

            $tickMiss   = Count-Matches $combined "dispatch of an SPU program with no lifted image|dispatch MISS"
            $tickSpuErr = Count-Matches $combined "\[spu_workload\]\s*ERROR"
            $tickAbort  = Count-Matches $combined "FATAL|ABORT|Unhandled exception"
            $tickSave   = Count-Matches $combined "SAVE complete for 'BLUS30721-BCSAVEDATA'"

            $newBiks = @()
            foreach ($m in [regex]::Matches($combined, "\[fs\] open '([^']*\.BIK)'")) {
                $bName = Split-Path -Leaf ($m.Groups[1].Value -replace '/', '\')
                if (-not $seenBikList.Contains($bName)) {
                    $seenBikList.Add($bName)
                    $newBiks += $bName
                }
            }
            $newXxxs = @()
            foreach ($m in [regex]::Matches($combined, "\[fs\] open '([^']*\.XXX)'")) {
                $xName = Split-Path -Leaf ($m.Groups[1].Value -replace '/', '\')
                if (-not $seenXxxList.Contains($xName)) {
                    $seenXxxList.Add($xName)
                    $newXxxs += $xName
                }
            }

            if ($newXxxs.Count -gt 0 -or $newBiks.Count -gt 0) {
                $segDur = [math]::Max(0.001, ($elWall - $curSegStartSec))
                $segFlips = $curFlip - $curSegStartFlip
                $segFps = [math]::Round(($segFlips / $segDur), 2)
                $segmentRecords += ("{0,-32} | {1,6:F1}s .. {2,6:F1}s | flips={3,5} (+{4,4}) | avgFPS={5,6:F2}" -f $curSegName, $curSegStartSec, $elWall, $curFlip, $segFlips, $segFps)
                $curSegName = if ($newXxxs.Count -gt 0) { $newXxxs[$newXxxs.Count - 1] } else { $newBiks[$newBiks.Count - 1] }
                $curSegStartSec = $elWall
                $curSegStartFlip = $curFlip
            }

            $bikStr = if ($newBiks.Count -gt 0) { $newBiks -join "," } else { "-" }
            $xxxStr = if ($newXxxs.Count -gt 0) { $newXxxs -join "," } else { "-" }
            $hangTag = if ($stallSec -gt 30.0) { "P0_HANG" } else { "OK" }

            $telemLine = ("[TELEM t={0:D3}s] png={1} flip={2} (+{3}) FPS={4:F2} (cum={5:F2}) stall={6:F1}s[{7}] miss={8} spuErr={9} abort={10} saves={11} newBIK=[{12}] newXXX=[{13}]" -f `
                $snapSec, $name, $curFlip, $dFlip, $intFps, $cumFps, $stallSec, $hangTag, $tickMiss, $tickSpuErr, $tickAbort, $tickSave, $bikStr, $xxxStr)
            Write-Stage $telemLine
            $telemetryRows += $telemLine

            if ($tickSave -gt ($baselineSaveCount + $epClearSaveNotified)) {
                $epClearSaveNotified = $tickSave - $baselineSaveCount
                Write-Stage ("[EPISODE CLEAR SAVE] New cellSaveData SAVE complete detected during Stage 6 (total saves={0}, post-Stage4={1})!" -f $tickSave, $epClearSaveNotified)
            }

            $prevTickFlip = $curFlip
            $prevTickWallSec = $elWall
            $nextSnapSec += 15
        }

        if ($err -match "ERROR: dispatch of an SPU program") {
            throw "Episode 1 SPU dispatch MISS!"
        }
        Start-Sleep -Milliseconds 500
    }
    $ep1Elapsed = $ep1Sw.Elapsed.TotalSeconds
    if ($ep1Elapsed -gt $curSegStartSec) {
        $segDur = [math]::Max(0.001, ($ep1Elapsed - $curSegStartSec))
        $segFlips = $lastObservedFlip - $curSegStartFlip
        $segFps = [math]::Round(($segFlips / $segDur), 2)
        $segmentRecords += ("{0,-32} | {1,6:F1}s .. {2,6:F1}s | flips={3,5} (+{4,4}) | avgFPS={5,6:F2}" -f $curSegName, $curSegStartSec, $ep1Elapsed, $lastObservedFlip, $segFlips, $segFps)
    }
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
$allLogTxt = $stdOutTxt + "`n" + $stdErrTxt

$missCount     = Count-Matches $allLogTxt "dispatch of an SPU program with no lifted image|dispatch MISS"
$spuErrCount   = Count-Matches $allLogTxt "\[spu_workload\]\s*ERROR"
$abortCount    = Count-Matches $allLogTxt "FATAL|ABORT|Unhandled exception"
$totalSaveCnt  = Count-Matches $allLogTxt "SAVE complete for 'BLUS30721-BCSAVEDATA'"
$epClearSaves  = [math]::Max(0, ($totalSaveCnt - 1))
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
$spursJobs     = @([regex]::Matches($allLogTxt, "\[cellSpurs\] JobChainAttributeSetName\([^\r\n]*|\[spu_workload\][^\r\n]*") | ForEach-Object { $_.Value } | Select-Object -Unique)
$shaderVidErrs = @([regex]::Matches($allLogTxt, "rejects=[1-9][0-9]*|\[D3D12\][^\r\n]*ERROR|\[bink\][^\r\n]*ERROR") | ForEach-Object { $_.Value })

# Read-only post-run check of BLUS30721-BCSAVEDATA\PAYLOAD
$savePayloadPath = Join-Path $env:PORT_ROOT "04_BUILD\gamedata\dev_hdd0\home\00000001\savedata\BLUS30721-BCSAVEDATA\PAYLOAD"
$saveCheckLines = @()
if (Test-Path $savePayloadPath) {
    $svItem = Get-Item $savePayloadPath
    $svHash = (Get-FileHash $savePayloadPath -Algorithm SHA256).Hash
    $svBytes = [System.IO.File]::ReadAllBytes($savePayloadPath)
    $svAscii = [System.Text.Encoding]::ASCII.GetString($svBytes)
    $saveCheckLines += ("PAYLOAD Path : {0}" -f $savePayloadPath)
    $saveCheckLines += ("PAYLOAD Size : {0} bytes | mtime={1} | sha256={2}" -f $svItem.Length, $svItem.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"), $svHash)
    $svMatches = [regex]::Matches($svAscii, "ClearFlg\0")
    for ($si = 0; $si -lt [math]::Min(6, $svMatches.Count); $si++) {
        $pos = $svMatches[$si].Index
        if ($pos -ge 0x0B500) { break }
        $idOff = $pos - 8
        $valOff = $pos + 33
        $idVal = ([int]$svBytes[$idOff] -shl 24) -bor ([int]$svBytes[$idOff+1] -shl 16) -bor ([int]$svBytes[$idOff+2] -shl 8) -bor [int]$svBytes[$idOff+3]
        $flgVal = ([int]$svBytes[$valOff] -shl 24) -bor ([int]$svBytes[$valOff+1] -shl 16) -bor ([int]$svBytes[$valOff+2] -shl 8) -bor [int]$svBytes[$valOff+3]
        $saveCheckLines += ("  StoryClearFlgs[{0}] (Id={1,3}) : ClearFlg={2} (offset=0x{3:X5})" -f $si, $idVal, $flgVal, $valOff)
    }
} else {
    $saveCheckLines += "PAYLOAD not found at $savePayloadPath"
}

$stage6AvgFps = if ($ep1Elapsed -gt 0 -and $lastObservedFlip -ge $stage6StartFlip) {
    [math]::Round((($lastObservedFlip - $stage6StartFlip) / $ep1Elapsed), 2)
} else { 0.0 }

$summary = @(
    "=== ASURA'S WRATH QTE EP1 DIAGNOSTIC AUDIT ===",
    "Mode                 : $Mode",
    "OutDir               : $OutDir",
    "ExitCode             : $exitCode",
    "FailureReason        : $(if ($failureReason) { $failureReason } else { 'NONE' })",
    "Ep1ElapsedSec        : $([math]::Round($ep1Elapsed, 2)) (target=${Ep1Sec}s)",
    "Stage6Flips          : $stage6StartFlip -> $lastObservedFlip (+$($lastObservedFlip - $stage6StartFlip), AvgFPS=$stage6AvgFps)",
    "PadStick             : $(if ($Mode -eq 'inject') { $PadStick } else { '(disabled - real gamepad/keyboard)' })",
    "PadClock             : $PadClock",
    "PadAlwaysChange      : $([bool]$PadAlwaysChange)",
    "DispatchMiss         : $missCount",
    "SpuWorkloadError     : $spuErrCount",
    "FatalOrAbort         : $abortCount",
    "P0HangCount          : $($p0Hangs.Count)",
    "SaveCompleteTotal    : $totalSaveCnt (EpisodeClearSavesPostStage4: $epClearSaves)",
    "DiagPhysEvents       : $diagPhys (BackendChanges: $diagBackend, FocusChanges: $diagFocus)",
    "DiagGetInfo2         : $diagGetInfo2",
    "DiagSetPort          : $diagSetPort",
    "DiagGetDataTotal     : $diagGetData (active len>0: $diagActData, drain len=0: $diagZeroDrain)",
    "OpenedBikFiles       : $($seenBikList -join ', ')",
    "StreamedXxxPackages  : $($seenXxxList -join ', ')",
    "Screenshots          : $($capturedScreenshots -join ', ')",
    "",
    "--- P0 HANG CHECK (>30s flip stall) ---"
) + $(if ($p0Hangs.Count -gt 0) { $p0Hangs } else { @("NONE (0 stalls > 30s)") }) + @(
    "",
    "--- PER-15s TELEMETRY LOG ---"
) + $telemetryRows + @(
    "",
    "--- FPS PER SEGMENT (SUB-LEVEL .XXX / .BIK) ---"
) + $segmentRecords + @(
    "",
    "--- POST-RUN SAVE STATUS (READ-ONLY) ---"
) + $saveCheckLines + @(
    "",
    "--- SPURS / SPU WORKLOAD SUMMARY ---"
) + $spursJobs + @(
    "",
    "--- SHADER / VIDEO ERRORS ---"
) + $(if ($shaderVidErrs.Count -gt 0) { $shaderVidErrs } else { @("NONE") }) + @(
    "",
    "--- PAD_STICK status ---"
) + $padStickArm + @(
    "",
    "--- PAD_DIAG lines (first 40 & last 40) ---"
) + ($diagSample | Select-Object -First 40) + @("...") + ($diagSample | Select-Object -Last 40)

$summary -join "`r`n" | Set-Content -Path $auditTxt -Encoding UTF8
Write-Host ""
Get-Content $auditTxt

if ($failureReason -or $exitCode -ne 0 -or $missCount -gt 0 -or $spuErrCount -gt 0 -or $abortCount -gt 0 -or $p0Hangs.Count -gt 0) { exit 1 }
exit 0

