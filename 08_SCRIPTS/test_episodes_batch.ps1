<#
.SYNOPSIS
    Multi-Episode Batch Runner & Save/Episode-Menu Auditor for Asura's Wrath (BLUS30721)
.DESCRIPTION
    T4/T5 Batch harness:
    1. Reads BLUS30721-BCSAVEDATA\PAYLOAD (UE3 StoryClearFlgs ArrayProperty) to detect unlocked
       episodes without guessing (ClearFlg > 0 = unlocked, ClearFlg == 0 = locked).
    2. Boots AsurasWrathRecomp.exe with SPU_MISS_FATAL=1, FRAME_BUDGET=1, PAD_DIAG=1, and enters
       EPISODE MENU (Main Menu -> DOWN -> CROSS -> BC-CHAPTERMENU.XXX / CHAPTERMENU_C01_SF.XXX).
    3. For each requested episode (-Episodes):
       - If locked in save (ClearFlg == 0): records status "BELUM TERBUKA DI SAVE (ClearFlg=0)"
         along with visual proof from EPISODE MENU (stage_05_episode_menu.png).
       - If unlocked (ClearFlg > 0): selects the episode from EPISODE MENU, runs for
         -MinutesPerEpisode minutes, takes screenshots every 15s, detects hangs (flip counter
         not advancing > 30s), parses [BUDGET] & flip deltas for FPS/frame time, and checks
         whether progress is waiting on manual QTE/prompt input ("menunggu input").
#>
param(
    [object[]]$Episodes = @(2, 3),
    [double]$MinutesPerEpisode = 1.5,
    [switch]$VerifyMenuInGame = $true,
    [string]$PadStick = "",
    [string]$OutRoot = ""
)

$ParsedEpisodes = @()
foreach ($item in $Episodes) {
    foreach ($tok in ($item.ToString() -split '[,\s]+')) {
        if ($tok -match '^\d+$') { $ParsedEpisodes += [int]$tok }
    }
}
$Episodes = $ParsedEpisodes

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "env_ps3_laptop.ps1")

if (-not $OutRoot) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutRoot = Join-Path $env:PORT_ROOT "05_LOGS\episodes_batch_$stamp"
}
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

# ---------------------------------------------------------------------------
# 1. Episode Metadata Table (BLUS30721 COOKEDPS3 & StoryClearFlgs mapping)
# ---------------------------------------------------------------------------
$EpisodeTable = @(
    @{ Ep = 1;  SaveId = 0;   Prefix = "BC-S000"; Chapter = 1; IdxInChap = 0; Title = "Episode 1: Inusable" }
    @{ Ep = 2;  SaveId = 10;  Prefix = "BC-S010"; Chapter = 1; IdxInChap = 1; Title = "Episode 2: Still Stubborn" }
    @{ Ep = 3;  SaveId = 20;  Prefix = "BC-S020"; Chapter = 1; IdxInChap = 2; Title = "Episode 3: Forever and Ever" }
    @{ Ep = 4;  SaveId = 30;  Prefix = "BC-S030"; Chapter = 1; IdxInChap = 3; Title = "Episode 4: Trying Hard" }
    @{ Ep = 5;  SaveId = 40;  Prefix = "BC-S040"; Chapter = 1; IdxInChap = 4; Title = "Episode 5: Empty Words" }
    @{ Ep = 6;  SaveId = 50;  Prefix = "BC-S050"; Chapter = 1; IdxInChap = 5; Title = "Episode 6: Proceed Then" }
    @{ Ep = 7;  SaveId = 60;  Prefix = "BC-S060"; Chapter = 2; IdxInChap = 0; Title = "Episode 7: Out of Duty" }
    @{ Ep = 8;  SaveId = 70;  Prefix = "BC-S070"; Chapter = 2; IdxInChap = 1; Title = "Episode 8: Bad Luck" }
    @{ Ep = 9;  SaveId = 80;  Prefix = "BC-S080"; Chapter = 2; IdxInChap = 2; Title = "Episode 9: Hurry Up" }
    @{ Ep = 10; SaveId = 100; Prefix = "BC-S100"; Chapter = 2; IdxInChap = 3; Title = "Episode 10: Hold Your Tongue" }
    @{ Ep = 11; SaveId = 110; Prefix = "BC-S110"; Chapter = 2; IdxInChap = 4; Title = "Episode 11: Final Words" }
    @{ Ep = 12; SaveId = 130; Prefix = "BC-S130"; Chapter = 2; IdxInChap = 5; Title = "Episode 12: Trembling Heart" }
    @{ Ep = 13; SaveId = 140; Prefix = "BC-S140"; Chapter = 3; IdxInChap = 0; Title = "Episode 13: The Causality" }
    @{ Ep = 14; SaveId = 150; Prefix = "BC-S150"; Chapter = 3; IdxInChap = 1; Title = "Episode 14: Gods of Mantra" }
    @{ Ep = 15; SaveId = 160; Prefix = "BC-S160"; Chapter = 3; IdxInChap = 2; Title = "Episode 15: Own Way" }
    @{ Ep = 16; SaveId = 180; Prefix = "BC-S180"; Chapter = 3; IdxInChap = 3; Title = "Episode 16: Realize Now" }
    @{ Ep = 17; SaveId = 190; Prefix = "BC-S190"; Chapter = 3; IdxInChap = 4; Title = "Episode 17:That Is Why" }
    @{ Ep = 18; SaveId = 200; Prefix = "BC-S200"; Chapter = 3; IdxInChap = 5; Title = "Episode 18:The Destruction" }
)

function Get-SaveEpisodeFlags([string]$payloadPath) {
    $result = @{}
    if (-not (Test-Path $payloadPath)) { return $result }
    $bytes = [System.IO.File]::ReadAllBytes($payloadPath)
    $needle = [System.Text.Encoding]::ASCII.GetBytes("ClearFlg`0")
    # Search first 30 StoryClearFlgs entries (offset < 0x0B500)
    $limit = [Math]::Min($bytes.Length - 40, 0x0B500)
    for ($i = 8; $i -lt $limit; $i++) {
        $match = $true
        for ($j = 0; $j -lt $needle.Length; $j++) {
            if ($bytes[$i + $j] -ne $needle[$j]) { $match = $false; break }
        }
        if ($match) {
            # Big-endian int32 at $i - 8 is Id; big-endian int32 at $i + 33 is ClearFlg
            $idBytes = $bytes[($i - 5)..($i - 8)]
            $cfBytes = $bytes[($i + 36)..($i + 33)]
            $idVal = [System.BitConverter]::ToInt32($idBytes, 0)
            $cfVal = [System.BitConverter]::ToInt32($cfBytes, 0)
            $result[$idVal] = [PSCustomObject]@{
                SaveId   = $idVal
                ClearFlg = $cfVal
                Offset   = ("0x{0:X5}" -f $i)
            }
        }
    }
    return $result
}

$payloadPath = Join-Path $env:PORT_ROOT "04_BUILD\gamedata\dev_hdd0\home\00000001\savedata\BLUS30721-BCSAVEDATA\PAYLOAD"
$saveFlags = Get-SaveEpisodeFlags $payloadPath

$saveAuditPath = Join-Path $OutRoot "save_episode_status.txt"
$saveLines = @(
    "=== BLUS30721-BCSAVEDATA EPISODE UNLOCK AUDIT ==="
    "PayloadPath : $payloadPath"
    "PayloadExists: $(Test-Path $payloadPath)"
    ""
    "Ep | SaveId | Prefix  | ClearFlg | Offset  | Status in Save"
    "---|--------|---------|----------|---------|----------------"
)
foreach ($meta in $EpisodeTable) {
    $entry = $saveFlags[$meta.SaveId]
    $cf = if ($entry) { $entry.ClearFlg } else { -1 }
    $off = if ($entry) { $entry.Offset } else { "N/A" }
    $st = if ($cf -gt 0) { "UNLOCKED (ClearFlg=$cf)" } elseif ($cf -eq 0) { "LOCKED (ClearFlg=0)" } else { "NO_SAVE" }
    $saveLines += ("{0,2} | {1,6} | {2,-7} | {3,8} | {4,-7} | {5}" -f $meta.Ep, $meta.SaveId, $meta.Prefix, $cf, $off, $st)
}
$saveLines | Set-Content -Path $saveAuditPath -Encoding UTF8
Write-Host ($saveLines -join "`n")

# ---------------------------------------------------------------------------
# 2. Win32 Screenshot & Process Helpers
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class BatchWinCap {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", SetLastError=true)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
"@

function Read-SharedText([string]$path) {
    if (-not (Test-Path $path)) { return "" }
    $fs = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8, $true)
        return $sr.ReadToEnd()
    } finally {
        $fs.Dispose()
    }
}

function Capture-BatchPng([string]$destPath, [string]$stageLog) {
    $hWnd = [BatchWinCap]::FindWindow("ps3recomp_d3d12", [NullString]::Value)
    if ($hWnd -eq [IntPtr]::Zero) { return $false }
    $rc = New-Object BatchWinCap+RECT
    if (-not [BatchWinCap]::GetClientRect($hWnd, [ref]$rc)) { return $false }
    $w = $rc.Right - $rc.Left
    $h = $rc.Bottom - $rc.Top
    if ($w -le 0 -or $h -le 0) { return $false }
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = [IntPtr]::Zero
    try {
        $hdc = $gfx.GetHdc()
        $ok = [BatchWinCap]::PrintWindow($hWnd, $hdc, 3)
        $gfx.ReleaseHdc($hdc)
        $hdc = [IntPtr]::Zero
        if (-not $ok) { return $false }
        $bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $msg = ("[{0}] Screenshot saved: {1} ({2} bytes)" -f (Get-Date -Format "HH:mm:ss.ff"), (Split-Path -Leaf $destPath), (Get-Item $destPath).Length)
        Write-Host $msg
        Add-Content -Path $stageLog -Value $msg
        return $true
    } finally {
        if ($hdc -ne [IntPtr]::Zero) { $gfx.ReleaseHdc($hdc) }
        $gfx.Dispose()
        $bmp.Dispose()
    }
}

function Send-BatchPad([string]$mask, [string]$padFile, [System.Diagnostics.Process]$proc, [string]$stageLog) {
    [System.IO.File]::WriteAllText($padFile, "$mask`n", [System.Text.Encoding]::ASCII)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 10 -and -not $proc.HasExited) {
        Start-Sleep -Milliseconds 50
        try {
            $cur = [System.IO.File]::ReadAllText($padFile).Trim()
            if (-not $cur) {
                $msg = ("[{0}] PAD_FILE consumed: {1} in {2} ms" -f (Get-Date -Format "HH:mm:ss.ff"), $mask, [int]$sw.ElapsedMilliseconds)
                Write-Host $msg
                Add-Content -Path $stageLog -Value $msg
                return $true
            }
        } catch {}
    }
    $msg = ("[{0}] WARNING: PAD_FILE {1} not consumed within 10s" -f (Get-Date -Format "HH:mm:ss.ff"), $mask)
    Write-Host $msg -ForegroundColor Yellow
    Add-Content -Path $stageLog -Value $msg
    return $false
}

function Wait-BatchPattern([string]$stageName, [string]$pattern, [int]$minCount, [int]$timeoutSec, [System.Diagnostics.Process]$proc, [string]$outLog, [string]$errLog, [string]$stageLog) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        if ($proc.HasExited) { throw "$stageName failed: process exited early (code=$($proc.ExitCode))" }
        $txt = Read-SharedText $outLog
        $err = Read-SharedText $errLog
        if ($err -match "SPU_MISS_FATAL|ERROR: dispatch of an SPU program") {
            throw "$stageName aborted: SPU dispatch MISS detected!"
        }
        $cnt = ([regex]::Matches(($txt + "`n" + $err), $pattern)).Count
        if ($cnt -ge $minCount) {
            $msg = ("[{0}] [{1}] Matched '{2}' ({3} >= {4}) in {5:F1}s" -f (Get-Date -Format "HH:mm:ss.ff"), $stageName, $pattern, $cnt, $minCount, $sw.Elapsed.TotalSeconds)
            Write-Host $msg
            Add-Content -Path $stageLog -Value $msg
            return $true
        }
        Start-Sleep -Milliseconds 250
    }
    throw "$stageName timed out after ${timeoutSec}s waiting for '$pattern'"
}

function Get-LatestFlipAndTime([string]$errText) {
    $m = [regex]::Matches($errText, '\[PAD_DIAG\].*t=([\d\.]+)s flip=(\d+)')
    if ($m.Count -gt 0) {
        $last = $m[$m.Count - 1]
        return [PSCustomObject]@{
            t    = [double]$last.Groups[1].Value
            flip = [int]$last.Groups[2].Value
            firstT = [double]$m[0].Groups[1].Value
            firstFlip = [int]$m[0].Groups[2].Value
        }
    }
    return $null
}

# ---------------------------------------------------------------------------
# 3. Runner Function for Entering EPISODE MENU & Executing Unlocked Episode
# ---------------------------------------------------------------------------
function Invoke-EpisodeRun([hashtable]$epMeta, [bool]$isUnlocked, [int]$clearFlg, [bool]$doMenuVerifyOnly) {
    $epNum = $epMeta.Ep
    $epDir = Join-Path $OutRoot ("ep{0:D2}_{1}" -f $epNum, $epMeta.Prefix)
    New-Item -ItemType Directory -Force -Path $epDir | Out-Null

    $outLog   = Join-Path $epDir "stdout.log"
    $errLog   = Join-Path $epDir "stderr.log"
    $stageLog = Join-Path $epDir "stages.log"
    $padFile  = Join-Path $epDir "pad.txt"
    $sumFile  = Join-Path $epDir "episode_summary.txt"

    if (-not $isUnlocked -and -not $doMenuVerifyOnly) {
        $summary = @(
            "=== EPISODE $epNum ($($epMeta.Prefix)) BATCH SUMMARY ==="
            "Episode         : Ep $epNum ($($epMeta.Title))"
            "PackagePrefix   : $($epMeta.Prefix)"
            "SaveId          : $($epMeta.SaveId)"
            "SaveClearFlg    : $clearFlg"
            "UnlockedInSave  : False"
            "Status          : BELUM TERBUKA DI SAVE (ClearFlg=0)"
            "Classification  : N/A (menunggu episode sebelumnya tamat hingga layar Save akhir episode)"
            "DispatchMiss    : 0"
            "FatalOrAbort    : 0"
            "HangDetected    : False"
            "AvgFPS          : [belum diukur]"
            "AvgFrameTimeMs  : [belum diukur]"
        )
        $summary | Set-Content -Path $sumFile -Encoding UTF8
        return [PSCustomObject]@{
            Ep             = $epNum
            Prefix         = $epMeta.Prefix
            UnlockedInSave = $false
            ClearFlg       = $clearFlg
            Status         = "BELUM TERBUKA DI SAVE (ClearFlg=0)"
            Class          = "N/A (Locked)"
            AvgFPS         = "[belum diukur]"
            FrameTimeMs    = "[belum diukur]"
            DispatchMiss   = 0
            Hang           = $false
            OutDir         = $epDir
        }
    }

    # Prepare environment for strict run
    $exe = Join-Path $env:PORT_ROOT "04_BUILD\AsurasWrathRecomp.exe"
    $elf = Join-Path $env:PORT_ROOT "00_GAME_DUMP\extracted\PS3_GAME\USRDIR\EBOOT.ELF"
    $env:PS3_VFS_ROOT      = Join-Path $env:PORT_ROOT "00_GAME_DUMP\extracted"
    $env:SPU_MISS_FATAL    = "1"
    $env:FRAME_BUDGET      = "1"
    $env:PAD_DIAG          = "1"
    $env:PAD_FILE          = $padFile
    $env:SPU_MISS_DUMP_DIR = Join-Path $epDir "miss_dumps"
    New-Item -ItemType Directory -Force -Path $env:SPU_MISS_DUMP_DIR | Out-Null
    if ($PadStick) {
        $env:PAD_STICK = $PadStick
    } else {
        Remove-Item Env:PAD_STICK -ErrorAction SilentlyContinue
    }
    [System.IO.File]::WriteAllText($padFile, "", [System.Text.Encoding]::ASCII)

    $proc = Start-Process -FilePath $exe -ArgumentList "`"$elf`"" -WorkingDirectory $env:PORT_ROOT -PassThru `
        -RedirectStandardOutput $outLog -RedirectStandardError $errLog

    $status = "UNKNOWN"
    $class  = "NONE"
    $hangDetected = $false
    $avgFpsStr = "[belum diukur]"
    $avgMsStr  = "[belum diukur]"
    $missCount = 0
    $fatalCount = 0

    try {
        # Stage 0: Title Screen
        Wait-BatchPattern "Stage0:Title" "TITLEMENU_BG00\.BIK" 1 90 $proc $outLog $errLog $stageLog | Out-Null
        Start-Sleep -Seconds 4
        Capture-BatchPng (Join-Path $epDir "stage_01_title.png") $stageLog | Out-Null

        # Stage 1: START -> AutoLoad2 complete
        Send-BatchPad "0x0008" $padFile $proc $stageLog | Out-Null
        Wait-BatchPattern "Stage1:AutoLoad" "LOAD complete for 'BLUS30721-BCSAVEDATA'" 3 30 $proc $outLog $errLog $stageLog | Out-Null
        Start-Sleep -Seconds 3
        Capture-BatchPng (Join-Path $epDir "stage_02_load_dialog.png") $stageLog | Out-Null

        # Stage 2: CROSS -> Main Menu
        Send-BatchPad "0x4000" $padFile $proc $stageLog | Out-Null
        Start-Sleep -Seconds 3
        Capture-BatchPng (Join-Path $epDir "stage_03_main_menu.png") $stageLog | Out-Null

        # Stage 3: Select EPISODE MENU (single-step DOWN "0x0040 4" -> CROSS 0x4000)
        # Note: cellPad.c:1231 documents "0x0040 4" (4 reports) so menus do not auto-repeat a 40-report hold.
        Send-BatchPad "0x0040 4" $padFile $proc $stageLog | Out-Null
        Start-Sleep -Seconds 2
        Capture-BatchPng (Join-Path $epDir "stage_04_main_menu_ep_hl.png") $stageLog | Out-Null

        Send-BatchPad "0x4000" $padFile $proc $stageLog | Out-Null
        Start-Sleep -Seconds 4
        Capture-BatchPng (Join-Path $epDir "stage_05_episode_menu.png") $stageLog | Out-Null

        $errAfterMenu = Read-SharedText $errLog
        $hasChapterMenu = ($errAfterMenu -match "BC-CHAPTERMENU\.XXX|CHAPTERMENU_C01_SF\.XXX")

        if (-not $isUnlocked) {
            if ($hasChapterMenu) {
                Send-BatchPad "0x4000" $padFile $proc $stageLog | Out-Null
                Start-Sleep -Seconds 3
                Capture-BatchPng (Join-Path $epDir "stage_06_part1_episode_list.png") $stageLog | Out-Null
                $status = "BELUM TERBUKA DI SAVE (ClearFlg=0, diverifikasi di EPISODE MENU)"
            } else {
                $status = "BELUM TERBUKA DI SAVE (ClearFlg=0; EPISODE MENU di Main Menu masih nonaktif/abu-abu karena Ep 1 ClearFlg=2 belum tamat sampai Episode Clear Save)"
            }
            $class  = "N/A (Locked in save)"
        } else {
            if ($hasChapterMenu) {
                # Navigate to Episode inside Chapter Menu:
                Send-BatchPad "0x4000" $padFile $proc $stageLog | Out-Null
                Start-Sleep -Seconds 2
                Capture-BatchPng (Join-Path $epDir "stage_06_part_episode_list.png") $stageLog | Out-Null
                for ($k = 0; $k -lt $epMeta.IdxInChap; $k++) {
                    Send-BatchPad "0x0040 4" $padFile $proc $stageLog | Out-Null
                    Start-Sleep -Seconds 1
                }
                Send-BatchPad "0x4000" $padFile $proc $stageLog | Out-Null
                Start-Sleep -Seconds 2
                Capture-BatchPng (Join-Path $epDir "stage_07_ep_difficulty.png") $stageLog | Out-Null
                Send-BatchPad "0x4000" $padFile $proc $stageLog | Out-Null
                Start-Sleep -Seconds 2
                Send-BatchPad "0x0010 4" $padFile $proc $stageLog | Out-Null
                Start-Sleep -Seconds 1
                Send-BatchPad "0x4000" $padFile $proc $stageLog | Out-Null
            } else {
                throw "EPISODE MENU is disabled on Main Menu (no episode has ClearFlg=1 cleared yet in BLUS30721-BCSAVEDATA)"
            }

            # Wait for episode package BC-Sxxx_L01
            $pkgPattern = "$($epMeta.Prefix)_L0\d_"
            Wait-BatchPattern "Stage4:EpLoad" $pkgPattern 1 90 $proc $outLog $errLog $stageLog | Out-Null
            Start-Sleep -Seconds 15
            Capture-BatchPng (Join-Path $epDir "stage_08_ep_press_start.png") $stageLog | Out-Null
            Send-BatchPad "0x0008" $padFile $proc $stageLog | Out-Null

            # Run for MinutesPerEpisode
            $targetSec = [int]([Math]::Round($MinutesPerEpisode * 60.0))
            $epSw = [System.Diagnostics.Stopwatch]::StartNew()
            $nextShot = 15
            $errStart = Read-SharedText $errLog
            $initFlipObj = Get-LatestFlipAndTime $errStart
            $startFlip = if ($initFlipObj) { $initFlipObj.flip } else { 0 }
            $startT    = if ($initFlipObj) { $initFlipObj.t } else { 0.0 }
            $lastFlip  = $startFlip
            $lastFlipChangeSec = 0.0

            while ($epSw.Elapsed.TotalSeconds -lt $targetSec) {
                if ($proc.HasExited) {
                    $status = "P0 CRASH/EXIT (code=$($proc.ExitCode))"
                    $class  = "P0"
                    break
                }
                Start-Sleep -Seconds 1
                $el = $epSw.Elapsed.TotalSeconds
                $errCur = Read-SharedText $errLog
                if ($errCur -match "SPU_MISS_FATAL|ERROR: dispatch of an SPU program") {
                    $status = "P0 SPU DISPATCH MISS"
                    $class  = "P0"
                    break
                }
                $curFlipObj = Get-LatestFlipAndTime $errCur
                if ($curFlipObj) {
                    if ($curFlipObj.flip -gt $lastFlip) {
                        $lastFlip = $curFlipObj.flip
                        $lastFlipChangeSec = $el
                    } elseif (($el - $lastFlipChangeSec) -gt 30.0) {
                        $hangDetected = $true
                        $status = "P0 HANG (flip stalled at $lastFlip for >30s)"
                        $class  = "P0"
                        break
                    }
                }
                if ($el -ge $nextShot) {
                    Capture-BatchPng (Join-Path $epDir ("ep{0:D2}_t{1:D3}s.png" -f $epNum, $nextShot)) $stageLog | Out-Null
                    $nextShot += 15
                }
            }

            $errEnd = Read-SharedText $errLog
            $endFlipObj = Get-LatestFlipAndTime $errEnd
            if ($endFlipObj -and ($endFlipObj.t - $startT) -gt 1.0) {
                $dt = $endFlipObj.t - $startT
                $df = $endFlipObj.flip - $startFlip
                $fps = $df / $dt
                $ms  = if ($fps -gt 0) { 1000.0 / $fps } else { 0.0 }
                $avgFpsStr = ("{0:F2} FPS" -f $fps)
                $avgMsStr  = ("{0:F2} ms" -f $ms)
            }

            if ($status -eq "UNKNOWN") {
                # Check if QTE/prompt held progress without physical input
                $physPressCount = ([regex]::Matches($errEnd, '\[PAD_DIAG\]\[PHYS\]')).Count
                if (-not $PadStick -and $physPressCount -eq 0 -and $targetSec -ge 75) {
                    $status = "PARSIAL (menunggu input QTE/prompt)"
                    $class  = "Menunggu Input"
                } else {
                    $status = "BERJALAN TANPA CRASH/HANG (${targetSec}s; menunggu input QTE lanjutan)"
                    $class  = "OK (In-Episode)"
                }
            }
        }
    } finally {
        if (-not $proc.HasExited) {
            $hWnd = [BatchWinCap]::FindWindow("ps3recomp_d3d12", [NullString]::Value)
            if ($hWnd -ne [IntPtr]::Zero) {
                [BatchWinCap]::PostMessage($hWnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
                $proc.WaitForExit(5000) | Out-Null
            }
            if (-not $proc.HasExited) { $proc.Kill() }
        }
    }

    $errFinal = Read-SharedText $errLog
    $missCount  = ([regex]::Matches($errFinal, "SPU_MISS_FATAL|ERROR: dispatch of an SPU program")).Count
    $fatalCount = ([regex]::Matches($errFinal, "FATAL|abort\(\) called")).Count
    $budgetLines = ([regex]::Matches($errFinal, "\[BUDGET\].*")).ForEach({ $_.Value })

    $summary = @(
        "=== EPISODE $epNum ($($epMeta.Prefix)) BATCH SUMMARY ==="
        "Episode         : Ep $epNum ($($epMeta.Title))"
        "PackagePrefix   : $($epMeta.Prefix)"
        "SaveId          : $($epMeta.SaveId)"
        "SaveClearFlg    : $clearFlg"
        "UnlockedInSave  : $isUnlocked"
        "Status          : $status"
        "Classification  : $class"
        "ExitCode        : $($proc.ExitCode)"
        "DispatchMiss    : $missCount"
        "FatalOrAbort    : $fatalCount"
        "HangDetected    : $hangDetected"
        "AvgFPS          : $avgFpsStr"
        "AvgFrameTimeMs  : $avgMsStr"
        "BudgetSamples   : $($budgetLines.Count)"
    )
    $summary | Set-Content -Path $sumFile -Encoding UTF8

    return [PSCustomObject]@{
        Ep             = $epNum
        Prefix         = $epMeta.Prefix
        UnlockedInSave = $isUnlocked
        ClearFlg       = $clearFlg
        Status         = $status
        Class          = $class
        AvgFPS         = $avgFpsStr
        FrameTimeMs    = $avgMsStr
        DispatchMiss   = $missCount
        Hang           = $hangDetected
        OutDir         = $epDir
    }
}

# ---------------------------------------------------------------------------
# 4. Execute Batch over Requested Episodes
# ---------------------------------------------------------------------------
$results = @()
$didMenuVerify = $false

foreach ($epNum in $Episodes) {
    $meta = $EpisodeTable | Where-Object { $_.Ep -eq $epNum } | Select-Object -First 1
    if (-not $meta) {
        Write-Warning "Episode $epNum not found in EpisodeTable (valid: 1..18)"
        continue
    }
    $entry = $saveFlags[$meta.SaveId]
    $cf = if ($entry) { $entry.ClearFlg } else { 0 }
    $unlocked = ($cf -gt 0)

    $doMenuVerify = $false
    if (-not $unlocked -and $VerifyMenuInGame -and -not $didMenuVerify) {
        $doMenuVerify = $true
        $didMenuVerify = $true
    }

    Write-Host "`n>>> Processing Episode $epNum ($($meta.Prefix)): ClearFlg=$cf Unlocked=$unlocked MenuVerify=$doMenuVerify <<<" -ForegroundColor Cyan
    $res = Invoke-EpisodeRun -epMeta $meta -isUnlocked $unlocked -clearFlg $cf -doMenuVerifyOnly $doMenuVerify
    $results += $res
}

$batchSummaryPath = Join-Path $OutRoot "batch_summary.txt"
$batchLines = @(
    "=== ASURA'S WRATH MULTI-EPISODE BATCH SUMMARY ==="
    "Date              : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "OutRoot           : $OutRoot"
    "RequestedEpisodes : $($Episodes -join ', ')"
    "MinutesPerEpisode : $MinutesPerEpisode"
    ""
    "Ep | Prefix  | ClearFlg | Unlocked | Status | Class | AvgFPS | FrameTime | Miss | Hang | OutDir"
    "---|---------|----------|----------|--------|-------|--------|-----------|------|------|-------"
)
foreach ($r in $results) {
    $batchLines += ("{0,2} | {1,-7} | {2,8} | {3,-8} | {4} | {5} | {6} | {7} | {8} | {9} | {10}" -f `
        $r.Ep, $r.Prefix, $r.ClearFlg, $r.UnlockedInSave, $r.Status, $r.Class, $r.AvgFPS, $r.FrameTimeMs, $r.DispatchMiss, $r.Hang, $r.OutDir)
}
$batchLines | Set-Content -Path $batchSummaryPath -Encoding UTF8
Write-Host "`n"
Write-Host ($batchLines -join "`n")
