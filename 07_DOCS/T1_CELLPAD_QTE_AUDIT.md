# T1–T4 Audit: `cellPad` Analog Input & QTE `L↓ + R↓` (*Asura's Wrath* `BLUS30721`)

**Tanggal**: 2026-11-15  
**Target build**: `04_BUILD\AsurasWrathRecomp.exe` (dikompilasi langsung dari sumber `02_REPOS\ps3recomp` sesuai `03_ASURASWRATH_PORT\CMakeLists.txt` & `08_SCRIPTS\build.py`)  
**Status Fase**: T1–T3 selesai & terverifikasi build/unit test; T4(a) injeksi terverifikasi bersih (`ExitCode=0`); **menunggu T4(b) uji manual gamepad nyata (Aturan 7)** sebelum analisis/perbaikan T5.

---

## 1. Ringkasan Eksekutif (T1–T4)

1. **Bedah `ps3recomp` & Sister Port (T1)**: Tata letak paket `CellPadData` di `libs\input\cellPad.h` & `libs\input\cellPad.c` menempatkan mask digital di `button[2..3]` dan 4 sumbu analog (`u8 0..255`, pusat `128`, Y: `0=atas / 255=bawah`) di `button[4..7]` (`RX, RY, LX, LY`). Dokumentasi `docs\MODULES_REFERENCE.md:243-268` keliru mengindeks offset `button[0..21]` (tergeser 2 elemen). Pada backend Windows XInput (`pad_poll_xinput`), refleksi sumbu Y menggunakan `(u8)(256 - pad_xinput_stick_to_u8(...))`, yang berisiko wrap ke `0` jika `pad_xinput_stick_to_u8` mengembalikan `0` serta menghasilkan rentang asimetris `1..255` (`256 - 255 = 1` saat dorong penuh atas).
2. **Pembacaan Analog di Game (T1)**: Dari `EBOOT.ELF` (`0x008A1E78..0x008A1E8F`) dan hasil lift `03_ASURASWRATH_PORT\recompiled\ppu_recomp_013.cpp:45561-46090` (`func_008A1AF0`, `func_008A1E90`), game mengimpor `sys_io` (`cellPadInit`, `cellPadSetPortSetting`, `cellPadGetData`, `cellPadGetInfo2`, `cellPadSetActDirect`), mengurangi byte stik dengan `127`, menskalakan dengan `1/127`, mengecek deadzone `0.2f`, menegasi `LY` (`ppu_recomp_013.cpp:45707`), dan memanggil handler tak langsung per sumbu.
3. **Audit & Validasi `PAD_STICK` (T2)**: Nilai `"128,255,128,255,190,260"` bukan 6 nilai stik — 4 field pertama adalah `lx,ly,rx,ry` (`0..255`), sedangkan field 5–6 (`190,260`) adalah jendela waktu aktif `[from, until)` dalam detik (atau flip jika `PAD_CLOCK=flips`). Validasi ketat `strtol`/`strtod` ditambahkan di `cellPad.c` dan lolos 7/7 kasus unit test (`05_LOGS\pad_t2_t3_unit_test.log`).
4. **Diagnostik `PAD_DIAG` & Bukti T4(a)**: Logging runtime `[PAD_DIAG]` di `cellPad.c` membuktikan pada `05_LOGS\qte_ep1_inject_20261115_095639` (`ExitCode=0`, `Ep1ElapsedSec=130.52`, `DispatchMiss=0`, `FatalOrAbort=0`) bahwa `cellPadGetData` benar-benar mengirim `len=28 hdr=0x7E src=PAD_STICK btn=(00,00:NONE) L=(128,255)[0.01,1.00] R=(128,255)[0.01,1.00] (z_sup=0)` selama `t=190.000s..258.454s`. Meski demikian, tangkapan layar `qte_t070s.png` hingga `stage_08_ep1_end.png` menunjukkan prompt QTE `(L)↓ (R)↓` tetap tertahan. Teramati pula di `qte_t055s.png` (`t≈193s`) bahwa prompt QTE belum muncul saat `PAD_STICK` mulai aktif di `t=190.000s`. Penyebab pasti QTE menunggu hasil T4(b) dengan kontroler fisik (Aturan 7).

---

## 2. T1 — Hasil Bedah Repo (`ps3recomp`, Port Sister, dan Binary Game)

### 2.1 Dokumentasi & Implementasi `ps3recomp` (`02_REPOS\ps3recomp`, MIT)
- **Commit basis**: HEAD lokal `de4f0903` (`https://github.com/sp00nznet/ps3recomp.git`).
- **Docs yang diaudit**:
  - `docs\GAME_PORTING_GUIDE.md:504-522` — menjelaskan pemetaan XInput → PS3 dan backend `cellPad` (XInput Windows / SDL2).
  - `docs\DIAGNOSTICS.md:501-517` — mendaftar variabel `PAD_*` (`PAD_ALWAYS_CHANGE`, `PAD_AUTOPRESS`, `PAD_FILE`, `PAD_NO_KEYBOARD`, `PAD_SCRIPT`, `PAD_STICK`, `PAD_SWEEP`).
  - `docs\MODULE_STATUS.md:36-42` — status `cellPad`, `cellKb`, `cellMouse` (**Complete**).
  - `docs\CUSTOM_MODULES.md:360` & `docs\MODULES_REFERENCE.md:215-270` — `MODULES_REFERENCE.md:243-268` mendokumentasikan `button[0..21]` sebagai `[DIGITAL1, DIGITAL2, RX, RY, ...]` (melenceng 2 indeks dari header/kode asli `cellPad.h:77-98`).
- **Format paket aktual `CellPadData` (`libs\input\cellPad.h:71-98`, `libs\input\cellPad.c:1022-1055`)**:
  - `data->len`: `0` (`CELL_PAD_LEN_NO_CHANGE` pada drain baca ulang ketika `s_data_fresh[port]==0` dan `PAD_ALWAYS_CHANGE` tidak aktif), `8` (default), `24` (`PRESS_ON`), atau `28` (`SENSOR_ON`, mode yang diminta *Asura's Wrath* via `cellPadSetPortSetting(0, setting=0x4)`).
  - `button[0] = 0` (reserved; GH3 membuang paket jika `!= 0`).
  - `button[1] = 0x70 | ((len / 2) & 0xF)` → `0x7E` saat `len=28`.
  - `button[2]` (`CELL_PAD_BTN_OFFSET_DIGITAL1`) = low byte mask `hs->buttons` (`SELECT..LEFT`).
  - `button[3]` (`CELL_PAD_BTN_OFFSET_DIGITAL2`) = high byte mask `hs->buttons` (`L2..SQUARE`).
  - `button[4]` (`ANALOG_RIGHT_X`), `button[5]` (`ANALOG_RIGHT_Y`), `button[6]` (`ANALOG_LEFT_X`), `button[7]` (`ANALOG_LEFT_Y`), masing-masing `u8` `0..255`, pusat `128`, Y: `0=atas`, `255=bawah`.
- **Terjemahan stik per backend di `libs\input\cellPad.c`**:
  - **XInput Windows (`cellPad.c:381,417-432,488-496`)**: `PAD_STICK_DEADZONE=7849`; `pad_xinput_stick_to_u8` memetakan `-1.0..1.0` ke `(int)(normalized * 127.0f) + 128` terklamp `0..255`. Lalu Y dibalik dengan `(u8)(256 - pad_xinput_stick_to_u8(...))` (catatan dari commit `a0a050ce` / `9e4e302a`, adaptasi PR `#42` `@sagemono`). Bila fungsi helper mengembalikan `0`, `(u8)(256 - 0)` wrap menjadi `0`; bila `+32767` (atas penuh → helper `255`), hasilnya `1`, bukan `0`.
  - **SDL2 (`cellPad.c:534-541,712-716`)**: `pad_sdl_axis_to_u8` memetakan langsung `-32768..32767` ke `0..255` tanpa inversi tambahan (`-32768 → 0`, `+32767 → 255`).
  - **Keyboard fallback port 0 (`cellPad.c:200-245,322-372,819`)**: Aktif hanya jika `s_host_state[0].connected == 0` dan jendela proses ini fokus (`GetForegroundWindow()` milik PID saat ini). Tambahan lokal di workspace ini menambahkan kontrol R-stick (`J/L/I/K`) dan `L3/R3` (`3/4`) selain D-pad/L-stick (Arrow keys) dan tombol aksi (`Z/X/A/S/Q/W/1/2/Return/Tab`).
  - **Commit input relevan di history `ps3recomp`**:
    - `9e4e302a` & `a0a050ce` (PR `#42` adaptasi) — split `DIGITAL2` & refleksi analog Y terhadap `128`.
    - `803d0b9b` (PR `#496`) — port kosong mereset stik ke `128` via `pad_host_release()`, bukan `0`.
    - `c59814b6` — `PAD_CLOCK=flips` untuk `PAD_SCRIPT`/`PAD_STICK`.
    - `74e8bb02` (`6eb26c1e`, PR `#570`) — pertahankan `PAD_FILE` melewati empty drain reads (`len=0`).
    - `8933ff90` (PR `#581`) — backoff polling slot XInput kosong `1000 ms`.
    - `24c702ae` — fallback keyboard lintas platform + `tests\test_pad_keyboard.c`.

### 2.2 Port Sister yang Tersedia di `02_REPOS` (MIT)
*(Catatan: `flow`, `midway-ps3`, dan `simpsonsarcade-ps3` tidak ter-clone di `02_REPOS`; hanya `crazytaxi-ps3` dan `twistedmetal` tersedia lokal. Tidak ada kode GPL RPCS3 yang disalin ke tree.)*
- **`crazytaxi-ps3` (`94c5a3d`, `https://github.com/sp00nznet/crazytaxi-ps3.git`, MIT)**: `README.md:87` memanfaatkan `PAD_SCRIPT="30:0x0008"` untuk otomasi input berbasis waktu, mask tombol `START=0x0008`, `CROSS=0x4000`.
- **`twistedmetal` (`23afb43`, `https://github.com/sp00nznet/twistedmetal.git`, MIT)**: `src\gen\ppu_hle_nids.cpp:485-497,1604-1616` mendaftarkan NID standar `sys_io` termasuk `cellPadInit` (`0x1CF98800`), `cellPadGetData` (`0x8B72CDA1`), `cellPadGetInfo2` (`0xA703A51D`), `cellPadSetPortSetting` (`0x578E3C98`), `cellPadSetActDirect` (`0xF65544EE`).

### 2.3 Pembacaan `sys_io` & Sumbu Analog pada *Asura's Wrath* (`EBOOT.ELF` & `ppu_recomp_013.cpp`)
- **Impor `sys_io` (`03_ASURASWRATH_PORT\meta\EBOOT.imports.json`)**:
  - 14 NID `sys_io`, terdiri atas 5 fungsi `cellPad` (`cellPadInit` `0x1cf98800`, `cellPadSetPortSetting` `0x578e3c98`, `cellPadGetData` `0x8b72cda1`, `cellPadGetInfo2` `0xa703a51d`, `cellPadSetActDirect` `0xf65544ee`), 6 NID `cellKb*`, dan 3 NID `cellMouse*`.
- **Konstanta & Jalur Sumbu Analog Game (`EBOOT.ELF` `0x008A1E78..0x008A1E8F`, `ppu_recomp_013.cpp:45561-46090`)**:
  - Tabel konstanta float di `0x008A1E78`: `+0x00 = 0.0f`, `+0x04 = 0.20000000298023224f` (deadzone), `+0x08 = 0.007874015718698502f` (`1.0 / 127.0`), `+0x0C = 0.001956947147846222f` (`1.0 / 511.0`), `+0x10 = -1.0f`, `+0x14 = 1.0f`.
  - Fungsi PPU `func_008A1AF0` & `func_008A1E90` (dipanggil oleh `func_008A2C18` → `func_008A2E1C`) mengurangkan nilai `u8` analog dengan `127`, mengalikan dengan `1/127`, memeriksa `fabs(axis) >= 0.2f`, menegasi `LY` di `ppu_recomp_013.cpp:45707` (`ctx->fpr[1] = -ctx->fpr[1]`), lalu melakukan `ps3_indirect_call` per sumbu.

---

## 3. T2 — Audit & Validasi `PAD_STICK`

- **Audit `"128,255,128,255,190,260"`**:
  - Format resmi yang didokumentasikan di `02_REPOS\ps3recomp\libs\input\cellPad.c`: `PAD_STICK="lx,ly,rx,ry[,from,until]"`
  - Field 1..4 (`128,255,128,255`): sumbu analog `u8` rentang `[0..255]` (`128`=tengah, `255`=bawah penuh pada Y).
  - Field 5..6 (`190,260`): nilai `double` jendela waktu aktif `[190.0, 260.0)` dalam **detik** (atau **flip** bila `PAD_CLOCK=flips`). Angka `260` valid sebagai detik akhir window, bukan koordinat stik.
- **Perbaikan di `cellPad.c`**:
  - Parser diganti dari `sscanf` longgar ke `strtol` / `strtod` ketat yang menolak string kosong, token non-numerik / karakter sisa, sumbu di luar `[0..255]`, jumlah field salah, dan window invalid (`until <= from`), serta membatasi injeksi hanya ke `port_no == 0` dan mencetak `[cellPad] PAD_STICK armed: ...` atau `[cellPad] ERROR: ...` ke `stderr`.
- **Bukti Unit Test (`05_LOGS\pad_t2_t3_unit_test.log`) — 7/7 PASS**:
  - Menolak `"128,255,128,260"` (field 4 = `260 > 255`), `"128,-1,128,128"` (field 2 = `-1 < 0`), `""`, `"abc,128,128,128"`, dan `"128,255,128,255,260,190"` (`until <= from`).
  - Menerima `"128,255,128,255,0,10"` dan `"128,255,128,255,0,260"`, mengembalikan `len=28 L=(128,255) R=(128,255)`.

---

## 4. T3 — Diagnostik `PAD_DIAG`

- Ditambahkan di `02_REPOS\ps3recomp\libs\input\cellPad.c`: `pad_diag_level()`, `pad_diag_norm_127()`, `pad_diag_fmt_btns()` yang aktif lewat env `PAD_DIAG` (`0`=mati, `1`=perubahan tombol/stik/sumber + heartbeat `GetData` tiap `2s` & `GetInfo2` tiap `5s` + penghitung empty drain `len=0`, `2`/`all`=semua panggilan).
- Format log di `stderr`:
  - `[PAD_DIAG] enabled level=1 mapping: D1=btn[2] D2=btn[3] RX=btn[4] RY=btn[5] LX=btn[6] LY=btn[7] (u8 0..255, 128=ctr, Y:0=up/255=down)`
  - `[PAD_DIAG][SetPortSetting] t=... flip=... port=0 setting=0x4`
  - `[PAD_DIAG][GetInfo2] t=... flip=... max=4 now=1 p0(status=0x1 setting=0x4 cap=0x1F type=0x0)`
  - `[PAD_DIAG][GetData] t=... flip=... p=0 len=28 hdr=0x7E src=<host/kbd|PAD_STICK|PAD_SWEEP|disconn> btn=(..) L=(..)[..] R=(..)[..] (z_sup=...)`

---

## 5. T4(a) — Hasil Uji Mode Injeksi (`test_qte_ep1.ps1`)

Skrip uji `08_SCRIPTS\test_qte_ep1.ps1` menyediakan dua mode: `-Mode inject` (mode `(a)`) dan `-Mode manual` (mode `(b)`), keduanya dengan `SPU_MISS_FATAL=1` dan `PAD_DIAG=1`.

- **Hasil Run Verifikasi Bersih**: `05_LOGS\qte_ep1_inject_20261115_095639\`
  - `ExitCode`: `0` (penutupan bersih via `WM_CLOSE` setelah fix `[void]$p.Handle` di `test_qte_ep1.ps1`)
  - `Ep1ElapsedSec`: `130.52` | `DispatchMiss`: `0` | `FatalOrAbort`: `0`
  - `DiagGetInfo2`: `55` | `DiagSetPort`: `2` | `DiagGetDataTotal`: `148` (`active len>0: 142`, `drain len=0: 6`)
  - `PAD_STICK` armed: `[cellPad] PAD_STICK armed: L=(128,255) R=(128,255) window=[190.000, 260.000) (sec)`
- **Bukti Pengiriman Data Analog ke Game (`stderr.log` & `audit_summary.txt`)**:
  - `t=189.125s` (`flip=11789`): `src=host/kbd L=(128,128)[0.01,0.01] R=(128,128)[0.01,0.01]`
  - `t=190.000s` (`flip=11829`): `src=PAD_STICK btn=(00,00:NONE) L=(128,255)[0.01,1.00] R=(128,255)[0.01,1.00] (z_sup=0)`
  - Tetap stabil di `len=28 hdr=0x7E` sepanjang `190.000s..258.454s` (`flip=14823`), lalu kembali ke `L=(128,128) R=(128,128)` pada `t=260.000s`.
- **Observasi Visual (`qte_t055s.png` .. `stage_08_ep1_end.png`)**:
  - Pada `qte_t055s.png` (`t≈193s` proses), prompt `(L)↓ (R)↓` **belum muncul** (masih fase jatuh bebas) — artinya `PAD_STICK` sudah menahan `L=(128,255) R=(128,255)` *sebelum* QTE dimulai.
  - Pada `qte_t070s.png` (`t≈208s`) s.d. `qte_t130s.png` (`t≈268s`) dan `stage_08_ep1_end.png`, prompt `(L)↓ (R)↓` tampak di layar namun tidak lolos selama `~60+` detik meski `cellPadGetData` menyerahkan `LY=255` & `RY=255`.
- **Henti Wajib (Aturan 7)**: Belum menyimpulkan akar masalah untuk **T5** (mis. apakah QTE butuh transisi dari `128 → 255` setelah prompt muncul, polaritas `RY`/`LY` berbeda, atau mekanik input game khusus) sebelum user menguji manual dengan gamepad fisik lewat:
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File "C:\PORTINGAN GAME\PS3\Ashura W\08_SCRIPTS\test_qte_ep1.ps1" -Mode manual
  ```

