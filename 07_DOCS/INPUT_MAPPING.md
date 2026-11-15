# Audit Input (`cellPad`) & Tabel Pemetaan Kontrol — *Asura's Wrath* (`BLUS30721`)

**Tanggal**: 2026-11-15  
**Target Build**: `04_BUILD\AsurasWrathRecomp.exe` (Windows x64)  
**Sumber Kode Utama**: `02_REPOS\ps3recomp\libs\input\cellPad.c` (`1..1893`), `02_REPOS\ps3recomp\libs\input\cellPad.h` (`1..209`), `02_REPOS\ps3recomp\CMakeLists.txt` (`139..170`), `03_ASURASWRATH_PORT\CMakeLists.txt` (`1..319`)

---

## 1. Konfirmasi Backend Input: Apakah SDL3 Digunakan?

**Jawaban Singkat: TIDAK.** Build Windows `AsurasWrathRecomp.exe` **tidak menggunakan SDL3 maupun SDL2**.

### Bukti Kode & Konfigurasi Build (File & Baris)
1. **Seleksi Backend Kompilasi (`02_REPOS\ps3recomp\libs\input\cellPad.c:41-50`)**:
   ```c
   #if defined(PS3RECOMP_PAD_USE_SDL2)
     #define PAD_BACKEND_SDL2  1
     #define PAD_BACKEND_XINPUT 0
   #elif defined(_WIN32)
     #define PAD_BACKEND_SDL2  0
     #define PAD_BACKEND_XINPUT 1
   #else
     #define PAD_BACKEND_SDL2  1
     #define PAD_BACKEND_XINPUT 0
   #endif
   ```
   Karena pada Windows makro `_WIN32` aktif dan `PS3RECOMP_PAD_USE_SDL2` tidak didefinisikan di `02_REPOS\ps3recomp\CMakeLists.txt` maupun `03_ASURASWRATH_PORT\CMakeLists.txt`, maka:
   - `PAD_BACKEND_XINPUT = 1`
   - `PAD_BACKEND_SDL2 = 0`
2. **Konfigurasi Linker CMake (`02_REPOS\ps3recomp\CMakeLists.txt:139-170`)**:
   - Cabang `if(WIN32)` (baris `139–144`) hanya menautkan `ws2_32`, `ole32`, dan `bcrypt`.
   - Pencarian `find_package(SDL2 QUIET)` (baris `149`) berada di cabang `else()` yang hanya dieksekusi pada host non-Windows (Linux/macOS).
   - Bahkan pada host non-Windows, `ps3recomp` memakai `<SDL2/SDL.h>` (`cellPad.c:65`), bukan SDL3 (kata `SDL3` di `cellPad.c:568` hanya muncul di komentar mengenai wrapper `sdl2-compat over SDL3` pada Homebrew macOS).

---

## 2. Arsitektur 3 Lapis Sumber Input pada Build Ini

Setiap kali game memanggil `cellPadGetData(port_no, data_guest)` (`cellPad.c:1052-1556`), fungsi `pad_poll_backend()` (`cellPad.c:904-927`, interval minimum `PAD_POLL_INTERVAL_MS = 4 ms` / `250 Hz` di baris `788`) membaca input dari **3 lapis sumber** berikut:

| Urutan / Prioritas | Sumber Input | File & Baris di `cellPad.c` | Kondisi Aktif & Cara Kerja |
|---|---|---|---|
| **1 (Utama — Gamepad Fisik)** | **Windows XInput** (`XInput1_4.dll` / `XInput1_3.dll` / `XInput9_1_0.dll`) | `52–62`, `378–526`, `916–917` | Dimuat dinamis saat runtime dari `C:\Windows\System32` via `LoadLibraryExW(..., LOAD_LIBRARY_SEARCH_SYSTEM32)` di `pad_xinput_load()` (`395–415`). Mem-poll slot XInput `0..3` via `XInputGetState` di `pad_poll_xinput()` (`443–513`). **Hanya membaca controller XInput** (Xbox 360 / Xbox One / Series X\|S, atau DualShock/DualSense yang dijalankan lewat wrapper XInput seperti DS4Windows / Steam Input). |
| **2 (Fallback — Keyboard PC)** | **Win32 `GetAsyncKeyState` + `GetForegroundWindow`** | `216–245`, `322–372`, `921` | Dipanggil melalui `if (!s_host_state[0].connected) pad_poll_keyboard();` (`921`). Hanya aktif pada **Port 0** apabila: (a) **tidak ada** controller XInput di slot 0, (b) env `PAD_NO_KEYBOARD` tidak disetel (`324–326`), dan (c) **jendela game `Asura's Wrath` sedang fokus (foreground)** (`pad_host_window_focused()`, baris `217–224`). Jika jendela kehilangan fokus (`Alt+Tab` ke terminal), semua tombol dilepas dan stik dikembalikan ke netral `128` (`329–337`). |
| **3 (Override / Injeksi Uji)** | **Variabel Lingkungan `PAD_*`** | `1077–1387` | Dievaluasi di dalam `cellPadGetData()` setelah polling fisik:<ul><li>`YDKJ_INJECT_PAD` (`975–1010`): pulsa tombol berkala setelah delay.</li><li>`PAD_AUTOPRESS` (`1059–1067`): pulsa `CROSS` (`0x40`) lalu `START` (`0x08`).</li><li>`PAD_SCRIPT` (`1077–1117`): jadwal `<detik>:<mask16>` di-OR (`\|=`) ke `DIGITAL1`/`DIGITAL2`.</li><li>`PAD_FILE` (`1132–1157`): baca `<mask16> [hold_count]` dari file dan di-OR (`\|=`) ke `DIGITAL1`/`DIGITAL2`.</li><li>`PAD_STICK` (`1268–1359`): `"lx,ly,rx,ry[,from,until]"` — **menimpa** (`=`) ke-4 sumbu analog `hs->analog_lx/ly/rx/ry` pada Port 0 selama berada di jendela waktu `[from, until)`.</li><li>`PAD_SWEEP` (`1365–1387`): siklus 9 arah stik otomatis.</li></ul> |

> **Penting untuk Pengujian Manual**: Jika `PAD_STICK` aktif di dalam jendela waktunya `[from, until)`, nilai `PAD_STICK` akan **menimpa** stik fisik XInput maupun Keyboard (`cellPad.c:1354-1358`). Oleh karena itu, pada mode manual (`08_SCRIPTS\test_qte_ep1.ps1 -Mode manual`), variabel `PAD_STICK`, `PAD_SWEEP`, `PAD_SCRIPT`, dan `PAD_AUTOPRESS` sengaja dihapus (`test_qte_ep1.ps1:27-29`).

---

## 3. Tabel Mapping Lengkap: Keyboard $\to$ Tombol & Stik PS3 (Port 0)

Definisi konstanta virtual-key Windows berada di `cellPad.c:226-245`, dan logika pemetaannya berada di `pad_poll_keyboard()` (`cellPad.c:339-366`) serta pengisian pressure di `cellPadGetData()` (`cellPad.c:1394-1428`).

> **PERHATIAN PENTING**: Skema keyboard `ps3recomp` **bukan WASD**!
> - Tombol **`S`** adalah **$\triangle$ (`TRIANGLE`)**, **bukan** stik kiri bawah!
> - Tombol **`W`** adalah **`R1`**, dan **`A`** adalah **$\square$ (`SQUARE`)**!
> - **Stik Kiri (`Left Stick`) digabung dengan `Panah` (`Arrow Keys`)**, sedangkan **Stik Kanan (`Right Stick`) memakai `I / J / K / L`**.

| Kategori PS3 | Kontrol PS3 (DualShock 3) | Tombol Keyboard (Windows `VK_*`) | Kode & Bitmask di `CellPadData` | Nilai Analog / Pressure yang Dikirim | Baris `cellPad.c` |
|---|---|---|---|---|---|
| **D-Pad + Stik Kiri** | **D-Pad Up** + **Left Stick Up (`L↑`)** | **`Up Arrow` (Panah Atas)** (`VK_UP`) | `button[2]` (`DIGITAL1`) `0x10` (`CELL_PAD_CTRL_UP`) | `button[7]` (`LX=128`, **`LY=0`**), `press_up=255` | `226, 340, 361, 1415` |
| **D-Pad + Stik Kiri** | **D-Pad Down** + **Left Stick Down (`L↓`)** | **`Down Arrow` (Panah Bawah)** (`VK_DOWN`) | `button[2]` (`DIGITAL1`) `0x40` (`CELL_PAD_CTRL_DOWN`) | `button[7]` (`LX=128`, **`LY=255`**), `press_down=255` | `227, 340, 361-362, 1416` |
| **D-Pad + Stik Kiri** | **D-Pad Left** + **Left Stick Left (`L←`)** | **`Left Arrow` (Panah Kiri)** (`VK_LEFT`) | `button[2]` (`DIGITAL1`) `0x80` (`CELL_PAD_CTRL_LEFT`) | `button[6]` (**`LX=0`**, `LY=128`), `press_left=255` | `228, 341, 359, 1414` |
| **D-Pad + Stik Kiri** | **D-Pad Right** + **Left Stick Right (`L→`)** | **`Right Arrow` (Panah Kanan)** (`VK_RIGHT`) | `button[2]` (`DIGITAL1`) `0x20` (`CELL_PAD_CTRL_RIGHT`) | `button[6]` (**`LX=255`**, `LY=128`), `press_right=255` | `229, 341, 359-360, 1413` |
| **Stik Kanan** | **Right Stick Up (`R↑`)** | **`I`** (`'I'`) | *(tidak mengubah bit digital)* | `button[5]` (`RX=128`, **`RY=0`**) | `240, 355, 364` |
| **Stik Kanan** | **Right Stick Down (`R↓`)** | **`K`** (`'K'`) | *(tidak mengubah bit digital)* | `button[5]` (`RX=128`, **`RY=255`**) | `242, 355, 364` |
| **Stik Kanan** | **Right Stick Left (`R←`)** | **`J`** (`'J'`) | *(tidak mengubah bit digital)* | `button[4]` (**`RX=0`**, `RY=128`) | `241, 354, 363` |
| **Stik Kanan** | **Right Stick Right (`R→`)** | **`L`** (`'L'`) | *(tidak mengubah bit digital)* | `button[4]` (**`RX=255`**, `RY=128`) | `243, 354, 363` |
| **Face Buttons** | **$\times$ (`CROSS` / Konfirmasi / Serang)** | **`Z`** (`'Z'`) | `button[3]` (`DIGITAL2`) `0x40` (`0x4000`) | `button[14]` (`press_cross=255`) | `230, 342, 1419` |
| **Face Buttons** | **$\bigcirc$ (`CIRCLE` / Batal / Burst)** | **`X`** (`'X'`) | `button[3]` (`DIGITAL2`) `0x20` (`0x2000`) | `button[13]` (`press_circle=255`) | `231, 342, 1418` |
| **Face Buttons** | **$\square$ (`SQUARE` / Tembak)** | **`A`** (`'A'`) | `button[3]` (`DIGITAL2`) `0x80` (`0x8000`) | `button[15]` (`press_square=255`) | `232, 343, 1420` |
| **Face Buttons** | **$\triangle$ (`TRIANGLE` / Heavy Attack)** | **`S`** (`'S'`) | `button[3]` (`DIGITAL2`) `0x10` (`0x1000`) | `button[12]` (`press_triangle=255`) | `233, 343, 1417` |
| **Shoulder / Trigger** | **`L1`** | **`Q`** (`'Q'`) | `button[3]` (`DIGITAL2`) `0x04` (`0x0400`) | `button[16]` (`press_l1=255`) | `234, 344, 1421` |
| **Shoulder / Trigger** | **`R1`** | **`W`** (`'W'`) | `button[3]` (`DIGITAL2`) `0x08` (`0x0800`) | `button[17]` (`press_r1=255`) | `235, 344, 1422` |
| **Shoulder / Trigger** | **`L2`** | **`1`** (angka 1 baris atas, `'1'`) | `button[3]` (`DIGITAL2`) `0x01` (`0x0100`) | `button[18]` (`press_l2=255`) | `236, 345, 365, 1423` |
| **Shoulder / Trigger** | **`R2`** | **`2`** (angka 2 baris atas, `'2'`) | `button[3]` (`DIGITAL2`) `0x02` (`0x0200`) | `button[19]` (`press_r2=255`) | `237, 345, 366, 1424` |
| **Stick Click** | **`L3` (Tekan Stik Kiri)** | **`3`** (angka 3 baris atas, `'3'`) | `button[2]` (`DIGITAL1`) `0x02` (`0x0002`) | *(digital saja)* | `238, 346` |
| **Stick Click** | **`R3` (Tekan Stik Kanan)** | **`4`** (angka 4 baris atas, `'4'`) | `button[2]` (`DIGITAL1`) `0x04` (`0x0004`) | *(digital saja)* | `239, 346` |
| **System** | **`START` (Pause / Mulai)** | **`Enter` (`Return`)** (`VK_RETURN`) | `button[2]` (`DIGITAL1`) `0x08` (`0x0008`) | *(digital saja)* | `244, 347` |
| **System** | **`SELECT` (Back)** | **`Tab`** (`VK_TAB`) | `button[2]` (`DIGITAL1`) `0x01` (`0x0001`) | *(digital saja)* | `245, 347` |

---

## 4. Tabel Mapping Lengkap: Gamepad XInput $\to$ Tombol & Stik PS3 (Port 0..3)

Didefinisikan di `pad_xinput_stick_to_u8()` (`cellPad.c:417-432`) dan `pad_poll_xinput()` (`cellPad.c:443-513`). Deadzone bawaan stik adalah `PAD_STICK_DEADZONE = 7849` (`~24%` dari `32767`, baris `381`), dan ambang digital trigger adalah `PAD_TRIGGER_THRESHOLD = 30` (dari `0..255`, baris `382`).

| Kategori PS3 | Kontrol PS3 (DualShock 3) | Kontrol Gamepad XInput (Xbox) | Kode & Bitmask di `CellPadData` | Konversi Analog / Pressure (`0..255`) | Baris `cellPad.c` |
|---|---|---|---|---|---|
| **D-Pad** | **D-Pad Up** | `XINPUT_GAMEPAD_DPAD_UP` | `button[2]` (`DIGITAL1`) `0x10` | `button[10]` (`press_up = 255`), **tidak** mengubah `LX/LY` | `473, 502` |
| **D-Pad** | **D-Pad Down** | `XINPUT_GAMEPAD_DPAD_DOWN` | `button[2]` (`DIGITAL1`) `0x40` | `button[11]` (`press_down = 255`), **tidak** mengubah `LX/LY` | `475, 503` |
| **D-Pad** | **D-Pad Left** | `XINPUT_GAMEPAD_DPAD_LEFT` | `button[2]` (`DIGITAL1`) `0x80` | `button[9]` (`press_left = 255`), **tidak** mengubah `LX/LY` | `476, 504` |
| **D-Pad** | **D-Pad Right** | `XINPUT_GAMEPAD_DPAD_RIGHT` | `button[2]` (`DIGITAL1`) `0x20` | `button[8]` (`press_right = 255`), **tidak** mengubah `LX/LY` | `474, 505` |
| **Stik Kiri** | **Left Stick X (`LX`: Kiri $\leftrightarrow$ Kanan)** | `sThumbLX` (`-32768..+32767`) | `button[6]` (`ANALOG_LEFT_X`) | Deadzone `±7849` $\to$ `128`; Kiri penuh `-32768` $\to$ `0`; Kanan penuh `+32767` $\to$ `255` | `417-432, 492` |
| **Stik Kiri** | **Left Stick Y (`LY`: Atas $\leftrightarrow$ Bawah)** | `sThumbLY` (`-32768..+32767`) | `button[7]` (`ANALOG_LEFT_Y`) | Rumus: `(u8)(256 - pad_xinput_stick_to_u8(sThumbLY, 7849))` (`493`). Tengah $\to$ `128`; **Bawah penuh (`-32768` / `-32767`) $\to$ `255`**; Atas penuh (`+32767`) $\to$ `1` | `417-432, 493` |
| **Stik Kanan** | **Right Stick X (`RX`: Kiri $\leftrightarrow$ Kanan)** | `sThumbRX` (`-32768..+32767`) | `button[4]` (`ANALOG_RIGHT_X`) | Deadzone `±7849` $\to$ `128`; Kiri penuh `-32768` $\to$ `0`; Kanan penuh `+32767` $\to$ `255` | `417-432, 494` |
| **Stik Kanan** | **Right Stick Y (`RY`: Atas $\leftrightarrow$ Bawah)** | `sThumbRY` (`-32768..+32767`) | `button[5]` (`ANALOG_RIGHT_Y`) | Rumus: `(u8)(256 - pad_xinput_stick_to_u8(sThumbRY, 7849))` (`495`). Tengah $\to$ `128`; **Bawah penuh (`-32768` / `-32767`) $\to$ `255`**; Atas penuh (`+32767`) $\to$ `1` | `417-432, 495` |
| **Face Buttons** | **$\times$ (`CROSS`)** | **Tombol `A`** (`XINPUT_GAMEPAD_A`) | `button[3]` (`DIGITAL2`) `0x40` | `button[14]` (`press_cross = 255`) | `483, 508` |
| **Face Buttons** | **$\bigcirc$ (`CIRCLE`)** | **Tombol `B`** (`XINPUT_GAMEPAD_B`) | `button[3]` (`DIGITAL2`) `0x20` | `button[13]` (`press_circle = 255`) | `482, 507` |
| **Face Buttons** | **$\square$ (`SQUARE`)** | **Tombol `X`** (`XINPUT_GAMEPAD_X`) | `button[3]` (`DIGITAL2`) `0x80` | `button[15]` (`press_square = 255`) | `484, 509` |
| **Face Buttons** | **$\triangle$ (`TRIANGLE`)** | **Tombol `Y`** (`XINPUT_GAMEPAD_Y`) | `button[3]` (`DIGITAL2`) `0x10` | `button[12]` (`press_triangle = 255`) | `481, 506` |
| **Shoulder** | **`L1`** | **`LB` (Left Bumper)** (`XINPUT_GAMEPAD_LEFT_SHOULDER`) | `button[3]` (`DIGITAL2`) `0x04` | `button[16]` (`press_l1 = 255`) | `479, 510` |
| **Shoulder** | **`R1`** | **`RB` (Right Bumper)** (`XINPUT_GAMEPAD_RIGHT_SHOULDER`) | `button[3]` (`DIGITAL2`) `0x08` | `button[17]` (`press_r1 = 255`) | `480, 511` |
| **Trigger** | **`L2`** | **`LT` (Left Trigger)** (`bLeftTrigger > 30`) | `button[3]` (`DIGITAL2`) `0x01` | `button[18]` (`press_l2 = bLeftTrigger` `0..255`, atau `255` jika bit digital aktif) | `477, 498, 1405, 1423` |
| **Trigger** | **`R2`** | **`RT` (Right Trigger)** (`bRightTrigger > 30`) | `button[3]` (`DIGITAL2`) `0x02` | `button[19]` (`press_r2 = bRightTrigger` `0..255`, atau `255` jika bit digital aktif) | `478, 499, 1406, 1424` |
| **Stick Click** | **`L3`** | **Left Thumbstick Click** (`XINPUT_GAMEPAD_LEFT_THUMB`) | `button[2]` (`DIGITAL1`) `0x02` | *(digital saja)* | `470` |
| **Stick Click** | **`R3`** | **Right Thumbstick Click** (`XINPUT_GAMEPAD_RIGHT_THUMB`) | `button[2]` (`DIGITAL1`) `0x04` | *(digital saja)* | `471` |
| **System** | **`START`** | **`Start` / `Menu`** (`XINPUT_GAMEPAD_START`) | `button[2]` (`DIGITAL1`) `0x08` | *(digital saja)* | `472` |
| **System** | **`SELECT`** | **`Back` / `View`** (`XINPUT_GAMEPAD_BACK`) | `button[2]` (`DIGITAL1`) `0x01` | *(digital saja)* | `469` |
| **Rumble** | **Motor Kecil & Besar** | `XInputSetState` (`wRightMotorSpeed`, `wLeftMotorSpeed`) | `cellPadSetActDirect` | `small_on ? 65535 : 0` $\to$ Right (hi-freq); `large * 257` $\to$ Left (lo-freq) | `188-192, 1860-1878` |

---

## 5. Panduan Khusus QTE `"L-down + R-down"` (`(L)↓ (R)↓`) di Episode 1

Pada fase Atmospheric Re-entry Episode 1 (~70 detik setelah menekan `START` di orbit Bumi), layar menampilkan ikon **`(L)↓` dan `(R)↓`**. Berikut cara melakukannya di masing-masing perangkat serta perbedaan datanya:

| Perangkat Input | Aksi Fisik untuk QTE `(L)↓ + (R)↓` | Nilai `CellPadData` yang Dikirim ke Game | Catatan Penting |
|---|---|---|---|
| **Gamepad XInput** *(Direkomendasikan)* | Tarik **Stik Kiri ke Bawah penuh** + **Stik Kanan ke Bawah penuh** bersamaan | `btn=(00,00:NONE)`<br>`L=(128,255)[+0.01,+1.00]`<br>`R=(128,255)[+0.01,+1.00]` | Menggerakkan `LY=255` dan `RY=255` secara murni **tanpa** menyalakan bit digital `D-Pad DOWN`. |
| **Keyboard PC** *(Hanya jika TIDAK ada gamepad XInput terpasang & jendela game sedang diklik/fokus)* | Tekan dan tahan **`Down Arrow` (Panah Bawah)** + **`K`** bersamaan | `btn=(40,00:DOWN)`<br>`L=(128,255)[+0.01,+1.00]`<br>`R=(128,255)[+0.01,+1.00]` | Karena `Down Arrow` di `pad_poll_keyboard()` (`cellPad.c:340,361-362`) memetakan D-Pad sekaligus Left Stick, tombol ini mengirim `LY=255` **bersama** bit digital `DOWN` (`0x40` di `button[2]`) dan `press_down=255`. |
| **Injeksi Otomasi (`PAD_STICK`)** | `PAD_STICK="128,255,128,255,190,260"` | `btn=(00,00:NONE)`<br>`L=(128,255)[+0.01,+1.00]`<br>`R=(128,255)[+0.01,+1.00]` | Menahan `LY=255, RY=255` secara statis dari `t=190s` s.d. `t=260s`. |

---

## 6. Telemetri `PAD_DIAG` untuk Tombol & Stik Fisik (`cellPad.c:790-902, 1467-1549`)

Saat dijalankan dengan `PAD_DIAG=1` (otomatis aktif di `08_SCRIPTS\test_qte_ep1.ps1`), `stderr.log` kini mencatat:
1. **`[PAD_DIAG][BACKEND]`**: Mencatat sumber input fisik aktif per port (`XInput` vs `Keyboard` vs `Disconn`).
2. **`[PAD_DIAG][FOCUS]`**: Mencatat perubahan status fokus jendela game (`window_focused=1` atau `0`) saat memakai fallback keyboard, sehingga langsung terlihat bila jendela belum ter-klik.
3. **`[PAD_DIAG][PHYS]`**: Mencatat **setiap kali tombol atau stik fisik ditekan (`ev=PRESS`), berubah (`ev=CHANGE`), ditahan setiap 500 ms (`ev=HOLD`), atau dilepas kembali ke netral (`ev=RELEASE`)**, lengkap dengan nama tombol, nilai mentah `u8 (0..255)`, dan nilai ternormalisasi `[-1.00..+1.00]`:
   ```text
   [PAD_DIAG][PHYS] t=12.340s flip=610 p=0 src=Keyboard ev=PRESS btn=(40,00:DOWN) L=(128,255)[0.01,1.00] R=(128,255)[0.01,1.00] trig=(0,0)
   [PAD_DIAG][PHYS] t=12.610s flip=625 p=0 src=Keyboard ev=RELEASE btn=(00,00:NONE) L=(128,128)[0.01,0.01] R=(128,128)[0.01,0.01] trig=(0,0)
   ```
4. **`[PAD_DIAG][GetData]`**: Mencatat paket akhir yang diserahkan ke guest (`src=xinput`, `src=kbd`, `src=PAD_STICK`, atau `src=PAD_SWEEP`).
