# test_e2e_ep1_play.ps1 - Stage-logged E2E runner for Asura's Wrath (Tier 2 >=5m & TC-05)
param(
    [ValidateSet("tier2", "tc05")]
    [string]$Mode = "tier2",
    [int]$Ep1DurationSec = 330,
    [double]$FrameRate = 2.0,
    [int]$ShotIntervalSec = 30,
    [string]$PadStick = "128,255,128,255,190,260",
    [string]$OutDir = "",
    [string]$ExeName = "AsurasWrathRecomp.exe",
    [string]$ElfPath = "00_GAME_DUMP\extracted\PS3_GAME\USRDIR\EBOOT.ELF",
    [switch]$AllowMiss = $false
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "env_ps3_laptop.ps1")
if (-not $env:PS3_VFS_ROOT) {
    $env:PS3_VFS_ROOT = Join-Path $env:PORT_ROOT "00_GAME_DUMP\extracted"
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $env:RSX_SHADER_CACHE_DIR) | Out-Null

$exe = Join-Path $env:PORT_ROOT "04_BUILD\$ExeName"
if (-not (Test-Path $exe)) { Write-Error "Exe not found: $exe"; exit 1 }
$targetElf = Join-Path $env:PORT_ROOT $ElfPath
if (-not (Test-Path $targetElf)) { Write-Error "ELF not found: $targetElf"; exit 1 }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
if (-not $OutDir) {
    $OutDir = Join-Path $env:PORT_ROOT ("05_LOGS\e2e_{0}_{1}" -f $Mode, $stamp)
}
$framesDir = Join-Path $OutDir "frames"
$missDir   = Join-Path $OutDir "miss_dumps"
New-Item -ItemType Directory -Force -Path $OutDir, $framesDir, $missDir | Out-Null

$outLog   = Join-Path $OutDir "stdout.log"
$errLog   = Join-Path $OutDir "stderr.log"
$stageLog = Join-Path $OutDir "stages.log"
$padFile  = Join-Path $OutDir "pad.txt"
$auditTxt = Join-Path $OutDir "audit_summary.txt"
[System.IO.File]::WriteAllText($padFile, "", [System.Text.UTF8Encoding]::new($false))

$env:PAD_FILE             = $padFile
if ($Mode -eq "tier2" -and $PadStick) {
    $env:PAD_STICK = $PadStick
} else {
    Remove-Item Env:PAD_STICK -ErrorAction SilentlyContinue
}
$env:PS3_STDIO_UNBUFFERED = "1"
$env:PS3_WATCHDOG         = "1"
$env:SPU_DUMP_MISS        = $missDir
$env:SPU_MISS_FATAL       = if ($AllowMiss) { "0" } else { "1" }

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class WinCap {
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

function Capture-Frame([string]$destPath, [string]$fmt) {
    $hWnd = [WinCap]::FindWindow("ps3recomp_d3d12", [NullString]::Value)
    if ($hWnd -eq [IntPtr]::Zero) { return $false }
    $rc = New-Object WinCap+RECT
    if (-not [WinCap]::GetClientRect($hWnd, [ref]$rc)) { return $false }
    $w = $rc.Right - $rc.Left
    $h = $rc.Bottom - $rc.Top
    if ($w -le 0 -or $h -le 0) { return $false }
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = [IntPtr]::Zero
    try {
        $hdc = $gfx.GetHdc()
        $ok = [WinCap]::PrintWindow($hWnd, $hdc, 3)
        $gfx.ReleaseHdc($hdc)
        $hdc = [IntPtr]::Zero
        if (-not $ok) { return $false }
        if ($fmt -eq "jpg") {
            $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" } | Select-Object -First 1
            $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
            $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]88)
            $bmp.Save($destPath, $codec, $ep)
            $ep.Dispose()
        } else {
            $bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        return $true
    } finally {
        if ($hdc -ne [IntPtr]::Zero) { try { $gfx.ReleaseHdc($hdc) } catch {} }
        $gfx.Dispose()
        $bmp.Dispose()
    }
}

function Save-StageShot([string]$filename) {
    $p = Join-Path $OutDir $filename
    if (Capture-Frame $p "png") {
        Write-Stage "Screenshot saved: $filename ($((Get-Item $p).Length) bytes)"
    } else {
        Write-Stage "WARNING: Screenshot capture failed for $filename"
    }
}

function Send-Pad([string]$maskHex, [int]$polls = 3, [int]$timeoutMs = 5000, [System.Diagnostics.Process]$proc = $null) {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($padFile, "$maskHex $polls`n", $utf8NoBom)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
        if ($proc -and $proc.HasExited) { throw "Target process exited unexpectedly with code $($proc.ExitCode)" }
        try {
            $cur = [System.IO.File]::ReadAllText($padFile).Trim()
            if (-not $cur) {
                Write-Stage "PAD consumed: $maskHex ($polls polls) in $($sw.ElapsedMilliseconds)ms"
                return $true
            }
        } catch {}
        Start-Sleep -Milliseconds 100
    }
    Write-Stage "WARNING: PAD $maskHex not cleared within ${timeoutMs}ms"
    return $false
}

function Wait-ForPattern([string]$logPath, [string]$pattern, [int]$minCount, [int]$timeoutSec, [System.Diagnostics.Process]$proc, [string]$stageName) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        if ($proc.HasExited) {
            throw "[$stageName] Process exited early (code $($proc.ExitCode))"
        }
        $txt = Read-LogText $logPath
        $n = Count-Matches $txt $pattern
        if ($n -ge $minCount) {
            Write-Stage "[$stageName] Matched '$pattern' ($n >= $minCount) in $([math]::Round($sw.Elapsed.TotalSeconds, 2))s"
            return $true
        }
        Start-Sleep -Milliseconds 250
    }
    Write-Stage "[$stageName] TIMEOUT after ${timeoutSec}s waiting for '$pattern' ($minCount)"
    return $false
}

Write-Stage "Starting E2E Mode=$Mode OutDir=$OutDir SPU_MISS_FATAL=$($env:SPU_MISS_FATAL)"
Write-Stage "Exe=$exe Elf=$targetElf"

$p = Start-Process -FilePath $exe -ArgumentList "`"$targetElf`"" -WorkingDirectory $env:PORT_ROOT `
     -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errLog
$null = $p.Handle

$frameIdx = 0
$ep1Elapsed = 0.0
$ep1FramesStart = 0
$ep1FramesEnd = 0
$failureReason = ""

try {
    # Stage 0: Wait for Title Screen Bink after Capcom / CC2 / UE3 / SpeedTree logos
    Write-Stage "[Stage 0] Waiting for TITLEMENU_BG00.BIK (timeout 90s)..."
    if (-not (Wait-ForPattern $errLog "TITLEMENU_BG00\.BIK" 1 90 $p "Stage 0:Title")) {
        Save-StageShot "fail_stage0_title.png"
        throw "Timeout reaching Title Screen"
    }
    Start-Sleep -Seconds 5
    Save-StageShot "stage_01_title.png"

    # Stage 1: Press START -> wait for SaveData auto-load (or initial creation)
    Write-Stage "[Stage 1] Sending START (0x0008) on Title Screen..."
    $loadBefore = Count-Matches (Read-LogText $outLog) "LOAD complete for 'BLUS30721-BCSAVEDATA'"
    $saveBefore = Count-Matches (Read-LogText $outLog) "SAVE complete for 'BLUS30721-BCSAVEDATA'"
    [void](Send-Pad "0x0008" 3 5000 $p)

    $gotLoad = $false
    $swLoad = [System.Diagnostics.Stopwatch]::StartNew()
    while ($swLoad.Elapsed.TotalSeconds -lt 35) {
        if ($p.HasExited) { throw "Process exited during Stage 1 Load" }
        $txt = Read-LogText $outLog
        $loads = Count-Matches $txt "LOAD complete for 'BLUS30721-BCSAVEDATA'"
        $saves = Count-Matches $txt "SAVE complete for 'BLUS30721-BCSAVEDATA'"
        if ($loads -ge ($loadBefore + 2) -or $saves -ge ($saveBefore + 1)) {
            $gotLoad = $true
            Write-Stage "[Stage 1] Auto-Load/Save completed (loads=$loads, saves=$saves) in $([math]::Round($swLoad.Elapsed.TotalSeconds, 2))s"
            break
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $gotLoad) {
        Save-StageShot "fail_stage1_load.png"
        throw "Timeout waiting for Load/Save dialog after Title START"
    }
    Start-Sleep -Seconds 4.5
    Save-StageShot "stage_02_load_dialog.png"

    # Stage 2: Close Load dialog -> Main Menu
    Write-Stage "[Stage 2] Closing Load dialog with CROSS (0x4000) -> Main Menu..."
    [void](Send-Pad "0x4000" 3 5000 $p)
    Start-Sleep -Seconds 4.5
    Save-StageShot "stage_03_main_menu.png"

    if ($Mode -eq "tc05") {
        Write-Stage "[TC-05] Auto-load & Main Menu verified; requesting clean WM_CLOSE..."
    } else {
        # Stage 3: Select NEW GAME
        Write-Stage "[Stage 3] Selecting NEW GAME (CROSS 0x4000)..."
        [void](Send-Pad "0x4000" 3 5000 $p)
        Start-Sleep -Seconds 4.5
        Save-StageShot "stage_04_difficulty.png"

        # Stage 4: Select EASY & handle "Start the game on EASY? Yes/No" (default No -> UP -> Yes -> CROSS)
        $saveStarted = $false
        for ($attempt = 1; $attempt -le 3 -and -not $saveStarted; $attempt++) {
            $savesBase = Count-Matches (Read-LogText $outLog) "SAVE complete for 'BLUS30721-BCSAVEDATA'"
            Write-Stage "[Stage 4 attempt $attempt/3] Selecting EASY (CROSS 0x4000)..."
            [void](Send-Pad "0x4000" 3 5000 $p)
            Start-Sleep -Seconds 3.5
            Save-StageShot "stage_05_easy_dialog_a${attempt}.png"

            Write-Stage "[Stage 4 attempt $attempt/3] Navigating UP (0x0010) to 'Yes'..."
            [void](Send-Pad "0x0010" 3 5000 $p)
            Start-Sleep -Seconds 1.8
            Save-StageShot "stage_06_easy_yes_a${attempt}.png"

            Write-Stage "[Stage 4 attempt $attempt/3] Confirming 'Yes' with CROSS (0x4000)..."
            [void](Send-Pad "0x4000" 3 5000 $p)

            $saveStarted = Wait-ForPattern $outLog "SAVE complete for 'BLUS30721-BCSAVEDATA'" ($savesBase + 1) 20 $p "Stage 4:SaveDifficulty"
        }
        if (-not $saveStarted) {
            Save-StageShot "fail_stage4_easy_dialog.png"
            throw "Failed to confirm 'Start the game on EASY? Yes' after 3 attempts"
        }
        Start-Sleep -Seconds 3.0
        Save-StageShot "stage_07_save_ok.png"

        # Stage 5: Close Save dialog -> wait for Episode 1 (BC-S000_L01_PDE_01.XXX)
        Write-Stage "[Stage 5] Closing Save OK dialog (CROSS 0x4000) -> waiting Episode 1 (timeout 90s)..."
        [void](Send-Pad "0x4000" 3 5000 $p)
        if (-not (Wait-ForPattern $errLog "BC-S000_L01_PDE_01\.XXX" 1 90 $p "Stage 5:Ep1Load")) {
            Save-StageShot "fail_stage5_ep1_load.png"
            throw "Timeout waiting for BC-S000_L01_PDE_01.XXX"
        }
        Start-Sleep -Seconds 16
        Save-StageShot "stage_08_ep1_press_start.png"

        # Stage 6: Enter Episode 1 gameplay & record >= Ep1DurationSec
        Write-Stage "[Stage 6] Pressing START (0x0008) on Earth orbit -> Episode 1 gameplay (${Ep1DurationSec}s)..."
        [void](Send-Pad "0x0008" 3 5000 $p)

        $swEp1 = [System.Diagnostics.Stopwatch]::StartNew()
        $frameIntervalMs = [int](1000.0 / $FrameRate)
        $nextFrameMs = 0
        $nextShotSec = 10
        $nextInputSec = 8
        $inputStep = 0
        $ep1FramesStart = $frameIdx + 1

        # Cycle combat & QTE buttons cleanly during Episode 1:
        # 0x8000 = SQUARE (Rapid Fire), 0x2000 = CIRCLE (Lock/Burst), 0x1000 = TRIANGLE,
        # 0x4000 = CROSS, 0x0200 = R2 (Burst), 0x0800 = R1
        $inputs = @(
            @{ mask = "0x8000"; polls = 6; name = "SQUARE" },
            @{ mask = "0x8000"; polls = 6; name = "SQUARE" },
            @{ mask = "0x2000"; polls = 4; name = "CIRCLE" },
            @{ mask = "0x0200"; polls = 6; name = "R2" },
            @{ mask = "0x1000"; polls = 4; name = "TRIANGLE" },
            @{ mask = "0x4000"; polls = 4; name = "CROSS" },
            @{ mask = "0x0800"; polls = 4; name = "R1" }
        )

        while ($swEp1.Elapsed.TotalSeconds -lt $Ep1DurationSec) {
            if ($p.HasExited) {
                [void](Capture-Frame (Join-Path $OutDir "crash_ep1.png") "png")
                throw "Process crashed/exited during Episode 1 at $([math]::Round($swEp1.Elapsed.TotalSeconds, 1))s with code $($p.ExitCode)"
            }
            $secNow = $swEp1.Elapsed.TotalSeconds
            $msNow  = $swEp1.ElapsedMilliseconds

            if ($msNow -ge $nextFrameMs) {
                $nextIdx = $frameIdx + 1
                $fPath = Join-Path $framesDir ("f_{0:D5}.jpg" -f $nextIdx)
                if (Capture-Frame $fPath "jpg") {
                    $frameIdx = $nextIdx
                }
                $nextFrameMs += $frameIntervalMs
            }

            if ($secNow -ge $nextShotSec) {
                Save-StageShot ("ep1_t{0:D3}s.png" -f [int]$secNow)
                $nextShotSec += $ShotIntervalSec
            }

            if ($secNow -ge $nextInputSec) {
                $cmd = $inputs[$inputStep % $inputs.Count]
                [System.IO.File]::WriteAllText($padFile, "$($cmd.mask) $($cmd.polls)`n", [System.Text.UTF8Encoding]::new($false))
                $inputStep++
                $nextInputSec += 4
            }

            Start-Sleep -Milliseconds 100
        }
        $ep1Elapsed = $swEp1.Elapsed.TotalSeconds
        $ep1FramesEnd = $frameIdx
        Save-StageShot "stage_09_ep1_end.png"
        Write-Stage ("[Stage 6] Episode 1 completed {0:F2}s ({1} frames captured)" -f $ep1Elapsed, $frameIdx)
    }
} catch {
    $failureReason = $_.Exception.Message
    Write-Stage "ERROR: $failureReason"
} finally {
    # Clean close via WM_CLOSE
    if ($p -and -not $p.HasExited) {
        $hWnd = [WinCap]::FindWindow("ps3recomp_d3d12", [NullString]::Value)
        if ($hWnd -ne [IntPtr]::Zero) {
            Write-Stage "Sending WM_CLOSE to hWnd=$hWnd..."
            [void][WinCap]::PostMessage($hWnd, [WinCap]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
            [void]$p.WaitForExit(15000)
        }
        if (-not $p.HasExited) {
            Write-Stage "Force stopping process after WM_CLOSE timeout..."
            $p.Kill()
            [void]$p.WaitForExit(5000)
        }
    }
}

$exitCode = if ($p -and $null -ne $p.ExitCode) { [int]$p.ExitCode } else { -1 }
Write-Stage "Process finished with exitCode=$exitCode"

# Assemble MP4 recording if Tier 2 captured frames & ffmpeg exists
$recPath = Join-Path $OutDir "ep1_recording.mp4"
$ffmpegCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($Mode -eq "tier2" -and $frameIdx -gt 5 -and $ffmpegCmd -and $ep1Elapsed -gt 1) {
    $actualFps = $frameIdx / $ep1Elapsed
    Write-Stage ("Encoding {0} frames over {1:F2}s (fps={2:F4}) -> {3}" -f $frameIdx, $ep1Elapsed, $actualFps, $recPath)
    $ffArgs = @(
        "-y", "-loglevel", "error",
        "-framerate", $actualFps.ToString("F4", [System.Globalization.CultureInfo]::InvariantCulture),
        "-i", (Join-Path $framesDir "f_%05d.jpg"),
        "-c:v", "libx264", "-preset", "fast", "-crf", "22", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        $recPath
    )
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $ffmpegCmd.Source @ffArgs 2>&1 | Out-Null
        $ffExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
    if ($ffExit -eq 0 -and (Test-Path $recPath) -and ((Get-Item $recPath).Length -gt 10240)) {
        Remove-Item $framesDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Stage "Encoded $recPath successfully ($([math]::Round((Get-Item $recPath).Length / 1MB, 2)) MB)"
    } else {
        Write-Stage "WARNING: ffmpeg failed (exit=$ffExit); raw frames kept in $framesDir"
    }
}

# Final Log & Crash Audit
$stdOutTxt = Read-LogText $outLog
$stdErrTxt = Read-LogText $errLog
$missCount     = Count-Matches ($stdOutTxt + "`n" + $stdErrTxt) "dispatch of an SPU program with no lifted image|dispatch MISS"
$jumpParkCount = Count-Matches ($stdOutTxt + "`n" + $stdErrTxt) "jump-park"
$abortCount    = Count-Matches ($stdOutTxt + "`n" + $stdErrTxt) "FATAL|ABORT|Unhandled exception"
$drawMatches   = [regex]::Matches($stdOutTxt, "\[D3D12\] draw_arrays #(\d+)")
$maxDraw       = if ($drawMatches.Count -gt 0) { $drawMatches[$drawMatches.Count - 1].Groups[1].Value } else { "0" }
$wdMemMatches  = [regex]::Matches($stdErrTxt, "\[WATCHDOG MEM\].*")
$lastWdMem     = if ($wdMemMatches.Count -gt 0) { $wdMemMatches[$wdMemMatches.Count - 1].Value } else { "(none)" }
$missFiles     = @(Get-ChildItem $missDir -File -ErrorAction SilentlyContinue)
$loadLines     = @([regex]::Matches($stdOutTxt, "\[cellSaveData\].*") | ForEach-Object { $_.Value })
$spuMissLines  = @([regex]::Matches(($stdOutTxt + "`n" + $stdErrTxt), "ERROR:.*SPU program.*") | ForEach-Object { $_.Value })

$summary = @(
    "=== ASURA'S WRATH E2E AUDIT ($Mode) ===",
    "Timestamp      : $(Get-Date -Format o)",
    "OutDir         : $OutDir",
    "ExitCode       : $exitCode",
    "FailureReason  : $(if ($failureReason) { $failureReason } else { 'NONE' })",
    "SPU_MISS_FATAL : $($env:SPU_MISS_FATAL)",
    "Ep1DurationSec : $([math]::Round($ep1Elapsed, 2))",
    "FramesCaptured : $frameIdx",
    "RecordingMP4   : $(if (Test-Path $recPath) { "$recPath ($([math]::Round((Get-Item $recPath).Length / 1MB, 2)) MB)" } else { 'NONE' })",
    "MaxDrawArrays  : $maxDraw",
    "DispatchMiss   : $missCount (miss_dumps files: $($missFiles.Count))",
    "JumpPark       : $jumpParkCount",
    "FatalOrAbort   : $abortCount",
    "LastWatchdogMem: $lastWdMem",
    "",
    "--- cellSaveData events ---"
) + $loadLines + @(
    "",
    "--- Dispatch MISS lines ---"
) + $spuMissLines

$summary -join "`r`n" | Set-Content -Path $auditTxt -Encoding UTF8
Write-Host ""
Get-Content $auditTxt

$passed = (-not $failureReason) -and ($exitCode -eq 0) -and ($missCount -eq 0) -and ($missFiles.Count -eq 0) -and ($abortCount -eq 0)
if ($Mode -eq "tier2") {
    $passed = $passed -and ($ep1Elapsed -ge 300)
}
if (-not $passed) { exit 1 } else { exit 0 }

