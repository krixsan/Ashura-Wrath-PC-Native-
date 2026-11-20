# Progress & Technical Milestone Log — Asura's Wrath (`BLUS30721`)

Detailed summary of completed engineering milestones and verified fixes (documentation-only, without source code).

---

## Milestone History

### Tier 0 — Decryption, Lifting & Boot (`TC-01`, `TC-02` = PASS)
- **Dump & Decryption Verified:** PS3 US Base (`BLUS30721`, `APP_VER=01.00`, `12 GB` disc layout) decrypted cleanly from `EBOOT.BIN` (`key_rev 0x0016`) to a **`27.1 MB` `EBOOT.ELF`** containing **`30,350`** unique PPU functions and **`27`** SPU ELF images (`1.52 MB`).
- **Media Independence Confirmed:** Import analysis showed **`0` imports** to `cellVdec` / `cellPamf` / `cellDmux` / `cellAdec` because *Asura's Wrath* handles `.BIK` playback internally via Bink Video.
- **Post-Logo Black Screen Solved (`SPURS Job2`):** Added deterministic extraction & constructor registration (`image_id 40..45`) for all **`6` embedded SPURS `Job2` workloads** (`ShaderPatching`, `WriteFence`, `Job3`, `PhysX1`, `Fluid1`, `Fluid2`) plus **`2` multistream overlays**, clearing Capcom / CyberConnect2 / UE3 / SpeedTree logos straight to the Title Screen (`40.2s`–`43.2s`) under strict `SPU_MISS_FATAL=1`.

### Tier 1 — Menu Navigation & Save Persistence (`TC-03`, `TC-05` = PASS)
- **`NV0039` (`m2mf`) 2D-to-3D Routing:** Fixed linear DMA copy and `subch 1` routing between 2D Bink/menu passes and 3D RSX contexts without breaking `NV4097_SET_COLOR_MASK`.
- **`TITLEMENU_BG00.BIK` & Save Round-Trip:** Verified full menu navigation (`START` -> `NEW GAME` -> `EASY`), writing **`81,920`-byte `PAYLOAD`** (`BLUS30721-BCSAVEDATA`) via `cellSaveData`, quitting cleanly (`WM_CLOSE` exit `0`), and reloading via `AutoLoad2` (`"Load successful."`), unlocking the **`EPISODE MENU`** option on reboot.

### Tier 2 — Episode 1 Playability & Rendering Fixes (`TC-04`, `TC-08`, `TC-09` = PASS)
- **Fixed Skeletal 3D Geometry Collapse (`CELL_GCM_VERTEX_CMP` `T6x1`):** Resolved an early-fallthrough bug in vertex attribute decoding where UE3's `CMP` (`11-11-10`, `size=1`) lost `Y` & `Z` coordinates and collapsed rigged models into flat spikes (`T6x_a0_zero` dropped from `2/3` & `25/43` down to `0/3` & `0/86`). Episode 1 guest render framerate improved from `31.04 FPS` to **`35.43 FPS`** (`+4.39 FPS`), reaching **`39.77 FPS`** overall in manual gameplay sessions.
- **Passed QTE `L↓ + R↓` (`Down Arrow + K`):** Verified with real physical input at `t=202.5s..207.3s`, triggering level streaming (`BC-S000_L01_PDE_02.XXX`, `BC-S000_STE_A030.XXX`), cloud credit sequences, `"Gohma Carrier"` water scene, and Phase 2 Earth-orbit rail-shooter gameplay (`0` SPU dispatch miss, `0` hang).
- **Direct3D 12 Disk Shader Cache & Unit Tests:** Cold-boot shaders compile cleanly (`rejects=0`) and warm boots hit cache with `0` misses; Windows runtime CTest suite passes **`30/30` tests**; two consecutive full relifts produce **`251` identical files** (`0` mismatches).
- **Partial Occlusion Query Recovery (`NV4097_GET_REPORT`):** Fixed local VRAM writeback on DMA `0xFEED0000` so UE3 stops culling 129–208 armada/Gohma meshes during Earth-orbit combat (material/particle visual parity remains open in [`docs/KNOWN_ISSUES.md`](docs/KNOWN_ISSUES.md)).
