# TC-07 — Perbandingan Frame Manual vs Golden RPCS3 (`BLUS30721`)

**Status**: `BELUM LENGKAP (Menunggu Golden Frame RPCS3 BLUS30721)`  
**Build lokal yang diuji**: `04_BUILD\AsurasWrathRecomp.exe` (`sha256: d66ed020ac20c376b450123240d81f802b138e010f485da4fecf07639770a443`, `APP_VER=01.00` Base `EBOOT.ELF`)  
**Sumber tangkapan lokal (`1280x720`, `SPU_MISS_FATAL=1`)**:
- Sesi Tier 2 (`330.11s`): `05_LOGS\e2e_tier2_20261115_061452\`
- Sesi `TC-05` post-save auto-load: `05_LOGS\e2e_tc05_20261115_062608\`

> **Catatan Aturan #1 & #7**: RPCS3 maupun golden frame referensi `BLUS30721` tidak ditemukan di sistem lokal. Kolom golden dibiarkan kosong hingga artefak golden eksternal tersedia. Tabel di bawah mendokumentasikan observasi visual terverifikasi pada frame lokal saat ini.

## Tabel Perbandingan Manual Momen-per-Momen

| # | Momen Game | Bukti Frame Lokal (`1280x720`) | Observasi Render Lokal (D3D12) | Golden Frame RPCS3 (`BLUS30721`) | Selisih Visual / PSNR / Status |
|---|---|---|---|---|---|
| 1 | Title Screen (`TITLEMENU_BG00.BIK`) | `05_LOGS\e2e_tier2_20261115_061452\stage_01_title.png` | Logo *ASURA'S WRATH*, teks `PRESS START`, hak cipta `@CAPCOM CO., LTD. 2012 ALL RIGHTS RESERVED.`, dan latar video Bink ter-render jelas. | *Menunggu supply user* | `PENDING GOLDEN` |
| 2 | Dialog Auto-Load (`cellSaveData`) | `05_LOGS\e2e_tc05_20261115_062608\stage_02_load_dialog.png` | Teks `Load successful.` dan tombol `(×) Close` terbaca; teramati artefak minor alpha/blend piksel putih di tepi bawah behind-overlay di belakang bar bantuan. | *Menunggu supply user* | `PENDING GOLDEN` *(catat artefak minor tepi bawah dialog)* |
| 3 | Main Menu (Pasca-Save Tier 2) | `05_LOGS\e2e_tc05_20261115_062608\stage_03_main_menu.png` | Menu `NEW GAME`, `EPISODE MENU` (terbuka pasca-save), `OPTIONS`, `! EXTRAS`, serta bar navigasi `(D-pad) Select (×) OK (○) Back` tampil lengkap di atas render 3D menu. | *Menunggu supply user* | `PENDING GOLDEN` |
| 4 | Episode 1 Orbit Title (`BC-S000_L01_PDE_01.XXX`) | `05_LOGS\e2e_tier2_20261115_061452\stage_08_ep1_press_start.png` | Lengkungan Bumi 3D, awan atmosfer, bidang bintang, logo *ASURA'S WRATH*, dan banner `PRESS START` ter-render tajam dalam letterbox `16:9`. | *Menunggu supply user* | `PENDING GOLDEN` |
| 5 | Episode 1 Orbital Combat (`(□) Rapid Fire`) | `05_LOGS\e2e_tier2_20261115_061452\ep1_t040s.png` | Partikel merah/abu, retikel bidik segitiga hijau/merah & HUD kunci target tengah, teks kredit pembuka (`Storyboard Artists` dkk.), dan efek ledakan tampil aktif. | *Menunggu supply user* | `PENDING GOLDEN` |
| 6 | Episode 1 Atmospheric Re-entry QTE (`L↓ + R↓`) | `05_LOGS\e2e_tier2_20261115_061452\ep1_t070s.png` *(sebelum fix `CMP`)* → `05_LOGS\draw_census_20261115_111217\qte_t070s.png` & `stage_08_ep1_end.png` *(sesudah fix `CMP`)* | **[Koreksi 2026-11-15]**: Sensus draw (`05_LOGS\draw_census_20261115_110049\census_t070s.csv`) membuktikan bahwa pada tangkapan lama (`ep1_t070s.png` / `qte_t070s.png` sebelum fix), vertex `CMP` (`a0:T6x1s32@L`, `size=1`) **sebenarnya kolaps** ke `Y=0, Z=0` (`pos0=X;0.000;0.000;1.000`, `T6x_a0_zero=25/43`) menjadi pita berduri pipih. Pasca-perbaikan `rsx_vertex_fetch.c:113-116` (`05_LOGS\draw_census_20261115_111217\census_t070s.csv`, `T6x_a0_zero=0/86`), geometri 3D makhluk berduri bertentakel di kiri dan objek bersayap di kanan ter-render utuh; keberadaan/posisi karakter lain terhadap kamera belum disimpulkan sebelum golden RPCS3 tersedia. Gameplay masih tertahan di prompt `(L)↓ (R)↓`. Riwayat catatan lama: ~~Model 3D Asura dengan pencahayaan api & bloom atmosfer serta ikon prompt QTE `(L)↓ (R)↓` ter-render; gameplay tertahan di prompt ini (lihat `KNOWN_ISSUES.md`).~~ | *Menunggu supply user* | `PENDING GOLDEN` |

## Cara Melengkapi `TC-07`

1. Ambil screenshot RPCS3 menggunakan game **BLUS30721** (`APP_VER=01.00`, resolusi render native 720p) pada 6 momen di tabel atas dan simpan ke `05_LOGS\golden\rpcs3_blus30721\`.
2. Bandingkan secara visual dan/atau hitung selisih piksel (`SSIM`/`PSNR`/`MAE` dengan masking HUD bila kredit dinamis berbeda frame).
3. Catat hasil toleransi pada kolom `Golden Frame RPCS3` dan `Selisih Visual / PSNR / Status`, lalu perbarui status `TC-07` di PRD.

