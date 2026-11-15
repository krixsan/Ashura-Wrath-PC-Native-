# KNOWN ISSUES - Asura's Wrath (PS3 Recomp)

Daftar hal yang belum diuji penuh, log non-fatal yang diketahui aman, serta batasan cakupan uji pada build Windows laptop saat ini (`04_BUILD\AsurasWrathRecomp.exe`).

## 1. Test Case PRD yang Belum Dijalankan Penuh / Temuan Terbuka

1. **`TC-06` (Soak test 30 menit gameplay kontinu)**
   - **Status**: Belum dijalankan selama 30 menit penuh (`1800s`).
   - **Bukti terkini**: Sesi E2E Tier 2 penuh (`05_LOGS\e2e_tier2_20261115_061452`) dengan `SPU_MISS_FATAL=1` berjalan selama **`330.11s`** (`660` frame, rekaman `ep1_recording.mp4` `62.71 MB`) hingga Episode 1 orbital combat & atmospheric re-entry (`draw_arrays #314000`, zero `dispatch MISS`, zero `jump-park`, zero `FatalOrAbort`, `[WATCHDOG MEM]` stabil pada `objs=103051`). Menunggu keputusan untuk menjalankan soak `1800s` + pencatatan profil memori berkala.
2. **`TC-07` (Perbandingan frame vs golden RPCS3 `BLUS30721`)**
   - **Status**: Belum lengkap (golden frame & jumlah draw/pass RPCS3 `BLUS30721` pada momen yang sama belum tersedia di mesin lokal; RPCS3 tidak ditemukan).
   - **Bukti terkini**: Tabel perbandingan manual disiapkan di `07_DOCS\TC07_RPCS3_COMPARISON.md` beserta tangkapan lokal (`1280x720`) dari `05_LOGS\e2e_tier2_20261115_061452\`, `05_LOGS\e2e_tc05_20261115_062608\`, serta sensus draw sebelum/sesudah perbaikan `CMP` pada `05_LOGS\draw_census_20261115_110049\` dan `05_LOGS\draw_census_20261115_111217\`. Audit shader `05_LOGS\t025s_particle_quads_audit.txt` membuktikan 21 draw ber-`pos0=(0,0,0)` (`i=0/6/30/36/288`) pada `t025s` adalah normal (20 draw `QUADS` partikel local-space `bUseLocalSpace=TRUE` + 1 draw UI `TRIS`). Yang masih memerlukan golden RPCS3 `BLUS30721` (`Aturan 7`): memastikan apakah pada momen orbit combat (`t025s`, `t040s`) maupun re-entry (`t070s`) keberadaan/posisi Asura dan kapal sesuai dengan frame RPCS3. Catatan visual minor lokal sebelumnya: pada `05_LOGS\e2e_tc05_20261115_062608\stage_02_load_dialog.png` tampak artefak blend putih minor di tepi bawah belakang dialog overlay `Load successful.`.
3. **Progres QTE `L↓ + R↓` pada Atmospheric Re-entry Episode 1 (Baru)**
   - **Gejala**: Pada `05_LOGS\e2e_tier2_20261115_061452`, dari `ep1_t070s.png` hingga `ep1_t310s.png` / `stage_09_ep1_end.png` (~260 detik sisa durasi Episode 1), QTE prompt `(L)↓ (R)↓` tetap bertahan dan belum berlanjut meski script mengirim `PAD_STICK="128,255,128,255,190,260"`. Rendering, animasi efek api, audio, dan watchdog (`draw_arrays #314000`) tetap berjalan tanpa freeze atau crash.
   - **Dampak / Tindak lanjut**: Menunggu uji manual dengan gamepad fisik (`08_SCRIPTS\test_qte_ep1.ps1 -Mode manual`, `Aturan 7`) untuk membedakan isu timing/sekuens injeksi vs pembacaan `cellPad` di game.
4. **Update v1.02 PKG & Struktur Git Root (`TC-09`)**
   - **Update v1.02**: Berkas `00_GAME_DUMP\extracted\Asura's Wrath [BLUS30721] (Update v1.02).pkg` (`34731232` bytes, `UP0102-BLUS30721_00-PATCH02000000000`) belum diekstrak/di-merge; `EBOOT.ELF` yang di-lift saat ini adalah Base `APP_VER=01.00` (field mastering `VERSION=01.02`). `00_GAME_DUMP\extracted\game\BLUS30721\` hanya berisi berkas `.TFC` + `ICON0.PNG` (tanpa `PARAM.SFO`/`EBOOT`).
   - **Git Root (`TC-09` — Teratasi 2026-11-15)**: Workspace root `"C:\PORTINGAN GAME\PS3\Ashura W\"` kini telah diinisialisasi (`git init`) dengan `.gitignore` ketat, commit bertahap, serta tag `tier1` dan `tier2-partial` (`05_LOGS\tc09_git_root_verify.txt`). Riwayat sebelumnya: ~~Workspace root `C:\PORTINGAN GAME\PS3\Ashura W\` belum diinisialisasi sebagai repositori Git (`Root workspace .git exists: False`; `.git` hanya ada di `02_REPOS\ps3recomp`), sehingga git tag `tier1` dan `tier2` di root belum dibuat.~~

## 2. Log & Catatan Non-Fatal

1. **Data non-instruksi `.word` pada `spujob_42E1FC8CEE0BE246` (`ShaderPatching`)**:
   - Laporan `spu_lifter.py` mencatat `25` `.word` pada tabel konstan embedded di tail blob biner mentah; ke-6 SPURS job2 (`ShaderPatching`, `WriteFence`, `Job3`, `PhysX1`, `Fluid1`, `Fluid2`) bebas instruksi SPU tak didukung (`real_unsup == {}`).
2. **File firmware eksternal opsional tidak ditemukan**:
   - Log: `[fs] open FAIL '/dev_flash/sys/external/flashMP3.pic'`
   - Dampak: Muncul sekali saat startup; pemutaran video Bink dan audio game tetap berjalan normal.
3. **Status jaringan offline (`cellNetCtl`)**:
   - Log: `[cellNetCtl] GetState() -> error NOT_INITIALIZED (offline mode)`
   - Dampak: Log berulang secara berkala karena mode offline/non-PSN disengaja; tidak memengaruhi alur menu, save/load, maupun gameplay Episode 1.
4. **Pengakhiran proses saat `WM_CLOSE`**:
   - Log: `[quit] the game did not exit on its own; ending it (save in flight: no, waited 0 ms) -> exit 0`
   - Dampak: Saat penutupan window setelah `REQUEST_EXITGAME` dikirim ke `2` sysutil callback, watchdog quit menutup proses secara bersih dengan exit code `0` ketika tidak ada operasi save yang sedang berjalan.

## 3. Catatan Unit Test `02_REPOS\ps3recomp` di Windows

1. **`libs\input\tests\test_pad_keyboard.c` tidak masuk cakupan Windows**:
   - Test tersebut bergantung pada header POSIX (`<unistd.h>`, `<sys/mman.h>`) dan flag `-DPS3RECOMP_PAD_KEYBOARD_SDL`, sehingga tidak dijalankan pada build uji Windows.
2. **`test_d3d12_device_pick.c` memerlukan forced-include header Windows**:
   - Saat dijalankan di luar target CMake default dengan `clang-cl`, kompilasi manual memerlukan `/FIwindows.h /FId3d12.h /FIdxgi1_4.h` dan linking ke `d3d12.lib dxgi.lib` (`31 passed, 0 failed`, `rc: 0`).
3. **Suite CTest Windows (`-DPS3RECOMP_BUILD_TESTS=ON`)**:
   - `30/30` test lolos (`100% tests passed out of 30`, durasi `34.65 sec`).

## 4. Lingkungan & Cache Lokal

- **Shader disk cache (`04_BUILD\shader_cache\rsx_shader_cache_v2`)**: Boot pertama scene baru mengkompilasi pixel shader tambahan ke disk cache tanpa error (`hits{vs=64 ps=100} misses{vs=0 ps=99} writes{vs=0 ps=99} rejects=0`), dan boot ulang memakai cache (`hits{vs=13 ps=16} misses{vs=0 ps=0} writes{vs=0 ps=0} rejects=0`).
- **Save data lokal**: Tersimpan di `04_BUILD\gamedata\dev_hdd0\home\00000001\savedata\BLUS30721-BCSAVEDATA\` (`ICON0.PNG`, `PARAM.PFD`, `PARAM.SFO`, `PAYLOAD`).
- **Patch lokal `ps3recomp`**: Seluruh perubahan `ps3recomp` (`36` file dimodifikasi + `3` file test baru di atas base `de4f090328ea08bef6b2f15caec0b85e343a7ece`) kini di-commit secara terpisah per perubahan logis di branch `asuras-wrath-local` (`3a887069..d78a0f7c`, `git status --short` bersih) dan diekspor ke `07_DOCS\patches\0001-*.patch` s.d. `0006-*.patch`. Riwayat sebelumnya: ~~Seluruh perubahan `ps3recomp` masih berstatus uncommitted lokal di `02_REPOS\ps3recomp` (`36` file dimodifikasi + `2` test untracked), dan bersih dari kunci/dump game.~~
- **Ekstrak SPU ELF lokal (`TC-09`)**: Direktori `03_ASURASWRATH_PORT\meta\spu\` berisi `27` file `spu_0000_at_*.elf` s.d. `spu_0026_at_*.elf` yang dihasilkan oleh `08_SCRIPTS\relift.ps1` dari `EBOOT.ELF`; berkas tersebut kini diabaikan secara eksplisit oleh `.gitignore` di root workspace (`03_ASURASWRATH_PORT/meta/` & `*.elf`), terbukti tidak masuk `git status` / `git ls-files` (`05_LOGS\tc09_git_root_verify.txt`).

## 5. Temuan yang Sudah Diperbaiki (Sensus Draw Episode 1 — `CMP` `T6x1`)

- **Akar masalah**: Di `02_REPOS\ps3recomp\libs\video\rsx_vertex_fetch.c` (`rsx_fetch_attrib`), `case 6:` (`CELL_GCM_VERTEX_CMP`, 11-11-10) selesai mendekode `out[0..2]` + `out[3]=1.0f` lalu jatuh lewat `break;` ke blok ekspansi skalar `if (n < 3) out[2] = 0.0f; if (n < 2) out[1] = 0.0f;` (baris 138–140). Karena UE3 mendeklarasikan `CMP` dengan `size=1` (`a0:T6x1s32@L` / `a0:T6x1s24@L`), seluruh vertex aktor/karakter skeletal kehilangan sumbu `Y` & `Z` (`pos0=X;0.000;0.000;1.000`) dan kolaps menjadi pita/duri pipih.
- **Perbaikan & Bukti**: Early `return;` ditambahkan di `case 6:` (`rsx_vertex_fetch.c:113-116`) + unit test `02_REPOS\ps3recomp\libs\video\tests\test_vertex_fetch_cmp.c` (`05_LOGS\test_vertex_fetch_cmp.log`, `0 failure(s)`). Pada sensus `SPU_MISS_FATAL=1` dengan `RSX_DROP_LOG=1` & `RSX_SPU_AUDIT=1`:
  - Sebelum (`05_LOGS\draw_census_20261115_110049`): `dropped=0, skip_rf=0`, `T6x_a0_zero=2/3` (`t010s`) dan `25/43` (`t070s`), objek QTE di `qte_t070s.png` & `qte_t085s.png` kolaps menjadi pita berduri.
  - Sesudah (`05_LOGS\draw_census_20261115_111217`): `ExitCode=0`, `DispatchMiss=0`, `FatalOrAbort=0`, `dropped=0, skip_rf=0`, `T6x_a0_zero=0/3` (`t010s`) dan `0/86` (`t070s`), seluruh koordinat Y/Z `T6x1` terisi normal, dan model 3D ber-tentakel/sayap tampil utuh di `qte_t070s.png`, `qte_t085s.png`, serta `stage_08_ep1_end.png`.
  - **Performa (`FRAME_BUDGET=1`, `05_LOGS\perf_cmp_before_after.txt`)**: Guest render FPS pada rentang `t010s..t070s` naik dari `31.04 FPS (32.22 ms/frame)` menjadi `35.43 FPS (28.23 ms/frame)` (`+4.39 FPS` / `-3.99 ms`); RSX flip rate naik dari `49.20 flip/s (20.33 ms)` menjadi `52.71 flip/s (18.97 ms)`; `0` frame terpotong budget (`MAX_VERTICES=786432`, `MAX_DRAWS=2048`, `VP_MAX_INDICES=2097152`).
  - **Audit SPU**: Seluruh SPU worker taskset aktif (`14..16,18,22,23`) & SPURS job2 (`40` `ShaderPatching` / `41` `WriteFence`) selesai bersih (`dispatch == done == halt`, `now=0`); `0` `rsx_hits` maupun `inflight_hits` pada vertex/index buffer (`T6x1` di VRAM `0xCE...`, `T2x3` di Main `0x40...`), sedangkan `img 40` menulis `[0x01A96900..0xC0100000)` untuk shader patch.

## 6. Audit 21 Draw `pos0=(0,0,0)` (`i=0/6/30/36/288`) pada `t025s` (Bukan Bug — Perilaku Normal UE3)

- **Bukti lengkap**: `05_LOGS\t025s_particle_quads_audit.txt`.
- **Rincian 21 draw (`a0_zero > 0`) dari 242 draw pada `t025s`**:
  - `10` draw `QUADS` (`ix=0`) dengan `vs=40` (`vp_hash=0xA82D03FA`, 162 instrs, `04_BUILD\shader_cache\rsx_shader_cache_v2\V_48BCB76EE0B0750F_00004E36.bin`), `vtx=a0:T2x3s80@M|a1:T2x1s80@M|a2:T2x3s80@M|a5:T2x3s80@M|a8:T2x2s80@M|a9:T2x4s80@M|a11:T2x4s80@M` (`FParticleSpriteSubUVVertex`), ID `137, 141, 156, 160, 164, 168, 172, 176, 180, 184`.
  - `10` draw `QUADS` (`ix=0`) dengan `vs=31` (`vp_hash=0x5E4D2063`, 161 instrs, `04_BUILD\shader_cache\rsx_shader_cache_v2\V_D4604C5C7BE0550C_00004DE9.bin`), `vtx=a0:T2x3s64@M|a1:T2x1s64@M|a2:T2x3s64@M|a5:T2x3s64@M|a8:T2x2s64@M|a9:T2x4s64@M` (`FParticleSpriteVertex`), ID `138, 142, 157, 161, 165, 169, 173, 177, 181, 185`.
  - `1` draw `TRIS` (`ix=1`, `id=241`) dengan `vs=11` (`vp_hash=0x8ED1F534`), quad UI 2D yang sudut kiri-atasnya berada di `(0,0,0,0.1)`.
- **Mengapa `pos0=(0,0,0)` normal pada ke-20 draw `QUADS` partikel**:
  - Decompiled HLSL `vs=40` dan `vs=31` membuktikan `v[0]` (`ATTR0`, `Position`) ditransformasi oleh matriks `LocalToWorld` di `vp_c[200..203]`: `r[0] = v[0].x*vp_c[200] + v[0].y*vp_c[201] + v[0].z*vp_c[202] + v[0].w*vp_c[203]`. Untuk emitter UE3 dengan `bUseLocalSpace=TRUE` yang berpusat di origin lokal emitter `(0,0,0)`, `v[0]=(0,0,0,1)` menghasilkan `r[0] = vp_c[203]` (posisi dunia emitter).
  - Ke-4 sudut quad diekspansi di dalam Vertex Shader dari `ATTR8` (`v[8].yx - vp_c[452].xx`, offset sudut `[-0.5, +0.5]`), dikalikan `ATTR5` (`v[5].xy`, ukuran partikel 2D non-nol seperti `(37.5, 37.5)` atau `(80, 80)`), dirotasi oleh `sin/cos(v[1].x)` (`ATTR1`) sepanjang sumbu kamera `vp_c[464]` (`CameraRight`) & `vp_c[465]` (`CameraUp`), ditambahkan ke `r[0]`, lalu diproyeksikan oleh `vp_c[0..3]` (`ViewProjection`).
- **Mengapa `i=0/6/30/36/288` muncul pada kolom `fi` CSV untuk draw `ix=0`**:
  - Seluruh 83 draw `QUADS` di `t025s` adalah non-indexed (`ix=0`, `d3d12_draw_arrays` -> `upload_quads_vp` -> `DrawInstanced(dr->vertex_count, 1, ...)`). Di `rsx_d3d12_backend.c:8165`, `d3d12_draw_arrays` menyetel `dr->indexed = 0` tanpa men-zero-kan `dr->index_count`, sehingga kolom CSV `fi` (`e->final_indices`) menyalin nilai `dr->index_count` sisa frame sebelumnya pada slot tersebut (`0, 6, 30, 36, 288`). Eksekusi GPU D3D12 tidak terpengaruh karena cabang `if (dr->indexed)` tidak diambil ketika `dr->indexed == 0`. Tidak ada kode yang diubah.


