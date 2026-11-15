# Asura's Wrath — PS3 Native Recompilation Port (`BLUS30721`)

Native static recompilation port of **Asura's Wrath** (`BLUS30721`, PlayStation 3, Unreal Engine 3) to **Windows 10/11 x64** with **Direct3D 12** rendering, built on [ps3recomp](https://github.com/sp00nznet/ps3recomp).

> **Legal Notice**: This repository contains **only** project-owned build scripts, CMake configuration, HLE/SPU integration scaffolds, patch series, and technical documentation. **No game dumps, encrypted/decrypted ELF/SELF/SPRX binaries, PS3 firmware, keys (`appldr`, `NP_klic`), cooked `.XXX`/`.TFC` packages, `.BIK` movies, or save data are included.** Users must supply their own legally dumped copy of *Asura's Wrath* (`BLUS30721`).

---

## 1. Project Overview

| Attribute | Details |
|---|---|
| **Title / Serial** | *Asura's Wrath* (`BLUS30721`, US Base `APP_VER=01.00`) |
| **Target Platform** | Windows 10 / 11 x64 (`clang-cl` + Ninja) |
| **Graphics Backend** | Direct3D 12 (`rsx_d3d12_backend`, `1280x720` native, `rsx_shader_cache_v2`) |
| **Recompilation Pipeline** | PPU (`30,350` functions) + SPU (`27` SPU ELF images + `6` embedded SPURS `Job2` modules + `2` multistream overlays) lifted to C/C++ via `ps3recomp` |
| **Input Backend** | Windows XInput (`XInput1_4.dll` / `XInput1_3.dll`) + Win32 Keyboard fallback (`GetAsyncKeyState`) |
| **Current PRD** | [`07_DOCS/_PRD_PS3_AsurasWrath_v1.2_Laptop.md`](07_DOCS/_PRD_PS3_AsurasWrath_v1.2_Laptop.md) (`v1.2-Laptop`) |

---

## 2. Current Verification Status (Tier 0 – Tier 2)

| Tier / Test Case | Target | Status | Evidence / Reference |
|---|---|---|---|
| **Tier 0 (`TC-01`, `TC-02`)** | Boot & Engine Init (Capcom / CyberConnect2 / UE3 / SpeedTree logos, strict `SPU_MISS_FATAL=1`) | **PASS** | [`05_LOGS/tc01_no_dump.txt`](05_LOGS/tc01_no_dump.txt), [`05_LOGS/task_c_spurs_audit.txt`](05_LOGS/task_c_spurs_audit.txt) |
| **Tier 1 (`TC-03`, `TC-05`)** | Title Screen (`TITLEMENU_BG00.BIK`), Main Menu navigation, `cellSaveData` AutoSave & AutoLoad | **PASS** (tag `tier1`) | [`07_DOCS/PATCH_MAP.md`](07_DOCS/PATCH_MAP.md) |
| **Tier 2 (`TC-04`)** | Episode 1 playable (orbital combat, `CMP` `T6x1` 3D skeletal meshes, QTE `L-down + R-down`, rail-shooter transition, `35.4–39.8 FPS`) | **PASS** (tag `tier2`) | [`05_LOGS/t1_tier2_pass_audit.txt`](05_LOGS/t1_tier2_pass_audit.txt), [`05_LOGS/perf_cmp_before_after.txt`](05_LOGS/perf_cmp_before_after.txt) |
| **`TC-08`** | Deterministic full relift (`251` generated files identical across 2 consecutive runs) + full CMake/Ninja build (`exit 0`) | **PASS** | [`05_LOGS/relift_tc08_verify.txt`](05_LOGS/relift_tc08_verify.txt) |
| **`TC-09`** | Repository hygiene (zero dumps, keys, ELF/PKG/BIK/XXX binaries, or saves in Git index/history) | **PASS** | [`05_LOGS/tc09_git_root_verify.txt`](05_LOGS/tc09_git_root_verify.txt) |

---

## 3. Repository Structure

### Tracked Project Directories
- [`03_ASURASWRATH_PORT/`](03_ASURASWRATH_PORT/) — CMake build definition (`CMakeLists.txt`), runtime entrypoint (`main.cpp`), game HLE stubs (`stubs.cpp`), and lifted SPURS Job2 / multistream SPU registration (`spu/jobmods_register.c`, `spu/ms_ovl_register.c`, `spu/spujob_*`).
- [`07_DOCS/`](07_DOCS/) — Product Requirements Document ([`_PRD_PS3_AsurasWrath_v1.2_Laptop.md`](07_DOCS/_PRD_PS3_AsurasWrath_v1.2_Laptop.md)), [`PATCH_MAP.md`](07_DOCS/PATCH_MAP.md), [`KNOWN_ISSUES.md`](07_DOCS/KNOWN_ISSUES.md), [`INPUT_MAPPING.md`](07_DOCS/INPUT_MAPPING.md), [`TC07_RPCS3_COMPARISON.md`](07_DOCS/TC07_RPCS3_COMPARISON.md), exported `ps3recomp` patch series ([`07_DOCS/patches/`](07_DOCS/patches/)), and upstream PR draft ([`07_DOCS/upstream/`](07_DOCS/upstream/)).
- [`08_SCRIPTS/`](08_SCRIPTS/) — PowerShell & Python automation scripts:
  - [`env_ps3_laptop.ps1`](08_SCRIPTS/env_ps3_laptop.ps1) — Portable MSVC + LLVM `clang-cl` + Ninja environment setup.
  - [`relift.ps1`](08_SCRIPTS/relift.ps1), [`lift_spurs_jobs.py`](08_SCRIPTS/lift_spurs_jobs.py), [`lift_ms_overlays.py`](08_SCRIPTS/lift_ms_overlays.py) — Deterministic PPU + SPU + embedded SPURS Job2 relift pipeline.
  - [`build.py`](08_SCRIPTS/build.py) — CMake + Ninja build driver (`AsurasWrathRecomp.exe`).
  - [`run_ps3.ps1`](08_SCRIPTS/run_ps3.ps1) — Runtime launcher with `PS3_VFS_ROOT` validation.
  - [`test_e2e_ep1_play.ps1`](08_SCRIPTS/test_e2e_ep1_play.ps1), [`test_qte_ep1.ps1`](08_SCRIPTS/test_qte_ep1.ps1), [`test_episodes_batch.ps1`](08_SCRIPTS/test_episodes_batch.ps1) — E2E verification, 15s telemetry + `P0` hang detection, and multi-episode batch test harnesses.
- [`05_LOGS/`](05_LOGS/) — Compact text-only verification and unit-test audit logs (raw logs, screenshots, recordings, and save backups are excluded via `.gitignore`).

### Excluded Local-Only Directories (Not Published to GitHub)
- `00_GAME_DUMP/` — User-supplied PS3 game dump (`BLUS30721`) and decrypted `EBOOT.ELF`.
- `01_KEYS/` — User-supplied decryption keys.
- `02_REPOS/ps3recomp/` — Local checkout of `sp00nznet/ps3recomp` (base commit `de4f0903` + patch series in [`07_DOCS/patches/`](07_DOCS/patches/)).
- `03_ASURASWRATH_PORT/recompiled/`, `03_ASURASWRATH_PORT/meta/`, `03_ASURASWRATH_PORT/spu/spu_00*/` — Bulk auto-generated PPU/SPU C++ translation units regenerated locally by `08_SCRIPTS/relift.ps1`.
- `04_BUILD/`, `06_TOOLS/`, `gamedata/` — Compiled binaries (`AsurasWrathRecomp.exe`), shader cache, local toolchains, and runtime save data.

---

## 4. Reproducing the Build Locally

1. **Clone `ps3recomp` and apply the local patch series**:
   ```powershell
   git clone https://github.com/sp00nznet/ps3recomp.git 02_REPOS\ps3recomp
   git -C 02_REPOS\ps3recomp checkout -b asuras-wrath-local de4f090328ea08bef6b2f15caec0b85e343a7ece
   git -C 02_REPOS\ps3recomp am ..\..\07_DOCS\patches\*.patch
   ```
2. **Place your decrypted `EBOOT.ELF` and game dump** under `00_GAME_DUMP\extracted\PS3_GAME\USRDIR\EBOOT.ELF`.
3. **Run the deterministic relift pipeline**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\08_SCRIPTS\relift.ps1
   ```
4. **Build `AsurasWrathRecomp.exe`**:
   ```powershell
   py -3 .\08_SCRIPTS\build.py
   ```
5. **Run Episode 1 (Manual Gamepad / Keyboard Mode)**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\08_SCRIPTS\test_qte_ep1.ps1 -Mode manual -Ep1Sec 900
   ```
   See [`07_DOCS/INPUT_MAPPING.md`](07_DOCS/INPUT_MAPPING.md) for the full XInput gamepad and PC keyboard control table.

---

## 5. Legal & Attribution

```text
This project is an educational reverse engineering and interoperability effort.
NOT affiliated with, endorsed by, or sponsored by Capcom, CyberConnect2, or Sony Interactive Entertainment.
Users must own a legitimate copy of Asura's Wrath (BLUS30721) for PlayStation 3 and prepare their own files and keys.
This repository distributes no game files, executables, firmware, keys, or copyrighted assets.
ps3recomp is licensed under the MIT License (Copyright (c) 2026 Ned Heller / sp00nznet).
```
