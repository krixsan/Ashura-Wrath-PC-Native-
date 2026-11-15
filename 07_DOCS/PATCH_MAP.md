# PATCH MAP - Asura's Wrath (PS3)

Catatan patch lokal pada `02_REPOS\ps3recomp`, konfigurasi build/script, dan status cakupan komponen untuk port *Asura's Wrath* (`BLUS30721`).

## 1. Ringkasan Patch Terverifikasi

| Area | File / Lokasi | Status | Catatan Terverifikasi |
|---|---|---|---|
| RSX / 2D-to-3D Routing | `02_REPOS\ps3recomp\libs\video\cellGcmSys.c` (`1543-1639`, `1760-1775`, `2938`, `3107`) | Fixed lokal | Implementasi permanen PS3 `libgcm` `NV0039` (`m2mf`, linear DMA copy) dan auto-routing `subch 1` (`gcm_subch1_route_2d`, `gcm_is_nv0039_method`, `nv0039_transfer`) untuk method `0x0180..0x0188` dan `0x030C..0x0328` tanpa merusak `NV4097_SET_COLOR_MASK` (`0x0324`). Auto-switch ke 3D tetap aktif jika game mengikat `NV4097` ke `subch 1`, plus override env `GCM_SUBCH1_2D` / `GCM_SUBCH1_3D`. Context DMA dibatasi aman ke `0xFEED0000` (LOCAL) / `0xFEED0001` (MAIN), melewati handle notify non-VRAM seperti `0x66626660`. Print debug sementara (`CMASK_DBG` / `CMASK_CTX`) telah dihapus. |
| RSX / Debug Cleanup | `02_REPOS\ps3recomp\libs\video\rsx_commands.c` | Fixed lokal | Penghapusan print debug sementara (`CMASK_DBG` / `CMASK_CTX`) setelah verifikasi rendering Bink/RSX. |
| RSX / D3D12 & Shader Cache | `02_REPOS\ps3recomp\libs\video\rsx_d3d12_backend.c`, `rsx_d3d12_device.h`, `rsx_fp_decompiler.c`, `rsx_live_draw.c` | Fixed lokal | Perubahan backend D3D12, deklarasi device/shader disk cache (`rsx_shader_cache_v2` / `[shader-disk-cache]`), decompiler FP, dan live draw. Terverifikasi oleh `test_d3d12_device_pick.c` (`31 passed, 0 failed`), runtime `VP_DIAG count=48`, `[BUDGET] 0 draws truncated`, dan warm/cold disk cache (`rejects=0`). |
| RSX / Vertex Fetch (`CMP` `T6x1`) | `02_REPOS\ps3recomp\libs\video\rsx_vertex_fetch.c:100-118`, `libs\video\tests\test_vertex_fetch_cmp.c`, `CMakeLists.txt` | Fixed lokal + unit test + draf PR | Tambah early `return;` di `rsx_fetch_attrib` `case 6:` (`CELL_GCM_VERTEX_CMP` 11-11-10) tepat setelah `out[3] = 1.0f;` agar atribut `T6x1` UE3 (`size=1`) tidak jatuh ke ekspansi skalar `if (n < 3) out[2] = 0.0f; if (n < 2) out[1] = 0.0f;`. Mengikuti pola `rsx_live_draw.c:5744` & `rsx_vertex_compact.c:84`. Diuji unit test `test_vertex_fetch_cmp` (`0 failure(s)`, `05_LOGS\test_vertex_fetch_cmp.log`) dan E2E `05_LOGS\draw_census_20261115_110049` -> `05_LOGS\draw_census_20261115_111217` (`T6x_a0_zero`: `2/3` & `25/43` -> `0/3` & `0/86`; geometri 3D & tentakel pulih di `qte_t070s.png` / `qte_t085s.png` / `stage_08_ep1_end.png`; performa naik `31.04 -> 35.43 FPS` di `05_LOGS\perf_cmp_before_after.txt`). Draf PR hulu disimpan di `07_DOCS\upstream\PR_DRAFT_rsx_vertex_fetch_cmp.md` & `07_DOCS\upstream\0001-rsx_vertex_fetch-return-early-for-CMP-attributes.patch`. |
| RSX & SPU / Draw Census, Drop-Log & SPU Audit | `02_REPOS\ps3recomp\libs\video\rsx_d3d12_backend.c`, `rsx_commands.c`, `libs\spurs\cellSpurs.c`, `runtime\spu\spu_workload.{c,h}`, `spu_lifted_job.h` | Diagnostik terpasang (env-gated) | Sensus per-draw CSV/ringkasan (`RSX_CENSUS_DIR`, `RSX_CENSUS_TRIG`), log eksplisit tiap draw yang di-skip/drop (`RSX_DROP_LOG=1` -> `[RSX_DROP]`), serta pelacakan DMA PUT SPU vs pembacaan buffer vertex/index RSX (`RSX_SPU_AUDIT=1`). Aktif hanya saat env var disetel. |
| SPU / Build Tooling | `02_REPOS\ps3recomp\tools\build_spu_workloads.py:178` | Fixed lokal | Perbaikan indentasi `extra_funcs[img]` yang sebelumnya berada di bawah `if args.merge_chunks` sehingga memicu `KeyError` saat kosong; dipindah ke blok `if img in extra_funcs`. |
| Toolchain / Windows MSVC | `02_REPOS\ps3recomp\tools\msvc_env.py:44` | Fixed lokal | Tambah fallback deteksi `portable_msvc/msvc/setup_x64.bat` agar kompilasi `clang-cl` berjalan di Windows tanpa instalasi VS resmi / hak admin. |
| SPURS / SPU Runtime & Tests | `02_REPOS\ps3recomp\libs\spurs\cellSpurs.c`, `cellSpurs.h`, `runtime/spu/*`, `tests/test_spurs_jobchain_end_resume.c`, `tools/test_spurs_jobchain_end_resume.py` | Modified / Added lokal | Penyesuaian runtime SPURS/SPU serta penambahan test regresi lokal (`test_spurs_jobchain_end_resume`). |
| SPURS / Lifted Job2 Pipeline | `08_SCRIPTS\lift_spurs_jobs.py`, `08_SCRIPTS\relift.ps1`, `03_ASURASWRATH_PORT\spu\jobmods_register.c`, `03_ASURASWRATH_PORT\spu\spujob_*` | Fixed lokal (port) | Perbaikan permanen black screen / stall setelah logo UE3 & SpeedTree (`20_UE3LOGO.BIK` → `20_SPEEDTREELOGO.BIK` → `TITLEMENU_BG00.BIK`): ekstrak sementara, wrap (`base=0, entry=0x10`), lift, dan registrasi `__attribute__((constructor))` (`spu_workload_register_img`, `image_id 40..45`) untuk ke-6 embedded SPURS job2 binaries (`ShaderPatching`, `WriteFence`, `Job3`, `PhysX1`, `Fluid1`, `Fluid2`). |
| Input / `cellPad` (T1–T3 + Audit Fisik) | `02_REPOS\ps3recomp\libs\input\cellPad.c`, `07_DOCS\INPUT_MAPPING.md` | Fixed lokal & terverifikasi E2E manual (`Tier 2 = PASS`) | Mapping keyboard fallback R-stick (`I/J/K/L`) + `L3/R3` (`3/4`) sebelumnya; ditambah **T2** dokumentasi format `PAD_STICK="lx,ly,rx,ry[,from,until]"` dan validasi ketat `strtol`/`strtod` (tolak token invalid, sumbu `<0` / `>255`, `until <= from`, isolasi `port_no==0`), **T3** diagnostik runtime `PAD_DIAG` (`pad_diag_level`, `pad_diag_norm_127`, `pad_diag_fmt_btns`) di `cellPadGetData`, `cellPadGetInfo2`, dan `cellPadSetPortSetting`, serta **`[PAD_DIAG][PHYS]` / `[PAD_DIAG][BACKEND]` / `[PAD_DIAG][FOCUS]`** (`pad_diag_log_phys`, `cellPad.c:839-902`) saat tombol/stik fisik XInput atau Keyboard ditekan (`PRESS`/`CHANGE`/`HOLD`/`RELEASE`). Terbukti oleh unit test `05_LOGS\pad_t2_t3_unit_test.log` (`8/8` kasus), inject `05_LOGS\qte_ep1_inject_20261115_095639`, serta **uji manual user `05_LOGS\qte_ep1_manual_20261115_161352`** (`stderr.log` baris `2138-2201` mencatat `[PAD_DIAG][PHYS]` `L=(128,255)` + `R=(128,255)` via `Panah Bawah + K`, diikuti streaming `BC-S000_L01_PDE_02.XXX` dan screenshot gameplay lanjutan `qte_t070s.png`..`stage_08_ep1_end.png`; rangkuman di `05_LOGS\t1_tier2_pass_audit.txt`). Tabel pemetaan lengkap disimpan di `07_DOCS\INPUT_MAPPING.md`. |

## 2. Branch Lokal `asuras-wrath-local`, Verifikasi Runtime Lib, & Patch Series (`07_DOCS\patches\`)

### 2A. Verifikasi `ps3recomp_runtime.lib` yang Ter-link ke `AsurasWrathRecomp.exe` (Audit T2 — `05_LOGS\t2_runtime_lib_audit.txt`)
- **Konfigurasi CMake & Ninja**:
  - `03_ASURASWRATH_PORT\CMakeLists.txt:76-77` memanggil `add_subdirectory("${PS3RECOMP_DIR}" "${CMAKE_BINARY_DIR}/ps3recomp_sdk" EXCLUDE_FROM_ALL)` dengan `PS3RECOMP_DIR = C:/PORTINGAN GAME/PS3/Ashura W/02_REPOS/ps3recomp` (branch `asuras-wrath-local`, commit `adb8a2ec`).
  - `04_BUILD\build.ninja:968,972` me-link `LINK_LIBRARIES = ps3recomp_sdk\ps3recomp_runtime.lib ...` serta mengompilasi `ppu_loader.cpp`, `ppu_hle.cpp`, `ppu_fs.cpp`, `ppu_sysprx.cpp`, dan `spu_dispatch_mt.c` langsung dari `02_REPOS\ps3recomp\runtime\`.
- **Tabel Hash SHA-256, Ukuran, & Timestamp**:

| Artefak | Path | Ukuran (bytes) | Timestamp | SHA-256 | Status Link |
|---|---|---|---|---|---|
| Runtime Lib (sumber lokal `asuras-wrath-local`) | `04_BUILD\ps3recomp_sdk\ps3recomp_runtime.lib` | `4,893,364` | `2026-11-15 14:34:54` | `AC0709149C1D0FE6359FA4106D5671EB57096F8F3639D510FDE1D47E5E56EEE0` | **AKTIF / TER-LINK** |
| Executable Port | `04_BUILD\AsurasWrathRecomp.exe` | `423,289,856` | `2026-11-15 14:35:02` | `CE722A0BC0AC86AF57A2D72CED07C4484A20A40EF2C2FCD2B71E00C09A5A0DD2` | **AKTIF** |
| Prebuilt Release Bundle (`v0.19.0`) | `02_REPOS\ps3recomp-v0.19.0-win-x64\lib\ps3recomp_runtime.lib` | `4,723,150` | `2026-11-06 17:42:29` | `817F90D24C4EAE73B2735152659905975C427FBBF8EAEF1264F7AA41AE44C9D3` | **TIDAK DIPAKAI** (diabaikan oleh `CMakeLists.txt`) |

- `08_SCRIPTS\env_ps3_laptop.ps1` telah diperbarui agar menimpa dan mencetak `$env:PS3RECOMP_RUNTIME_LIB = "$env:PORT_ROOT\04_BUILD\ps3recomp_sdk\ps3recomp_runtime.lib"` sehingga sesi PowerShell tidak lagi menampilkan variabel lama dari bundle `v0.19.0`.

### 2B. Patch Series (`07_DOCS\patches\`)

Seluruh `36` file termodifikasi + `3` file test baru di `02_REPOS\ps3recomp` telah di-commit secara terpisah per perubahan logis pada branch lokal `asuras-wrath-local` di atas base commit `de4f090328ea08bef6b2f15caec0b85e343a7ece` (`de4f0903`, `git -C 02_REPOS\ps3recomp status --short` kini bersih) dan diekspor ke `07_DOCS\patches\`:

| Patch File (`07_DOCS\patches\`) | Commit (`asuras-wrath-local`) | Cakupan Logis |
|---|---|---|
| `0001-rsx_vertex_fetch-return-early-after-decoding-CMP-typ.patch` (juga di `07_DOCS\upstream\0001-rsx_vertex_fetch-return-early-for-CMP-attributes.patch`) | `3a887069` | Perbaikan `CMP` (`type == 6`) early `return;` di `libs/video/rsx_vertex_fetch.c` + unit test `libs/video/tests/test_vertex_fetch_cmp.c` + registrasi `CMakeLists.txt`. |
| `0002-tools-portable_msvc-fallback-SPU-extra_funcs-fix-and.patch` | `7c022238` | `tools/msvc_env.py`, `tools/build_spu_workloads.py`, `tools/nid_database.py`, `tools/ppu_lifter.py`, `tools/test_ppu_jumptables.py`, `scratch/ppu_conformance*`. |
| `0003-runtime-PPU-loader-fs-LV2-syscalls-and-HLE-module-ad.patch` | `0a15f541` | `runtime/ppu/ppu_{fs,loader}.cpp`, `runtime/syscalls/{lv2_register,sys_event,sys_memory,sys_timer}.{c,h}`, `libs/misc/cellOvis.{c,h}`, `libs/network/{cellNetCtl,sceNpTrophy}.{c,h}`. |
| `0004-spurs-spu-jobchain-resume-strict-miss-fatal-and-SPU-.patch` | `4e7b38a6` | `libs/spurs/cellSpurs.{c,h}`, `runtime/spu/spu_{channels,context,dma,interp,lifted_job,workload}.{c,h}`, `tests/test_spurs_jobchain_end_resume.c`, `tools/test_spurs_jobchain_end_resume.py`. |
| `0005-cellPad-PAD_STICK-validation-PAD_DIAG-telemetry-and-.patch` | `3d94aabb` | `libs/input/cellPad.c`, `libs/input/tests/test_pad_keyboard.c`. |
| `0006-video-rsx-NV0039-subch1-routing-D3D12-shader-disk-ca.patch` | `d78a0f7c` | `libs/video/cellGcmSys.c`, `libs/video/rsx_d3d12_backend.c`, `libs/video/rsx_d3d12_device.h`, `libs/video/rsx_fp_decompiler.c`, `libs/video/rsx_live_draw.c`. |
| `0007-cellPad-add-PAD_DIAG-physical-button-stick-focus-log.patch` | `adb8a2ec` | `libs/input/cellPad.c`: log `[PAD_DIAG][PHYS]` (`PRESS`/`CHANGE`/`HOLD`/`RELEASE`), `[PAD_DIAG][BACKEND]`, `[PAD_DIAG][FOCUS]`, dan pembedaan `src=xinput` vs `src=kbd` tanpa mengubah perilaku input. |

### Daftar File per Area (terhadap base `de4f0903`):
- **Input**:
  - `M libs/input/cellPad.c`
  - `M libs/input/tests/test_pad_keyboard.c`
- **Misc & Network / Trophy**:
  - `M libs/misc/cellOvis.c`
  - `M libs/misc/cellOvis.h`
  - `M libs/network/cellNetCtl.c`
  - `M libs/network/sceNpTrophy.c`
  - `M libs/network/sceNpTrophy.h`
- **SPURS**:
  - `M libs/spurs/cellSpurs.c`
  - `M libs/spurs/cellSpurs.h`
- **Video / RSX**:
  - `M CMakeLists.txt`
  - `M libs/video/cellGcmSys.c`
  - `M libs/video/rsx_d3d12_backend.c`
  - `M libs/video/rsx_d3d12_device.h`
  - `M libs/video/rsx_fp_decompiler.c`
  - `M libs/video/rsx_live_draw.c`
  - `M libs/video/rsx_vertex_fetch.c`
  - `A libs/video/tests/test_vertex_fetch_cmp.c`
- **Runtime PPU**:
  - `M runtime/ppu/ppu_fs.cpp`
  - `M runtime/ppu/ppu_loader.cpp`
- **Runtime SPU**:
  - `M runtime/spu/spu_channels.c`
  - `M runtime/spu/spu_context.h`
  - `M runtime/spu/spu_dma.h`
  - `M runtime/spu/spu_interp.c`
  - `M runtime/spu/spu_lifted_job.h`
  - `M runtime/spu/spu_workload.c`
  - `M runtime/spu/spu_workload.h`
- **Syscalls LV2**:
  - `M runtime/syscalls/lv2_register.c`
  - `M runtime/syscalls/sys_event.c`
  - `M runtime/syscalls/sys_memory.c`
  - `M runtime/syscalls/sys_memory.h`
  - `M runtime/syscalls/sys_timer.c`
- **Scratch & Tools**:
  - `M scratch/ppu_conformance.cpp`
  - `M scratch/ppu_conformance_run.bat`
  - `M tools/build_spu_workloads.py`
  - `M tools/msvc_env.py`
  - `M tools/nid_database.py`
  - `M tools/ppu_lifter.py`
  - `M tools/test_ppu_jumptables.py`
- **Regression Tests Baru**:
  - `A tests/test_spurs_jobchain_end_resume.c`
  - `A tools/test_spurs_jobchain_end_resume.py`

## 3. Pipeline Skrip Port Lokal (`08_SCRIPTS`)

- `08_SCRIPTS\env_ps3_laptop.ps1`: Pengaturan environment port lokal Windows (`clang-cl` + Ninja).
- `08_SCRIPTS\lift_spurs_jobs.py`: Ekstraksi sementara ke-6 embedded SPURS job2 binaries langsung dari `EBOOT.ELF` (tanpa meninggalkan `.bin`/`.elf` di folder port), lift ke `03_ASURASWRATH_PORT\spu\spujob_<FP>\`, backup otomatis `jobmods_register.c` ke `jobmods_register.c.bak` sebelum menimpa (bila berbeda atau `.bak` belum ada), serta pembangkitan deterministik (line-ending LF) `03_ASURASWRATH_PORT\spu\jobmods_register.c`.
- `08_SCRIPTS\relift.ps1`: Pipeline relift penuh; terverifikasi ulang 2x deterministik pada `TC-08` (`251` file keluaran identik `Hash Mismatches: 0`, `207.04s` & `204.48s`, exit `0`; bukti `05_LOGS\relift_tc08_verify.txt`).
- `08_SCRIPTS\build.py`: Build CMake/Ninja menggunakan environment MSVC/Clang lokal (`exit 0`, `340.61s` pasca-relift `TC-08`; build ulang pasca-fix `rsx_vertex_fetch.c` menghasilkan `04_BUILD\AsurasWrathRecomp.exe` `423287296` bytes, `sha256: aea6235e8936f3ca4f7e034e500b9b9ddc99a4cb24738361239f39c9b8014d76`).
- `08_SCRIPTS\run_ps3.ps1`: Runner dengan validasi path ELF (`TC-01` exit `1` saat ELF tidak ada) dan mounting `VFS_ROOT` ke `00_GAME_DUMP\extracted`.
- `08_SCRIPTS\test_e2e_ep1_play.ps1`: Runner uji E2E terotomatisasi (`-Mode tier2|tc05`, default `SPU_MISS_FATAL=1`) dengan timeout per tahap, `stages.log` per tahap, screenshot PNG tiap tahap (`stage_01`..`stage_09`, dialog `"Start the game on EASY? Yes/No"` dengan retry `UP` -> `Yes` -> `CROSS`), injeksi `cellPad` + `PAD_STICK` untuk combat & QTE, perekaman `ep1_recording.mp4` via `ffmpeg`, dan ringkasan `audit_summary.txt`.
- `08_SCRIPTS\test_qte_ep1.ps1`: Harness diagnostik QTE Episode 1 (`-Mode inject` & `-Mode manual`, `SPU_MISS_FATAL=1`, `PAD_DIAG=1`, capture `qte_t010s..t130s.png`, audit `[PAD_DIAG]` & `[cellPad] PAD_STICK`). Terverifikasi bersih di `-Mode inject -Ep1Sec 130` (`05_LOGS\qte_ep1_inject_20261115_095639`, `ExitCode=0`, `[void]$p.Handle` sinkronisasi `ExitCode` PS 5.1).

## 4. Sumber Bedah Repo & Lisensi (Aturan 2)

Seluruh temuan bedah repo T1 didokumentasikan secara rinci di `07_DOCS\T1_CELLPAD_QTE_AUDIT.md`. Tidak ada kode berlisensi GPL (mis. RPCS3) yang disalin ke workspace.

| Sumber | URL / Path | Commit / Bagian yang Diperiksa | Lisensi |
|---|---|---|---|
| `ps3recomp` (hulu) | `https://github.com/sp00nznet/ps3recomp.git` (`02_REPOS\ps3recomp`) | HEAD `de4f0903`; PR #42 adaptasi `a0a050ce` & `9e4e302a` (refleksi Y `256 - x` & split `DIGITAL2`), `803d0b9b` (PR #496 center stick), `c59814b6` (`PAD_CLOCK=flips`), `74e8bb02` / `6eb26c1e` (PR #570 `PAD_FILE` across drain), `8933ff90` (PR #581 empty XInput backoff), `24c702ae` (kbd fallback); PR #529 `36b1ea43` (`CMP` 11-11-10 decode) + PR #597 `b3150f3c` (ekspansi skalar `w=1.0f` yang menimpa `Y/Z` `T6x1`); `docs\RSX_GRAPHICS.md:264-280`, `libs\video\rsx_d3d12_backend.c:6405-6422,7528-7557,8155-8223,8814-8828` (konversi `QUADS -> TRIANGLES` & `upload_quads_vp`), `libs\input\cellPad.{c,h}`, `libs\video\rsx_vertex_fetch.{c,h}`, `rsx_vertex_formats.h`, `rsx_live_draw.c:5744`, `rsx_vertex_compact.c:84`, `docs\GAME_PORTING_GUIDE.md:504-522`, `docs\DIAGNOSTICS.md:501-517`, `docs\MODULE_STATUS.md:36-42`, `docs\MODULES_REFERENCE.md:215-270` | MIT (`Copyright (c) 2026 Ned Heller / sp00nznet`) |
| `crazytaxi-ps3` | `https://github.com/sp00nznet/crazytaxi-ps3.git` (`02_REPOS\crazytaxi-ps3`) | HEAD `94c5a3d`; `README.md:87`, `CHANGELOG.md`, `docs\progress.md` (`PAD_SCRIPT` & mask tombol) | MIT |
| `twistedmetal` | `https://github.com/sp00nznet/twistedmetal.git` (`02_REPOS\twistedmetal`) | HEAD `23afb43`; `src\gen\ppu_hle_nids.cpp:485-497,1604-1616` (`sys_io` NIDs), `README.md`, `docs\in-match.md`, `docs\ps3recomp-fixes.patch` | MIT (`02_REPOS\twistedmetal\LICENSE`) |
| Port sister lain (`flow`, `midway-ps3`, `simpsonsarcade-ps3`) | — | Tidak tersedia lokal di `02_REPOS` | — |
| Dump/recomp lokal game target | `03_ASURASWRATH_PORT\meta\EBOOT.imports.json`, `03_ASURASWRATH_PORT\recompiled\ppu_recomp_013.cpp:45561-46090`, `00_GAME_DUMP\...\EBOOT.ELF` (`0x008A1E78..0x008A1E8F`) | 14 NID `sys_io` (`cellPad*`, `cellKb*`, `cellMouse*`), konstanta `0.2f` & `1/127`, `func_008A1AF0`/`func_008A1E90` (negasi `LY` baris `45707`) | Hanya artefak inspeksi lokal milik pengguna (tidak disalin/disebarkan) |
