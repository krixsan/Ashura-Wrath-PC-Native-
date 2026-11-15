# relift.ps1 - Asura's Wrath full relift pipeline
param(
    [switch]$SkipSPU
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root "02_REPOS\ps3recomp\tools"
$elf = Join-Path $root "00_GAME_DUMP\extracted\PS3_GAME\USRDIR\EBOOT.ELF"
$meta = Join-Path $root "03_ASURASWRATH_PORT\meta"
$recomp = Join-Path $root "03_ASURASWRATH_PORT\recompiled"
$spuOut = Join-Path $root "03_ASURASWRATH_PORT\spu"

if (-not (Test-Path $elf)) {
    Write-Error "EBOOT.ELF tidak ditemukan di $elf. Jalankan decrypt_self dulu."
}

New-Item -ItemType Directory -Force -Path $meta, $recomp, $spuOut | Out-Null

Write-Host "=== [1/4] PPU Loader ===" -ForegroundColor Cyan
py -3 "$tools\ppu_loader.py" $elf -o "$meta\loader.json"
Move-Item "$meta\loader.json\*" "$meta\" -Force -ErrorAction SilentlyContinue
Remove-Item "$meta\loader.json" -Force -ErrorAction SilentlyContinue

# Clip last function before .lib.stub
py -3 -c @"
import json
p = r'$meta\EBOOT.functions.json'
with open(p) as f: funcs = json.load(f)
for fn in funcs:
    if fn['start'] == '0x1602a0c': fn['end'] = '0x1602a30'
with open(p, 'w') as f: json.dump(funcs, f, indent=1)
"@

Write-Host "=== [2/4] PPU Lifter (32 chunks) ===" -ForegroundColor Cyan
# CMakeLists.txt auto-generates ppu_hle_nids.cpp in the build tree unless one is placed in $recomp.
py -3 "$tools\ppu_lifter.py" $elf `
    --functions "$meta\EBOOT.functions.json" `
    --hle-stubs "$meta\EBOOT.imports.json" `
    --code-end 0x1606A10 `
    --chunks 32 `
    --output $recomp

if (-not $SkipSPU) {
    Write-Host "=== [3/4] Extract SPU Images ===" -ForegroundColor Cyan
    $spuMeta = Join-Path $meta "spu"
    New-Item -ItemType Directory -Force -Path $spuMeta | Out-Null
    py -3 "$tools\extract_spu_images.py" $elf --output $spuMeta

    Write-Host "=== [4/4] Build SPU Workloads & MultiStream Overlays ===" -ForegroundColor Cyan
    py -3 "$tools\build_spu_workloads.py" `
        --images $spuMeta `
        --lifted $spuOut `
        --out "$spuOut\spu_workloads.c" `
        --register-fn asuraswrath_spu_register_all `
        --extra-funcs "spu_0000_at_017AA900=0x0837C,0x08AF8,0x0F404,0x10A54,0x125A0" `
        --return-entries `
        --constructor `
        --title asuraswrath `
        --merge-chunks `
        --relift
    py -3 "$PSScriptRoot\lift_ms_overlays.py" `
        --eboot $elf `
        --spu-dir $spuOut `
        --lifter "$tools\spu_lifter.py"
    py -3 "$PSScriptRoot\lift_spurs_jobs.py" `
        --eboot $elf `
        --spu-dir $spuOut `
        --lifter "$tools\spu_lifter.py"
}

Write-Host "Relift pipeline complete!" -ForegroundColor Green

