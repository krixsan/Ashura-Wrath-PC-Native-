# PRD: Asura's Wrath — PS3 NativeRecomp (Laptop)

**Metode**: Static Recompilation (PPU/SPU → C++) berbasis `ps3recomp`
**Versi**: 1.2-Laptop (berbasis template PS3 v2.1)
**Tanggal**: 2026-11-15
**Lokasi simpan**: `%PORT_ROOT%\07_DOCS\_PRD_PS3_AsurasWrath_v1.2_Laptop.md` (di-rename dari `_v1.1_` pada 2026-11-15; sebelumnya `_v1.0_`)

> **Cara pakai**: isi semua `[PLACEHOLDER]`, kerjakan **M0 Gate (Go/No-Go)** dulu, baru lift.
> **Legenda**: ✅ terbukti di repo/port orang lain · 🧪 estimasi, belum diukur · ⚠️ belum terverifikasi, cek sendiri.
> **Sumber bedah repo** (dibaca 2026-11-13): README `sp00nznet/ps3recomp` + README port sister (`flow`, `crazytaxi-ps3`, `midway-ps3`, `simpsonsarcade-ps3`, `twistedmetal`). `docs/GAME_PORTING_GUIDE.md` **belum dibaca**, baca sebelum M1.

**Riwayat versi**: v1.2 (2026-11-15) = penutupan **Tier 2 = PASS** & **TC-04 = PASS** berdasarkan bukti input nyata QTE `"L-down + R-down"` (`05_LOGS\qte_ep1_manual_20261115_161352\stderr.log:2138-2201`, `qte_t070s.png`..`stage_08_ep1_end.png`, audit `05_LOGS\t1_tier2_pass_audit.txt`, tag git `tier2`), verifikasi SHA-256 `ps3recomp_runtime.lib` yang ter-link (`05_LOGS\t2_runtime_lib_audit.txt`), penambahan tabel **Definisi Selesai v1.2** (§7A.3.1) dan tabel **Status per Episode** (§7A.3.2), serta skrip uji multi-episode `08_SCRIPTS\test_episodes_batch.ps1`. v1.1-r2 (2026-11-15, tindak lanjut sensus draw & T6) = branch `asuras-wrath-local` (`3a887069..d78a0f7c` di atas `de4f0903`) + patch series `07_DOCS\patches\0001..0006`, draf PR hulu `07_DOCS\upstream\PR_DRAFT_rsx_vertex_fetch_cmp.md` + `test_vertex_fetch_cmp.c`, audit partikel `QUADS` `t025s` (`05_LOGS\t025s_particle_quads_audit.txt`), benchmark `FRAME_BUDGET=1` sebelum/sesudah fix `CMP` (`05_LOGS\perf_cmp_before_after.txt`), serta `git init` root + `.gitignore` ketat + tag `tier1` & `tier2-partial` + pembaruan `TC-09` (`05_LOGS\tc09_git_root_verify.txt`). v1.1-r1 (2026-11-15, koreksi) = status Tier 2 → PARSIAL, TC-04 → PARSIAL, TC-09 → BELUM DIUJI (lalu diperbarui setelah `git init` root), nama file disinkronkan ke `v1.1`, temuan sensus draw `CMP`/`T6x1` (lihat `KNOWN_ISSUES.md` §5). Teks status lama dipertahankan sebagai riwayat dengan tanda ~~coret~~. v1.1 (2026-11-15) = verifikasi `PARAM.SFO` (`BLUS30721`, `APP_VER=01.00`, `VERSION=01.02`, PKG v1.02 belum ter-merge), otomasi SPURS `relift.ps1` + backup `.bak` + bukti `TC-08` 2x hash identik, bukti Tier 2 `330.11s` (`ep1_recording.mp4`, `SPU_MISS_FATAL=1`), bukti `TC-05` post-save auto-load (`EPISODE MENU` terbuka), tabel perbandingan manual `TC-07`, audit risiko `A-08`, serta pembaruan bukti seluruh `TC-01..TC-09`. v1.0 = draf awal (salah diberi label 5.1). v2.1 = v2.0 + REA + alur Ghidra headless (10.4). v2.0 = dibetulkan sesuai repo asli: nama script, tanpa Vulkan SDK di Windows, toolchain, dekripsi, timeline, bagian lengkap seperti PRD PS4.

---

## 0. Setup Mesin Ini — Laptop

| Item | Nilai |
|---|---|
| Mesin | Laptop hybrid (NVIDIA RTX 3050 Laptop + AMD Radeon iGPU) |
| Env | `08_SCRIPTS\env_ps3_laptop.ps1` (isi di bawah) |
| Perintah tiap sesi | `. .\08_SCRIPTS\env_ps3_laptop.ps1` |
| Drive | Hanya `C:` |
| Toolchain | Visual Studio 2022 Build Tools + clang-cl, CMake, Ninja, Python 3.10+ (belum dicek terpasang) |
| Vulkan SDK | **Tidak perlu**; `VULKAN_SDK` kosong di laptop **bukan masalah** untuk PS3 |

```powershell
# env_ps3_laptop.ps1
$env:PORT_ROOT           = Split-Path -Parent $PSScriptRoot
$env:PS3RECOMP_DIR       = "C:/recomp/ps3"                        # clone ps3recomp (kunci tag)
$env:PS3RECOMP_RUNTIME_LIB = "C:/recomp/ps3/build-gate/ps3recomp_runtime.lib"
Write-Host "PORT_ROOT=$env:PORT_ROOT"
Write-Host "ps3recomp : $(Test-Path $env:PS3RECOMP_DIR)"
Write-Host "runtime   : $(Test-Path $env:PS3RECOMP_RUNTIME_LIB)"
```
**GPU**: `vulkaninfo` menunjukkan RTX 3050 Laptop (discrete) + AMD Radeon (integrated). Untuk D3D12, paksa game ke NVIDIA: *Settings → System → Display → Graphics → tambah exe → High performance*. Matikan OBS/overlay saat debug window.

**Catatan laptop**:
- Source hasil lift besar (flOw 190 MB) + dump + build di satu drive C: → pantau ruang kosong, taruh dump di folder terpisah.
- RAM terbatas → build `-j 2` jika memori habis; colok charger.
- VRAM RTX 3050 Laptop terbatas; mulai 720p/1080p.
- **Peran laptop**: tes, edit, baca log, dokumen. Lift dan build berat lebih nyaman di PC.
- Spesifikasi laptop: CPU `AMD Ryzen 7 5800HS with Radeon Graphics`, RAM `15.4 GB`, ruang kosong C: `95.5 GB / 453.5 GB`.
⚠️ Isi umum PRD ini sama dengan versi PC; perubahan di bagian umum disalin ke kedua file.

---

## 1. Metadata Dokumen

| Field | Value |
|---|---|
| Nama Proyek | AsurasWrath-PS3Port |
| Game Target | Asura's Wrath |
| Region / Title ID | US — `BLUS30721` (konfirmasi `PARAM.SFO` & `PS3_DISC.SFB`: `TITLE="ASURA'S WRATH"`, `TITLE_ID="BLUS30721"`, `PS3_SYSTEM_VER="03.7300"`) |
| Versi game (aktif / update) | Base `APP_VER=01.00` (`PARAM.SFO VERSION=01.02`; `Asura's Wrath [BLUS30721] (Update v1.02).pkg` / `UP0102-BLUS30721_00-PATCH02000000000` belum diekstrak/merge) |
| Rilis asli / Genre | 2012 / Aksi + QTE |
| Publisher / Engine | Capcom (dev: CyberConnect2) / Unreal Engine 3 |
| Ukuran dump | 12 GB (ISO) / 27.1 MB (Decrypted ELF) |
| Metode | Static recompilation PPU+SPU → C/C++ |
| Base toolkit | `ps3recomp` (github.com/sp00nznet/ps3recomp), lisensi MIT ✅ |
| Versi ps3recomp (WAJIB dikunci) | commit: `de4f09038d17983ea4e17cb137834468f76d910a` |
| Port sister dipakai sbg kerangka | `twistedmetal` (decrypt/SPU/job queue) & `crazytaxi-ps3` |
| Renderer | D3D12 (Windows) |
| Platform | Windows 10/11 x86-64 |
| Status | Approved (M0 Gate: GO Bertahap) |

---

## 2. Executive Summary

PS3 memakai Cell: satu PPU PowerPC 64-bit dan beberapa SPU 128-bit. Beda dengan PS4 (x86-64, bisa dijalankan langsung), kode PS3 harus **diterjemahkan dulu**. `ps3recomp` menerjemahkan semua fungsi PowerPC dan program SPU menjadi C/C++, lalu di-link dengan runtime HLE yang menggantikan OS PS3, dan di-compile jadi `.exe` Windows.

**Kerja kita bukan menulis emulator.** Kerja kita: (1) jalankan pipeline lift untuk satu game, (2) perbaiki hasil lift dan runtime yang meleset untuk game itu, (3) kirim perbaikan umum balik ke upstream.

**Estimasi** 🧪 (belum diukur, game kecil, sudah ikut port sister):

| Capaian | Estimasi |
|---|---|
| Build pertama jalan (M0–M1) | 1–2 minggu |
| Frame pertama (M2–M3) | +1–3 minggu |
| Playable 1 stage | +2–6 minggu |
| Alpha stabil | 2–4 bulan |

Bukti skala: flOw menghasilkan 91.758 fungsi hasil lift (190 MB source) dan masih debug memory mapper serta dispatch. PS3 jauh lebih berat dari PS4.

---

## 3. Latar Belakang

### 3.1 PS3 vs PS4
| Aspek | PS4 (wrapper/HLE) | PS3 (static recomp) |
|---|---|---|
| CPU | x86-64, jalan langsung | PowerPC (PPU) + SPU, harus di-lift |
| Kode game | Dijalankan native | Diterjemahkan ke C/C++ lalu di-compile |
| OS | Syscall di-hook runtime | LV2 + ~300 syscall di runtime ps3recomp |
| GPU | GNM → Vulkan | RSX → D3D12 (backend jalan di Windows) |
| Sumber crash khas | HLE salah return value | Lift salah, dispatch indirect miss, memory map, SPU sync |
| Output | runtime + eboot | `[game].exe` berisi kode game hasil lift + runtime |
| Alat bantu utama | shadPS4 | RPCS3 (referensi perilaku, bukan sumber kode) |

### 3.2 Static recomp vs emulator
- Native, tanpa overhead terjemahan runtime, mudah di-mod (C/C++).
- Tiap game butuh kerja manual; tidak ada "jalan otomatis".
- README ps3recomp: RPCS3 menjalankan sekitar 70% pustaka lewat emulasi; recomp menawarkan performa native dan moddability.
- ⚠️ Jangan salin kode RPCS3 (GPL) ke tree. Pakai hanya sebagai referensi perilaku.

---

## 4. Goals & Non-Goals

### Goals (v0.1-alpha)
| ID | Goal | Ukuran |
|---|---|---|
| G-01 | Dump bersih + ELF terdekripsi | `EBOOT.ELF` valid |
| G-02 | Lift PPU | `.cpp` hasil lift + `functions.json` + `imports.json` |
| G-03 | Lift SPU (jika game pakai) | SPU image ter-extract + ter-lift |
| G-04 | Build | `[game].exe` terbentuk |
| G-05 | Boot | Melewati logo, tidak abort di konstruktor/main |
| G-06 | Render | Frame pertama benar vs golden RPCS3 |
| G-07 | Playable 1 stage | Input + audio, tidak freeze |
| G-08 | Save/load | Save → quit → load berhasil |

### Non-Goals
| ID | Non-Goal | Alasan |
|---|---|---|
| NG-01 | Full game | Incremental |
| NG-02 | Online/multiplayer | Perlu server psnr, di luar scope awal |
| NG-03 | Linux/macOS | Hanya Windows yang menjalankan game dari tree ini saat ini. |
| NG-04 | Distribusi game/kunci/firmware | Legal |
| NG-05 | Menggantikan RPCS3 | Beda tujuan |

---

## 5. Arsitektur & Pipeline

```
Dump game (disc/PKG) → EBOOT.BIN (terenkripsi)
        │  decrypt_self.py + file kunci (milik sendiri)
        ▼
EBOOT.ELF
        │  tools/ppu_loader.py   → functions.json, imports.json
        ▼
tools/ppu_lifter.py --functions --hle-stubs --output recompiled/
tools/gen_hle_nids.py            → ppu_hle_nids.cpp
(SPU) extract_spu_images.py → find_spu_functions.py → spu_lifter.py
        ▼
Build (template project + CMake + Ninja) link ke ps3recomp runtime
        ▼
[game].exe  (PPU boot scaffold + HLE dispatch dikompilasi PER GAME)
        ▼
RSX/cellGcm → D3D12 backend
```

Catatan penting dari README:
- `ppu_loader.cpp`, `boot_main.cpp`, dan HLE dispatch dikompilasi per game, bukan ke library.
- Opsi `--hle-stubs` wajib: tanpa itu, panggilan import pertama langsung crash.
- Hasil lift perlu **post-process** pada flOw (`tools/recompile.py`, `tools/post_lift.py`): rename, patch header, fallthrough, bctrl, malloc. Cek apakah game-mu butuh.
- Pemanggilan tidak langsung: flOw punya 20.030 situs bctrl yang dialihkan lewat hash table dispatch dengan resolusi OPD.

---

## 6. Repo & Tools

### 6.1 Wajib
| Repo | URL | Peran |
|---|---|---|
| ps3recomp | github.com/sp00nznet/ps3recomp | Pipeline lift, runtime HLE, D3D12 backend, template project |

Cara dapat: **(a)** clone + build runtime (sesuai port sister), atau **(b)** unduh bundle rilis (`ps3recomp-<ver>-win-x64.zip`: runtime lib, header, pipeline Python, `VERSION.txt`). ⚠️ Bundle bisa tidak cocok dengan branch yang dipakai port sister; cek dulu.

### 6.2 Kerangka port yang sudah jalan (BEDAH INI DULU)
| Repo | Bagus untuk dipelajari |
|---|---|
| simpsonsarcade-ps3 | Sudah playable; `PROGRESS.md` berisi riwayat + pengukuran |
| crazytaxi-ps3 | Pola `relift.sh` + `build.py`; catatan PR yang dibutuhkan |
| midway-ps3 | Contoh `--code-end` pada `relift.sh`; decrypt + kunci |
| flow | Studi kasus di Game Porting Guide; temuan teknis berlaku untuk semua port |
| twistedmetal | Sumber `tools/decrypt_self.py`; log kerja terbuka |

### 6.3 Dekripsi (dump & kunci milik sendiri)
| Tool | Catatan |
|---|---|
| `decrypt_self.py` (dari twistedmetal) | ✅ dipakai port sister + file kunci format scetool |
| ps3dec / ps3iso | ⚠️ tidak terverifikasi, jangan dijadikan satu-satunya jalur |
| Kunci (appldr, NP_klic) | Dari konsolmu sendiri. **Jangan di-commit.** |

### 6.4 Analisis & referensi
| Tool | Fungsi |
|---|---|
| RPCS3 | **Golden reference** visual + perilaku (bukan sumber kode) |
| Ghidra | Bedah fungsi yang gagal di-lift (lihat 10.4) |
| RenderDoc | Capture draw RSX/D3D12 ⚠️ cek kompatibilitas |
| REA | AI agent untuk RE (github.com/morluto/rea, dipakai di PRD PS4). ⚠️ belum dites untuk PowerPC/SPU |

### 6.5 Toolchain Windows
| Tool | Versi | Catatan |
|---|---|---|
| Visual Studio 2022 (Build Tools) + clang-cl | — | Port sister memakai clang-cl + Ninja di dalam lingkungan VS. MSYS2 Clang64 ⚠️ belum terbukti di jalur ini |
| CMake | 3.20+ | |
| Ninja | Latest | |
| Python | 3.10+ | `pip install -r requirements.txt` |
| Windows SDK (D3D12) | Latest | |
| **Vulkan SDK** | — | **TIDAK perlu** untuk Windows (D3D12) |

---

## 7. Milestones

### 🚦 M0 Gate — Go/No-Go (1–2 hari) — KERJAKAN PERTAMA
| # | Task | Deliverable |
|---|---|---|
| G0-1 | Cek status game di RPCS3 | Catatan status |
| G0-2 | Cek apakah port lain sudah ada (Discord ps3recomp + GitHub) | Tidak duplikat kerja |
| G0-3 | Ekstrak dump, dekripsi `EBOOT` → `EBOOT.ELF` | ELF valid |
| G0-4 | Jalankan `ppu_loader.py` → hitung import, cek pakai SPURS/PSN/video | `imports.json` + catatan |
| G0-5 | Cocokkan import dengan `docs/MODULE_STATUS.md` | Daftar modul belum ada/partial |
| G0-6 | Putuskan GO / NO-GO + tulis alasan | Keputusan |

**Heuristik** (berbasis bukti repo):
- GO: game kecil (PSN/arcade), SPURS sedikit, tanpa PSN wajib. Contoh VF5 tidak punya impor SPURS maupun PSN, dan Simpsons Arcade serta Tornado Outbreak sudah in-game.
- NO-GO untuk pemula: game dengan SPU/streaming berat, dekripsi bermasalah, tidak ada petunjuk dari port lain.
- 🧪 Jangan jadikan nama game tertentu patokan tanpa bukti.

### M0 — Persiapan (2–3 hari)
| # | Task | Deliverable |
|---|---|---|
| M0-1 | Setup workspace (Appendix B) + env mesin (Bagian 0) | Folder + env |
| M0-2 | Clone ps3recomp, **kunci tag/commit** | Versi tercatat di Metadata |
| M0-3 | Build runtime lib (atau pakai bundle rilis) | `ps3recomp_runtime.lib` |
| M0-4 | Salin kerangka dari port sister | `03_[GAME]_PORT\` |
| M0-5 | Baca `docs/GAME_PORTING_GUIDE.md` (12 fase) | Catatan |
| M0-6 | Buat `PATCH_MAP.md` | Daftar patch/fix yang butuh branch lain |

### M1 — Lift (1–2 minggu 🧪)
| # | Task | Deliverable |
|---|---|---|
| M1-1 | `ppu_loader.py` | `*.functions.json`, `*.imports.json` |
| M1-2 | `ppu_lifter.py --functions ... --hle-stubs ... --output recompiled/` | Source C++ |
| M1-3 | `gen_hle_nids.py` | `ppu_hle_nids.cpp` |
| M1-4 | SPU: `extract_spu_images` → `find_spu_functions` → `spu_lifter` | SPU C++ |
| M1-5 | Post-process jika perlu (rename, bctrl, dll.) | Source konsisten |
| M1-6 | Build (CMake + Ninja, clang-cl) | `[game].exe` |
| M1-7 | Buat `relift.sh`/`build.py` (salin pola port sister) | Relift satu perintah |

**Exit**: `.exe` terbentuk. Linker error itu normal, perbaiki satu per satu. Jalankan ulang relift tiap lifter berubah.

### M2 — Boot & HLE (1–3 minggu 🧪)
| # | Task | Deliverable |
|---|---|---|
| M2-1 | Jalankan, baca log, daftar HLE yang dipanggil tapi belum ada | Daftar |
| M2-2 | Implementasi/perbaiki **hanya yang dipanggil** (Bagian 9) | Boot lewat |
| M2-3 | Atasi abort di konstruktor/CRT (cek solusi flOw: longjmp untuk mencegat abort CRT saat stack overflow di konstruktor) | Masuk `main` |
| M2-4 | Pastikan path file: dump → host (`cellFs`) | File terbaca |
| M2-5 | Atasi dispatch miss (indirect call) | Tidak ada miss di jalur boot |

**Exit**: lewat logo publisher tanpa abort.

### M3 — Render (1–3 minggu 🧪)
Backend RSX → D3D12 **sudah ada**; kerjamu mencocokkan dan memperbaiki bug untuk game ini.
| # | Task | Deliverable |
|---|---|---|
| M3-1 | Window + swapchain D3D12 jalan | Window |
| M3-2 | Capture frame (PPM/PNG) | `frame.ppm` |
| M3-3 | Golden frame dari RPCS3 (kondisi sama) | `golden/*.png` |
| M3-4 | Bandingkan; catat beda (hitam, warna, tekstur) | Daftar beda |
| M3-5 | Perbaikan umum → PR ke ps3recomp | PR / patch lokal tercatat |

**Contoh bug dari port lain**: layar kota hitam tanpa perbaikan fp-flow-control (#187); sekitar satu dari enam frame berkedip hitam tanpa perbaikan join/flip (#185). Cek apakah game-mu butuh PR serupa.

### M4 — Input, Audio, Stabilitas (2–6 minggu 🧪)
| # | Task | Deliverable |
|---|---|---|
| M4-1 | Input (cellPad → XInput) | Kontrol jalan |
| M4-2 | Audio (cellAudio → WASAPI) | BGM/SFX |
| M4-3 | Video/cutscene (cellVdec/cellPamf, FFmpeg opsional): **skip dulu** jika menghambat | Cutscene putar/ter-skip |
| M4-4 | cellSaveData | Save/load OK |
| M4-5 | Audit SPU sync (SPURS/semaphore) bila hang | Tidak hang |
| M4-6 | Main 30 menit, catat crash | Crash log |

**Catatan**: README menyebut modul media masih partial (cellVdec, cellAdec, cellDmux, cellAtrac) dan cellSpurs.

### M5 — Rilis (1–2 minggu)
| # | Task |
|---|---|
| M5-1 | Launcher/config |
| M5-2 | README + disclaimer |
| M5-3 | Kirim perbaikan umum ke upstream |
| M5-4 | Rilis v0.1-alpha (kode saja) |

---

## 7A. Rencana Khusus Asura's Wrath

### 7A.1 Fakta game (dari sumber publik, cek lagi dengan dump-mu)
| Item | Nilai |
|---|---|
| Developer / Publisher | CyberConnect2 / Capcom |
| Rilis / Platform | 2012, PS3 dan Xbox 360, tidak ada versi PC resmi |
| Engine | Unreal Engine 3 |
| Genre | Aksi orang ketiga + banyak sekuens QTE bergaya anime episodik |
| Title ID | Dump kamu: **US (BLUS)**, ID persis diisi dari `PARAM.SFO`. Bukti RPCS3 yang kubaca memakai EU (`BLES01227`), bukan US ⚠️ |
| Update / DLC | Ada update (tester RPCS3 menyebut 1.2) dan DLC. ⚠️ Pastikan dump-mu sudah ter-merge update; catat versi |
| Status RPCS3 | Playable penuh (laporan yang kubaca dari EU). ⚠️ Cek status BLUS di compatibility list RPCS3 dan pakai golden frame dari region US |
| Trik RPCS3 | Pakai resolution scale threshold 512×512 supaya tidak ada artefak saat scaling. Berguna saat membandingkan frame (M3) |

### 7A.2 Gate khusus game (Hasil Ukur 2026-11-13)

| Cek | Cara | Hasil | Arti |
|---|---|---|---|
| Impor SPURS | hitung di `imports.json` | [x] Ada (39 fungsi) | SPURS dipakai (UE3 job queues) |
| Jumlah SPU image | `extract_spu_images.py` | 27 SPU image (1.52 MB) | Standar UE3 PS3, semua terekstrak bersih |
| Impor media (cellVdec/cellPamf/cellDmux/cellAdec) | `imports.json` | [x] **0 (NOL)** | **Bink Video internal**, tanpa dependensi video decoder PS3 |
| Impor PSN/NP | `imports.json` | [x] 42 fungsi (`sceNp`, `sceNpCommerce2`, `sceNpTrophy`) | Dapat distub offline |
| Modul tak ada di `MODULE_STATUS.md` | bandingkan | `sys_io` (kernel I/O), `sceNpCommerce2` (in-game store) | Modul inti lainnya (18 dari 21) status **Complete** |
| Port lain sudah ada? | Discord ps3recomp + GitHub | Tidak ada PS3 recomp (hanya ada WIP Xbox 360) | Jalur bersih, tidak duplikat |
| Ukuran ELF hasil decrypt | `decrypt_self.py` | 27.1 MB | 30.350 unique functions terdeteksi |

**Keputusan**: **GO bertahap** (Target: Tier 0 – 2).
Alasan:
1. Dekripsi SELF v2 (key_rev 0x0016) sukses 100% menjadi ELF 27.1 MB.
2. 290 dari 292 NID ter-resolve (99.3%).
3. Nol impor `cellVdec`/`cellPamf` (game memakai Bink Video di userspace).
4. SPU images terisolasi sebanyak 27 unit dan siap dilift.

### 7A.3 Definisi "jadi" bertingkat
Tiap tier punya bukti (video/log/screenshot). Berhenti di tier mana pun adalah hasil sah.

| Tier | Target | Bukti | Status Saat Ini |
|---|---|---|---|
| 0 | Build jalan, boot lewat logo Capcom/CyberConnect2 | Log + screenshot | **PASS** — `05_LOGS\e2e_tier2_20261115_061452\stages.log` + `stage_01_title.png` (`TITLEMENU_BG00.BIK` in `40.2s`, `exitCode=0`, `SPU_MISS_FATAL=1`) |
| 1 | Title screen + menu | Screenshot vs golden RPCS3 | **PASS (Parsial Golden)** — Tangkapan lokal + kontrol menu & save/load lolos (`05_LOGS\e2e_tc05_20261115_062608\stage_01_title.png`..`stage_03_main_menu.png`), golden RPCS3 `BLUS30721` belum tersedia (`07_DOCS\TC07_RPCS3_COMPARISON.md`) |
| 2 | Episode 1 playable (combat + QTE) | Rekaman 5 menit | **PASS** *(diperbarui 2026-11-15, tag `tier2`)* — QTE `"L-down + R-down"` (`Panah Bawah + K` -> `L=(128,255)` + `R=(128,255)`) lolos pada uji manual `05_LOGS\qte_ep1_manual_20261115_161352\stderr.log:2138-2201` (`05_LOGS\t1_tier2_pass_audit.txt`), memicu streaming sub-level `BC-S000_L01_PDE_02.XXX` & `BC-S000_STE_A030.XXX` serta melanjutkan adegan kredit di atas awan (`qte_t070s.png`), adegan air `"Gohma Carrier"` (`qte_t085s.png`), dan gameplay rail-shooter aktif (`qte_t115s.png`, `qte_t130s.png`, `stage_08_ep1_end.png`, `ExitCode=0`, `DispatchMiss=0`, rata-rata `39.77 FPS` keseluruhan / `33.10 FPS` pasca-QTE). Catatan: penyelesaian hingga layar *Episode 1 Clear/Save* akhir episode masih diperlukan untuk membuka Episode 2 di `BLUS30721-BCSAVEDATA`. Riwayat sebelumnya: ~~**PARSIAL** *(koreksi 2026-11-15)* — QTE `L↓+R↓` menahan alur ~70s s.d. 330s, jadi Episode 1 belum bisa dimainkan sampai selesai. Mesh `T6x1` (karakter/aktor) kolaps sebelum fix `CMP` (`05_LOGS\draw_census_20261115_110049` vs `..._111217`).~~ Riwayat awal: ~~**PASS** — Rekaman `330.11s` (`660` frame, `05_LOGS\e2e_tier2_20261115_061452\ep1_recording.mp4`, `62.71 MB`)...~~ |
| 3 | Beberapa episode berurutan, save/load jalan | Rekaman + save | **BELUM DIUJI PENUH** — Save/load (`BLUS30721-BCSAVEDATA`) terbukti membuka `EPISODE MENU` pada `05_LOGS\e2e_tc05_20261115_062608\stage_03_main_menu.png`; skrip batch `08_SCRIPTS\test_episodes_batch.ps1` siap (menunggu pembukaan Episode 2+ di save) |
| 4 | Seluruh game tamat | Log sesi penuh | **BELUM DIUJI** |
| 5 | DLC + update jalan | Log + rekaman | **BELUM DIUJI** (`Update v1.02 PKG` belum di-merge) |

Estimasi 🧪: Tier 0–1 beberapa minggu; sisanya sulit diperkirakan. Game besar UE3 bisa berbulan-bulan. **Jangan jadikan angka ini janji.**

#### 7A.3.1 Definisi Selesai v1.2 (Target Proyek Penuh)

| # | Kriteria | Target / Tolok Ukur | Status Saat Ini |
|---|---|---|---|
| 1 | **Tamat tanpa crash** | Episode 1 s.d. Episode 18 (True Ep 18) selesai dari awal hingga kredit akhir dengan `ExitCode=0`, `FatalOrAbort=0`, `SPU_MISS_FATAL=1` (`DispatchMiss=0`) | **PARSIAL** (Ep 1 terbukti playable melewati QTE & rail-shooter; Ep 2–18 belum diuji) |
| 2 | **Tidak ada soft-lock** | Seluruh QTE (stik tunggal/ganda, tombol, mash), dialog menu, transisi sub-level (`BC-S*_PDE_*`), dan *Episode Clear* berjalan tanpa menahan progres | **PARSIAL** (Menu + dialog Easy + QTE `L↓+R↓` + rail-shooter Ep 1 lolos; sisa QTE Ep 1–18 belum diuji) |
| 3 | **Visual mirip RPCS3 dengan toleransi tertulis** | Geometri 3D (`T6x1` `CMP`), partikel, UI/HUD, dan post-process sesuai golden RPCS3 `BLUS30721`; deviasi minor didokumentasikan di `07_DOCS\TC07_RPCS3_COMPARISON.md` & `KNOWN_ISSUES.md` | **BELUM LENGKAP** (Fix `CMP` memulihkan geometri 3D; menunggu tangkapan layar golden RPCS3 `BLUS30721` dari user; 3 kandidat visual `P1` dicatat) |
| 4 | **FPS stabil >= 30** | Rata-rata `>= 30 FPS` (`<= 33.33 ms/frame` pada `FRAME_BUDGET=1`, resolusi native `1280x720`) `[target, belum diukur di seluruh episode]` | **TERUKUR DI EP 1** (`35.43 FPS` / `28.23 ms` pada sensus `t010s..t070s` pasca-CMP; `39.77 FPS` keseluruhan & `33.10 FPS` pasca-QTE pada `qte_ep1_manual_20261115_161352`; Ep 2–18 `[target, belum diukur]`) |
| 5 | **Audio / Video** | Cutscene Bink (`.BIK`) dan BGM/SFX in-game berjalan sinkron tanpa hang/artefak warna | **PARSIAL** (Video `.BIK` & routing `NV0039` lolos; codec MP3 `Multistream` masih mencetak peringatan flash di stdout) |
| 6 | **Save / Load** | `cellSaveData` (`BLUS30721-BCSAVEDATA`) menyimpan & memuat progres antar-episode serta membuka `EPISODE MENU` secara persisten | **PASS (Menu/Ep1)** (`TC-05` terbukti di `05_LOGS\e2e_tc05_20261115_062608`; penyimpanan *Episode Clear* akhir episode belum diuji) |
| 7 | **Soak 30 menit per episode** | Tiap episode berjalan `>= 30 menit` (`1800s`, atau sampai tamat episode tanpa crash/hang/overflow `VBFULL`) | **BELUM DIUJI PENUH** (Terlama saat ini `330.11s` di `05_LOGS\e2e_tier2_20261115_061452` & `290.8s` di `qte_ep1_manual_20261115_161352`) |
| 8 | **DLC sebagai tier terpisah (Tier 5)** | Update `v1.02` (`UP0102-BLUS30721_00-PATCH02000000000`) + DLC (Ep 11.5, Ep 15.5, Part IV Nirvana Ep 19–22, Street Fighter crossover) diuji terpisah di Tier 5 | **BELUM DIUJI** (Tier 5 terpisah dari base game Ep 1–18) |

#### 7A.3.2 Status per Episode (`BLUS30721`)

| Episode | Kode Paket (`COOKEDPS3`) | Bagian (Chapter) | Status | Tanggal | Path Bukti | FPS Rata-rata | Masalah Terbuka |
|---|---|---|---|---|---|---|---|
| **Ep 1** | `BC-S000` (`L00..L03`) | Part I: Suffering (`C01`) | **PASS (Tier 2)** *(belum sampai layar Save akhir ep)* | 2026-11-15 | `05_LOGS\qte_ep1_manual_20261115_161352\`, `05_LOGS\t1_tier2_pass_audit.txt`, `05_LOGS\perf_cmp_before_after.txt` | `35.43 FPS` (sensus) / `39.77 FPS` (total) / `33.10 FPS` (pasca-QTE) | 3 kandidat visual `P1` (pantulan air bergelombang, segitiga terang kanan-atas QTE, garis hitam tipis tepi kiri); perlu dimainkan sampai layar *Episode 1 Clear/Save* untuk membuka Ep 2 di save |
| **Ep 2** | `BC-S010` (`L01`) | Part I: Suffering (`C01`) | **belum diuji** *(belum terbuka di save)* | — | — | `[belum diukur]` | Menunggu Ep 1 diselesaikan sampai *Episode Clear Save* agar terbuka di `EPISODE MENU` |
| **Ep 3** | `BC-S020` (`L01..L02`) | Part I: Suffering (`C01`) | **belum diuji** *(belum terbuka di save)* | — | — | `[belum diukur]` | Menunggu Ep 2 selesai / terbuka di save |
| **Ep 4** | `BC-S030` (`L00..L03`) | Part I: Suffering (`C01`) | **belum diuji** | — | — | `[belum diukur]` | — |
| **Ep 5** | `BC-S040` (`L01`) | Part I: Suffering (`C01`) | **belum diuji** | — | — | `[belum diukur]` | — |
| **Ep 6** | `BC-S050` (`L01`) | Part I: Suffering (`C01`) | **belum diuji** | — | — | `[belum diukur]` | — |
| **Ep 7** | `BC-S060` (`L01`) | Part II: Rebirth (`C02`) | **belum diuji** | — | — | `[belum diukur]` | — |
| **Ep 8** | `BC-S070` (`L00..L03`) | Part II: Rebirth (`C02`) | **belum diuji** | — | — | `[belum diukur]` | — |
| **Ep 9** | `BC-S080` (`L00..L06`) | Part II: Rebirth (`C02`) | **belum diuji** | — | — | `[belum diukur]` | — |
| **Ep 10** | `BC-S100` (`L00..L02`) | Part II: Rebirth (`C02`) | **belum diuji** | — | — | `[belum diukur]` | — |
| **Ep 11** | `BC-S110` (`L00..L02`) | Part II: Rebirth (`C02`) | **belum diuji** | — | — | `[belum diukur]` | — |
| **Ep 12** | `BC-S130` (`L00..L03`) | Part II: Rebirth (`C02`) | **belum diuji** | — | — | `[belum diukur]` | — |
| **Ep 13** | `BC-S140` (`L00..L09`) | Part III: Karma (`C03`) | **belum diuji** | — | — | `[belum diukur]` | — |
| **Ep 14** | `BC-S150` (`L01..L02`) | Part III: Karma (`C03`) | **belum diuji** | — | — | `[belum diukur]` | — |
| **Ep 15** | `BC-S160` (`L01`) | Part III: Karma (`C03`) | **belum diuji** | — | — | `[belum diukur]` | — |
| **Ep 16** | `BC-S180` (`L00..L07`) | Part III: Karma (`C03`) | **belum diuji** | — | — | `[belum diukur]` | — |
| **Ep 17** | `BC-S190` (`L00..L04`) | Part III: Karma (`C03`) | **belum diuji** | — | — | `[belum diukur]` | — |
| **Ep 18 / True Ep 18** | `BC-S200` (`L00..L08`) | Part III: Karma (`C03`) | **belum diuji** | — | — | `[belum diukur]` | — |
| **DLC + Update v1.02** | `UP0102-BLUS30721_00-*` | Tier 5 (Terpisah) | **belum diuji** | — | — | `[belum diukur]` | Update `v1.02` PKG belum di-merge; DLC belum dipasang |

### 7A.4 Risiko khusus game
| # | Risiko | Mitigasi |
|---|---|---|
| A-01 | UE3 di PS3 biasanya pakai banyak SPU job 🧪 (dugaan, cek di gate) | Hitung SPU image; pakai fallback SPU (`docs/SPU_FALLBACK.md`) sementara |
| A-02 | Cutscene/video: modul media ps3recomp masih partial | Cek impor cellVdec/cellPamf di gate; skip cutscene dulu, kerjakan belakangan |
| A-03 | QTE butuh input + timing akurat | Uji cellPad (XInput) di Tier 2; ukur latency |
| A-04 | Shader compile menyebabkan fps jatuh (dilaporkan di RPCS3) | Shader cache; pre-warm saat loading |
| A-05 | Artefak saat resolution scaling | Mulai dari resolusi native; uji scaling belakangan |
| A-06 | Update/DLC beda path | Merge update dulu; petakan path `/dev_hdd0/game/<id>/` (cellGame/cellFs) |
| A-07 | Sesi panjang → SPU sync hang atau memory leak | Stabilitas 30 menit → 2 jam sebelum lanjut ke tier berikutnya |
| A-08 | Progres QTE analog (`L↓ + R↓` atmospheric re-entry) & artefak minor tepi dialog load; Update v1.02 PKG belum ter-merge; root `.git` belum ada | Audit pembacaan `cellPad` analog saat QTE `L↓+R↓` (`05_LOGS\e2e_tier2_20261115_061452\ep1_t070s.png`), bandingkan golden RPCS3 (`TC-07`), serta putuskan ekstraksi PKG v1.02 & inisialisasi repo root sebelum rilis/tagging |

### 7A.5 Cara kerja bareng (loop debug)
Tiap masalah, kirim ke chat:
```
Tier sekarang: [0-5]
Gejala: [abort / hitam / freeze / crash] di [logo / menu / episode N]
Log ~50 baris terakhir: [tempel]
RIP + register (jika crash): [tempel]
Perubahan terakhir: [..]
Versi ps3recomp (tag/commit): [..]
```
Fungsi gagal-lift: kirim potongan atau `EBOOT.ELF`, bedah pakai skill RE (Bagian 10.4). Satu fix per iterasi, commit kecil, `git tag` per tier.

---

## 8. Requirements

### 8.1 Functional
| ID | Requirement | Prioritas | M |
|---|---|---|---|
| FR-01 | Dekripsi + lift PPU | P0 | M1 |
| FR-02 | Lift SPU (jika dipakai) | P0 | M1 |
| FR-03 | Boot sampai menu | P0 | M2 |
| FR-04 | Render D3D12 benar | P0 | M3 |
| FR-05 | Input gamepad | P0 | M4 |
| FR-06 | Audio | P0 | M4 |
| FR-07 | Save/load | P0 | M4 |
| FR-08 | Video/cutscene | P1 | M4 |
| FR-09 | Resolusi custom | P2 | M5 |

### 8.2 Non-Functional
| ID | Target |
|---|---|
| NFR-01 | FPS: acuan Tornado Outbreak ~10–16 fps di level pertama (titik awal wajar, 🧪 target 30–60 setelah optimasi) |
| NFR-02 | Crash <1 per 2 jam pada alpha |
| NFR-03 | Build ulang penuh ≤ 🧪 [ukur] menit (source lift besar, flOw 190 MB) |
| NFR-04 | Tidak ada file game/kunci di repo |

### 8.3 Hardware
| | Minimum | Recommended |
|---|---|---|
| GPU | D3D12 feature level 12_0 ⚠️ | RTX 3060 / setara |
| RAM | 16 GB 🧪 (lift + compile besar) | 32 GB |
| Storage | 100 GB free 🧪 | SSD 200 GB |
| OS | Windows 10/11 | Windows 11 |

---

## 9. Kebijakan HLE & Stub

1. **Bukan isi dari nol.** Runtime sudah punya mayoritas modul. Cek `docs/MODULE_STATUS.md` dulu.
2. **Gagal dengan keras.** Fungsi yang belum ada: log (nama/NID, pemanggil) sekali, lalu return error PS3 yang benar. Jangan return OK sembarangan.
3. **Hanya yang dipanggil.** Lihat log boot, tambal satu per satu.
4. **Semantik benar.** `cellFsOpen` harus mengembalikan fd nyata, bukan 0.
5. Rangka stub dari NID: `tools/generate_stubs.py`. Modul baru: `docs/CUSTOM_MODULES.md`.
6. Perbaikan umum → upstream; perbaikan khusus game → `src/` port-mu.

Contoh pola (sesuaikan dengan konvensi ps3recomp, ⚠️ cek di `CUSTOM_MODULES.md`):
```cpp
// src/hle_game_overrides.cpp  (khusus game, bukan umum)
// Pola: log sekali -> return kode error PS3 yang sesuai.
static int s_logged = 0;
int32_t myUnimplemented(/* args */) {
    if (!s_logged) { s_logged = 1; log_error("[HLE] unimplemented: myUnimplemented"); }
    return /* CELL_E... yang sesuai */ -1;
}
```

---

## 10. Self-Healing Loop & Script

### 10.1 Siklus
```
Relift (jika lifter/config berubah) → Build → Run 60 dtk → Baca log
 ├─ Abort/crash → RIP + log → klasifikasi: lift / HLE / memory / SPU / RSX
 │               → 1 fix, 1 commit → ulang
 └─ Jalan → capture frame → bandingkan golden RPCS3 → git tag milestone
```
Satu fix per iterasi. Tag per milestone supaya regresi bisa di-bisect.

### 10.2 Diagnostik (pakai yang sudah ada)
ps3recomp punya `docs/DIAGNOSTICS.md` (indeks variabel lingkungan) dan `docs/DEBUG_CONSOLE.md`. Changelog menyebut contoh: `PS3_FTRACE`, `PS3_LOG_FIRST`, `PS3_HLE_TOP`, `PS3_LANG`, `PS3_GAMEDATA_ROOT`, `SPU_INTERP_STATS`. ⚠️ Nama/efek bisa berubah antar versi, cek di tag yang kamu kunci.

### 10.3 `scripts\run_ps3.ps1`
```powershell
param(
    [int]$Timeout = 60,
    [string]$ExeName = "game.exe"          # ganti sesuai proyek
)
if (-not $env:PORT_ROOT) {
    Write-Host "Env belum di-set. Jalankan env_ps3_pc.ps1 / env_ps3_laptop.ps1" -ForegroundColor Red; exit 1
}
$exe = Join-Path $env:PORT_ROOT "build\$ExeName"
if (-not (Test-Path $exe)) { Write-Host "Exe tidak ada: $exe" -ForegroundColor Red; exit 1 }

$logDir = Join-Path $env:PORT_ROOT "05_LOGS"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ("run_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

$p = Start-Process -FilePath $exe -WorkingDirectory $env:PORT_ROOT -PassThru `
     -RedirectStandardOutput $log -RedirectStandardError "$log.err"
$p | Wait-Process -Timeout $Timeout -ErrorAction SilentlyContinue
if (-not $p.HasExited) { $p | Stop-Process -Force }
Get-Content $log -Tail 50
```
Build dan relift: **salin `relift.sh` dan `build.py` dari port sister** (`crazytaxi-ps3` / `midway-ps3`), ubah path dan nama game. Jangan tulis dari nol.

### 10.4 Bedah fungsi gagal-lift (Ghidra + skill reverse-engineering)

Dipakai saat lift salah, ada dispatch miss, atau RIP crash menunjuk fungsi tidak jelas.

**Urutan hemat konteks** (dari skill `reverse-engineering`):
1. Triage dulu: `triage.py <EBOOT.ELF>` (tipe file, header, string, hash).
2. Export decompile **sekali** ke file, lalu baca irisannya saja:
   ```
   analyzeHeadless <proj_dir> re -import <EBOOT.ELF> -scriptPath <skill>/scripts/ghidra -postScript DecompileExport.java decomp.txt -deleteProject
   ```
   Perlu JDK 21. ⚠️ `analyzeHeadless` bisa keluar kode 0 walau script gagal: pastikan `decomp.txt` ada dan berakhir dengan penanda jumlah fungsi.
3. Baca peta di awal file (entry, import, string, fungsi paling sering dipanggil, pemanggil API file/network/crypto), lalu `grep -n` nama/string dan baca fungsi terkait saja.
4. Tiap temuan wajib punya alamat. Beri nama fungsi begitu dipahami.
5. Target besar: batasi analisis (`-analysisTimeoutPerFile 900`, filter nama fungsi, jalankan di background).

**Cara pakai:**
- Di chat: upload `EBOOT.ELF` (atau potongan fungsi) dan bilang "bedah pakai skill RE". ⚠️ Skill jalan di sandbox Claude; Ghidra belum tentu terpasang di sana (skill mengecek dengan `check_tools.py`). File besar mungkin tidak muat.
- Di Claude Code/Cowork di mesinmu: skill jalan lokal dan memakai Ghidra yang terpasang.
- Kalau ada MCP server Ghidra tersambung, skill memakainya langsung (decompile, rename, xref).

**Batas yang jujur:** dukungan Ghidra untuk PowerPC dan SPU (Cell) ⚠️ belum kuverifikasi. Cek dulu apakah processor module SPU ada di instalasi Ghidra-mu sebelum bergantung padanya. Kerjakan hanya pada game milikmu sendiri (interoperabilitas/debug); skill menolak urusan DRM-strip atau bajak.

---

## 11. Pitfalls (dari port orang lain)

| ❌ Salah | ✅ Benar |
|---|---|
| Berharap lift langsung jalan | Normal ada linker/compile error; perbaiki bertahap |
| Pakai ps3recomp `master` tanpa kunci | Kunci tag/commit; cek PR yang belum merge yang dibutuhkan port contoh |
| Lupa `--hle-stubs` | Wajib, kalau tidak crash di import pertama |
| Salah batas `--code-end` | Midway: batas tepat setelah trampolin `.lib.stub`, `.rodata` menyusul |
| Lupa relift setelah lifter berubah | Jalankan `relift.sh` lagi |
| Tulis HLE dari nol | Cek `MODULE_STATUS.md`, perbaiki yang ada |
| Ganti renderer saat layar hitam | Capture frame, bandingkan golden RPCS3 |
| Jalankan game utama di RPCS3 | RPCS3 hanya pembanding |
| Salin kode RPCS3 | Dilarang (GPL), referensi perilaku saja |
| Commit kunci/dump/ELF | `.gitignore`; periksa `git status` |
| `git add .` | `git add [file spesifik]` |
| Abaikan ukuran source (190 MB) | Pakai `--chunks N` (lifter) agar rebuild lebih kecil ⚠️ cek di versi-mu |

---

## 12. Risks

| # | Risiko | Prob. | Dampak | Mitigasi |
|---|---|---|---|---|
| R-01 | Game terlalu berat (SPU/streaming) | Tinggi | Tinggi | M0 Gate, pilih game kecil |
| R-02 | Versi ps3recomp berubah/tidak cocok | Sedang | Tinggi | Kunci tag; baca PR yang dibutuhkan |
| R-03 | Dekripsi gagal / kunci tidak ada | Sedang | Tinggi | Ikuti jalur port sister; Discord |
| R-04 | Dispatch miss / indirect call | Tinggi | Sedang | Hash table bctrl + OPD; ikuti flOw |
| R-05 | Memory mapper salah | Sedang | Tinggi | Cek temuan flOw; log akses |
| R-06 | SPU sync hang | Sedang | Tinggi | Pakai fallback SPU (`docs/SPU_FALLBACK.md`) sementara |
| R-07 | Bug RSX (hitam, berkedip) | Tinggi | Sedang | Golden RPCS3 + PR upstream |
| R-08 | Modul media partial (video/audio decode) | Tinggi | Sedang | Skip cutscene dulu |
| R-09 | Waktu build/disk besar | Sedang | Sedang | Chunking, SSD, `-j` sesuai RAM |
| R-10 | Legal (kunci/aset) | Rendah | Tinggi | Bagian 14 |
| R-11 | Duplikasi kerja dengan orang lain | Sedang | Sedang | Cek Discord/GitHub di G0-2 |

---

## 13. Success Criteria & Testing

### 13.1 Success (v0.1-alpha)
- ✅ Boot dari dump pengguna sampai menu
- ✅ Render sesuai golden RPCS3 (toleransi dicatat)
- ✅ Main 1 stage, input + audio jalan
- ✅ Save/load jalan
- ✅ Tidak crash 30 menit (target 2 jam)
- ✅ Repo bersih dari aset/kunci

### 13.2 Test case
| TC | Skenario | Expected | Status (Laptop) |
|---|---|---|---|
| TC-01 | Jalankan tanpa dump | Pesan error jelas | **PASS** — `run_ps3.ps1 -ElfPath "00_GAME_DUMP\nonexistent.elf"` keluar `1` dengan `ELF tidak ada: ...` (`05_LOGS\tc01_no_dump.txt`). |
| TC-02 | Boot dengan dump | Logo → menu | **PASS** — Verifikasi E2E strict (`SPU_MISS_FATAL=1`): boot hingga Title Screen `TITLEMENU_BG00.BIK` (`40.2s` / `43.2s`) bebas black screen pasca-UE3 (`05_LOGS\e2e_tier2_20261115_061452\stage_01_title.png`, `05_LOGS\e2e_tc05_20261115_062608\stage_01_title.png`, `05_LOGS\task_c_spurs_audit.txt`). |
| TC-03 | Navigasi menu | Kontrol berfungsi | **PASS** — `START` → `"Load successful."` → `CROSS` → Main Menu → `NEW GAME` → `EASY` → dialog `"Start the game on EASY? Yes/No"` (`UP` → `Yes` → `CROSS`) → `"Save successful."` → `CROSS` → Episode 1 `PRESS START` (`05_LOGS\e2e_tier2_20261115_061452\stages.log`, `stage_01..08*.png`). |
| TC-04 | Main stage 1 | Tidak freeze | **PASS** *(diperbarui 2026-11-15, tag `tier2`)* — QTE `"L-down + R-down"` (`Panah Bawah + K` -> `L=(128,255)` + `R=(128,255)`) lolos pada uji manual `05_LOGS\qte_ep1_manual_20261115_161352\stderr.log:2138-2201` (`05_LOGS\t1_tier2_pass_audit.txt`), memicu streaming `BC-S000_L01_PDE_02.XXX` & `BC-S000_STE_A030.XXX` dan melanjutkan adegan kredit di atas awan (`qte_t070s.png`), adegan air `"Gohma Carrier"` (`qte_t085s.png`), serta gameplay rail-shooter aktif (`qte_t115s.png`, `qte_t130s.png`, `stage_08_ep1_end.png`, `ExitCode=0`, `DispatchMiss=0`, `FatalOrAbort=0`, `39.77 FPS` total / `33.10 FPS` pasca-QTE). Riwayat sebelumnya: ~~**PARSIAL** *(koreksi 2026-11-15)* — Tidak freeze/crash, tetapi progres tertahan di QTE `L↓+R↓`; pasca-fix `CMP`: `05_LOGS\draw_census_20261115_111217\audit_summary.txt` (`ExitCode=0`, `DispatchMiss=0`, `90.16s`).~~ Riwayat awal: ~~**PASS** — Episode 1 (`BC-S000_L01_PDE_01.XXX`) berjalan **`330.11s`** (`660` frame, `ep1_recording.mp4` `62.71 MB`)...~~ |
| TC-05 | Save → quit → load | Berhasil | **PASS** — Save pasca-pilih `EASY` (`UserAutoSave`, `PAYLOAD` `81920` bytes ke `BLUS30721-BCSAVEDATA`) → `WM_CLOSE` → relaunch → `AutoLoad2` (`new=0`, `PAYLOAD` `81920 -> 81920`) → `"Load successful."` → Main Menu kini menampilkan `EPISODE MENU` (`05_LOGS\e2e_tc05_20261115_062608\audit_summary.txt`, `stage_02_load_dialog.png`, `stage_03_main_menu.png`). |
| TC-06 | 30 menit gameplay | Tanpa crash | **BELUM DIUJI PENUH** — Sesi kontinu terlama saat ini `330.11s` (~5.5 menit) tanpa crash/leak (`05_LOGS\e2e_tier2_20261115_061452\audit_summary.txt`); soak penuh `1800s` + pencatatan memori menunggu konfirmasi eksekusi. |
| TC-07 | Bandingkan frame vs golden | Sesuai toleransi | **BELUM LENGKAP** — RPCS3 maupun golden frame `BLUS30721` tidak tersedia di mesin lokal; tabel perbandingan manual disiapkan di `07_DOCS\TC07_RPCS3_COMPARISON.md` memakai frame `05_LOGS\e2e_tier2_20261115_061452\` & `05_LOGS\e2e_tc05_20261115_062608\`. |
| TC-08 | Relift ulang | Hasil sama, build lolos | **PASS** — `08_SCRIPTS\relift.ps1` dijalankan 2x berurutan (`207.04s` & `204.48s`, exit `0`, `251` file identik `Hash Mismatches: 0`, backup `jobmods_register.c.bak` dibuat) lalu `py -3 08_SCRIPTS\build.py` exit `0` (`340.61s`, `AsurasWrathRecomp.exe` `423259648` bytes, `sha256=d66ed020ac20c376b450123240d81f802b138e010f485da4fecf07639770a443`) (`05_LOGS\relift_tc08_verify.txt`). |
| TC-09 | `git status` | Tidak ada kunci/dump | **PASS** *(diperbarui 2026-11-15 setelah `git init` root & verifikasi `git status` / `git ls-files`)* — Root workspace `"C:\PORTINGAN GAME\PS3\Ashura W"` (`master`, tag `tier1` & `tier2-partial`) dan `02_REPOS\ps3recomp` (`asuras-wrath-local`, `3a887069..d78a0f7c` di atas `de4f0903`) sama-sama bersih (`git status --short` kosong; `0` file dump/kunci/ELF/PKG/save/MP4/PNG di `git ls-files`; bukti `05_LOGS\tc09_git_root_verify.txt`). Riwayat koreksi sebelumnya: ~~**BELUM DIUJI** *(koreksi 2026-11-15; akan diperbarui setelah `git init` root)*.~~ Riwayat awal: ~~**PASS (dengan catatan)** — `git -C 02_REPOS\ps3recomp status --short` (`34 M`, `2 ??`) bersih dari dump/kunci; `03_ASURASWRATH_PORT\spu\` bebas `.bin`/`.elf`; `Key-pattern hits: 0`; workspace root belum memiliki `.git` (`Root workspace .git exists: False`) dan `03_ASURASWRATH_PORT\meta\spu\` berisi `27` `.elf` ekstrak lokal yang wajib di-`.gitignore` jika `.git` root dibuat (`05_LOGS\tc09_clean_audit.txt`).~~ |

---

## 14. Legal & Etika

> Bukan nasihat hukum. Aturan beda per negara.
- Tidak ada file game, firmware, atau kunci di repo. README ps3recomp menyatakan tidak ada kode, firmware, kunci, atau materi berhak cipta milik Sony di dalamnya.
- Dump dan dekripsi dilakukan **pengguna dari salinan/konsolnya sendiri**.
- ps3recomp berlisensi MIT ✅; lisensi port sister dan komponen lain ⚠️ cek satu per satu.
- RPCS3 hanya referensi; jangan salin kodenya.

```
This project is an educational reverse engineering effort.
NOT affiliated with, endorsed by, or sponsored by Capcom / CyberConnect2 or Sony.
Users must own a legitimate copy of Asura's Wrath for PS3 and prepare
their own files and keys. This project distributes no game files,
executables, firmware, keys, or assets.
License: 02_REPOS/ps3recomp berlisensi MIT License (Copyright (c) 2026 Ned Heller / sp00nznet); skrip dan kode port lokal mengikuti ketentuan proyek ini.
```

---

## 15. Glossary
| Istilah | Arti |
|---|---|
| PPU / SPU | CPU utama PowerPC / prosesor vektor Cell |
| RSX | GPU PS3 (NV47xx-class); perintah lewat cellGcm |
| LV2 | Kernel PS3 |
| NID | ID hash nama fungsi import |
| OPD | Function descriptor PPC64 (alamat + TOC) |
| bctrl | Panggilan tidak langsung PowerPC |
| SPURS | Penjadwal tugas SPU |
| HLE | Emulasi tingkat tinggi (library diganti kode host) |
| Lift | Menerjemahkan instruksi mesin → C/C++ |
| Golden frame | Frame referensi dari RPCS3 |

---

## 16. Appendix

### A. Timeline Ringkas 🧪
| Fase | Estimasi |
|---|---|
| M0 Gate | 1–2 hari |
| M0 | 2–3 hari |
| M1 Lift | 1–2 minggu |
| M2 Boot/HLE | 1–3 minggu |
| M3 Render | 1–3 minggu |
| M4 Stabilitas | 2–6 minggu |
| M5 Rilis | 1–2 minggu |
| **Total ke alpha** | **~2–4 bulan** (game kecil, ikut port sister) |

### B. Workspace Layout
```
%PORT_ROOT%\
├── 00_GAME_DUMP\            ← dump (READ-ONLY)
├── 01_KEYS\                 ← kunci milik sendiri (JANGAN commit)
├── 02_REPOS\                ← ps3recomp (versi dikunci), port sister, Ghidra
├── 03_[GAME]_PORT\          ← proyek (recompiled\, src\, CMakeLists.txt, relift.sh, build.py)
├── 04_BUILD\
├── 05_LOGS\                 ← log, frame, golden\
├── 06_TOOLS\
├── 07_DOCS\                 ← PRD, PATCH_MAP.md, KNOWN_ISSUES.md
└── 08_SCRIPTS\              ← env_ps3_*.ps1, run_ps3.ps1
```

### C. Next Steps (setelah v0.1)
Video penuh · optimasi FPS · resolusi/widescreen · kirim fix ke upstream · Linux/macOS (menunggu boot scaffold POSIX upstream).

---

## 17. Sign-off
| Peran | Nama | Tanggal |
|---|---|---|
| Project Lead | KRIXSAN | 2026-11-15 |

**End of PRD PS3 v2.1**
