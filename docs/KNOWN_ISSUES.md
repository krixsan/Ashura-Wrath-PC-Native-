# Known Issues & Open Findings — Asura's Wrath (`BLUS30721`)

Current open bugs, visual discrepancies, and uncompleted test cases (updated cleanly without source code).

---

## 1. Open Technical & Visual Issues

1. **Episode 1 Earth-Orbit Armada & Gohma Material/Particle Parity (`vs=37` — Unresolved)**
   - **Symptom:** During Episode 1 Earth-orbit rail-shooter sequences (`t025s`, `t040s`, `t055s`), dense red target-reticle/billboard particles and overly bright or washed-out armada ship & Gohma surfaces still differ from reference PS3 footage.
   - **Verified Diagnostics So Far:**
     - `NV4097_GET_REPORT` local VRAM fix successfully prevented UE3 from occlusion-culling `129–208` ship/Gohma draw calls.
     - Draw census verified vertex attribute `a4=(1,1,1,1)` already reaches `vs=37` (`vp_hash=0xBB41C22D`), ruling out an unpopulated `stride=0` color attribute as the root cause.
   - **Next Step:** Run draw census capture after orbit stabilization and correlate `vs=37` draws directly with active fragment shaders and bound textures (without applying depth/color hacks).

2. **`TC-07` Secondary Visual Parity Candidates (`P1-V1`, `P1-V2`, `P1-V3` & Auto-Load Edge)**
   - **`P1-V1` (Post-QTE Water Distortion — `"Gohma Carrier"`):** Refraction offset pass (`rt=0x0D32E000`, `id=280/582` -> `id=281/583`) produces noticeable wavy water surface distortion; awaits RPCS3 golden frame check for exact UV offset scale verification.
   - **`P1-V2` (Upper-Right QTE Bright Cone/Triangle):** Additive beam/fin meshes (`id=262/564`, `269..271/571..573`) during atmospheric re-entry QTE await comparison against RPCS3 to confirm whether geometry/blend matches console behavior.
   - **`P1-V3` (Thin `1–2 px` Left Border Line at `x=0`):** Quarter-resolution `322x182` downsample guard-band (`pos0.x = -0.994` vs `-1.000`) leaves a subtle 1–2 px dark edge when resolved to `1280x720`.
   - **Auto-Load Dialog Edge:** Minor white alpha-blend pixel artifact visible along the bottom edge behind the `Load successful.` overlay bar.

3. **Episodes 2, 3 & Full Campaign Untested**
   - Binary inspection of `BLUS30721-BCSAVEDATA/PAYLOAD` (`StoryClearFlgs`) confirms `Ep 1` (`BC-S000`) is currently `ClearFlg=2` (*in-progress*), while `Ep 2` (`BC-S010`) and `Ep 3` (`BC-S020`) remain `ClearFlg=0` (*locked*) until Episode 1's final boss (Wyzen/Vlitra) is defeated and *Episode 1 Clear Save* (`ClearFlg=1`) is stored.

4. **`TC-06` Continuous 30-Minute Soak Test Pending**
   - Longest continuous run under strict `SPU_MISS_FATAL=1` reached **`330.11s` (~5.5 minutes, `660` frames)** with stable object counts (`objs=103051`) and zero crashes/hangs. A full `1800s` (30-minute) soak test remains pending.

5. **`Update v1.02` PKG Not Merged & No Standalone Binary Release**
   - Current lifted build targets US Base `APP_VER=01.00` (`Update v1.02.pkg` / `UP0102-BLUS30721_00-PATCH02000000000` has not been merged yet).
   - Output binary `AsurasWrathRecomp.exe` (`423,291,392` bytes / `403.7 MB`) statically embeds lifted game code for local development only—there is no no-game-code standalone launcher release yet.

---

## 2. Harmless Non-Fatal Logs Confirmed Normal
- **`/dev_flash/sys/external/flashMP3.pic` open fail:** Logged once at boot; Bink video and game audio work normally.
- **`cellNetCtl` `NOT_INITIALIZED` (offline mode):** Expected because PSN/online services are intentionally stubbed offline.
- **`spujob_42E1FC8CEE0BE246` (`ShaderPatching`) `25 .word` constants:** Tail constant data embedded in SPU blob; all `6` SPURS `Job2` modules have `0` unsupported SPU instructions.
- **`FParticleSpriteSubUVVertex` `pos0=(0,0,0)` on `t025s`:** Audited and proven normal Unreal Engine 3 local-space particle billboard behavior (`bUseLocalSpace=TRUE`, corner offsets expanded via `ATTR8`/`ATTR5` in vertex shaders `vs=40` / `vs=31`).
