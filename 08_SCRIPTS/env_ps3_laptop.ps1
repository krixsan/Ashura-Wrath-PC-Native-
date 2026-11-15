# env_ps3_laptop.ps1
$env:PORT_ROOT = Split-Path -Parent $PSScriptRoot
$env:PS3RECOMP_DIR = Join-Path $env:PORT_ROOT "02_REPOS\ps3recomp"

Write-Host "PORT_ROOT   : $env:PORT_ROOT"
Write-Host "ps3recomp   : $(Test-Path $env:PS3RECOMP_DIR) ($env:PS3RECOMP_DIR)"

# GCM: deliver VBlank/User handlers on dedicated thread (fix FIFO header holes / bogus flip ids)
if (-not $env:GCM_HANDLER_THREAD) { $env:GCM_HANDLER_THREAD = '1' }
if (-not $env:GCM_FLIPCB_ONTICK)  { $env:GCM_FLIPCB_ONTICK  = '1' }
if (-not $env:GCM_PARK_GRACE_MS)  { $env:GCM_PARK_GRACE_MS  = '50' }
if (-not $env:PS3_VERBOSE)        { $env:PS3_VERBOSE        = '0' }
if (-not $env:RSX_SHADER_CACHE_DIR) {
    $env:RSX_SHADER_CACHE_DIR = Join-Path $env:PORT_ROOT "04_BUILD\shader_cache\rsx_shader_cache_v2"
}
