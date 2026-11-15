# [DRAFT — DO NOT SUBMIT AUTOMATICALLY] Upstream PR: `rsx_vertex_fetch`: return early after decoding `CMP` (`type == 6`) attributes

- **Target Repository**: `sp00nznet/ps3recomp` (`main`, base commit `de4f090328ea08bef6b2f15caec0b85e343a7ece`)
- **Patch File**: `07_DOCS/upstream/0001-rsx_vertex_fetch-return-early-for-CMP-attributes.patch`
- **Local Branch Commit**: `3a887069` (`asuras-wrath-local`)
- **Unit Test**: `libs/video/tests/test_vertex_fetch_cmp.c` (`test_vertex_fetch_cmp: 0 failure(s)`, log: `05_LOGS/test_vertex_fetch_cmp.log`)

---

## PR Title
`rsx_vertex_fetch: return early after decoding CMP (type == 6) attributes`

## PR Description

### Summary
In `rsx_decode_vertex_attrib()` (`libs/video/rsx_vertex_fetch.c`), `RSX_VERTEX_ATTR_TYPE_CMP` (`type == 6`, R11G11B10 signed normalized packed normal/tangent in a single big-endian `u32`) decoded `out4[0..3]` inside the `if (type == 6 && size >= 1)` block, **but lacked a `return;` statement at the end of that block**.

As a result, execution fell through into the `for (u32 c = 0; c < count; c++)` per-component loop (`count = size`, e.g., `size == 4` on Unreal Engine 3 skeletal/static meshes):
1. Within the loop, `switch (type)` had no `case 6:`, hitting `default: val = 0.0f;` and overwriting `out4[0..count-1]` with `0.0f`.
2. Immediately after the loop, `if (count < 4) out4[3] = 1.0f;` or `count == 4` left `out4` as `(0.0f, 0.0f, 0.0f, 0.0f)` (or `(0.0f, 0.0f, 0.0f, 1.0f)` when `size < 4`).

By contrast, both sibling decoders in `libs/video/` already returned or broke out properly after decoding `type == 6`:
- `libs/video/rsx_live_draw.c:5744` (`decode_vertex_attrib`): ends its `if (type == 6 && size >= 1)` block with `return;`.
- `libs/video/rsx_vertex_compact.c:84`: handles `case 6:` inside the `switch` and terminates with `break;`.

### Context & Prior PRs
- **PR #529** (`36b1ea43`, Ryan Bagas — *"fix(rsx): implement missing vertex attribute types CMP (6) and UB256 (7)"*): Added `type == 6` (`CMP`) decoding to `rsx_d3d12_backend.c` (later moved to `rsx_live_draw.c` and `rsx_vertex_fetch.c`), using `return;` in `decode_vertex_attrib()`, whereas `rsx_decode_vertex_attrib()` in `rsx_vertex_fetch.c` omitted the `return;`.
- **PR #597** (`b3150f3c`, DriifterSelf — *"Fix vertex attribute decoding: per-component loop for CMP/F16, fix UB256 normalized"*): Updated `CMP` bitfield extraction (`11-11-10` two's complement signed normalized), while `rsx_decode_vertex_attrib()` in `rsx_vertex_fetch.c` still lacked the `return;` before the per-component `for (u32 c = 0; c < count; c++)` loop.

### Real-Game Impact (Asura's Wrath — `BLUS30721`, Unreal Engine 3)
Unreal Engine 3 encodes `TangentX` (`ATTR1`) and `TangentZ` (`ATTR2`) on all skeletal and static meshes as `T6x4` (`type = 6` `CMP`, `size = 4`).
- In `BLUS30721`, the UE3 GPU skinning & mesh vertex shaders (e.g., `vs=26`, `vp_hash=0xD8768708`, 134 instructions) compute:
  ```hlsl
  r1.xyz = v[2].xyz * 2.0 - 1.0;
  r1.w   = dot(r1.xyz, r1.xyz);
  r1.w   = rsqrt(r1.w); // rsqrt(0.0) -> +Inf when v[2] was zeroed by the fallthrough
  r1.xyz = r1.xyz * r1.www; // 0.0 * +Inf -> NaN
  ```
- Because `v[1]` and `v[2]` were overwritten with `(0, 0, 0, 0)` on every vertex fetched through `rsx_vertex_fetch.c`, `rsqrt(0.0) * 0.0` produced `NaN` in the tangent-basis calculation, contaminating the vertex position/lighting registers and causing the D3D12 rasterizer to silently discard all triangles of every mesh with `T6x4` tangents (78 draws per frame at Episode 1 `t025s`, ~171k indices).
- Adding `return;` at the end of `if (type == 6 && size >= 1)` in `rsx_decode_vertex_attrib()` restores all `T6x4` meshes in *Asura's Wrath* (`BLUS30721`).

### Unit Test
Added `libs/video/tests/test_vertex_fetch_cmp.c` (patterned after `test_vertex_fetch_plan.c` and `test_vertex_current_color.c`) covering:
1. Direct `rsx_decode_vertex_attrib()` decoding of `type=6, size=4` (`+X,+Y,+Z` = `0x1FF7FE00`, `-X,-Y,-Z` = `0x20080100`, and zero = `0x00000000`), verifying `out[0..2]` are preserved and not overwritten by the `size=4` loop.
2. End-to-end `rsx_build_vertex_fetch_plan()` + `rsx_execute_vertex_fetch_plan()` with interleaved `FLOAT3` position (`ATTR0`) + `CMP` `T6x4` `TangentX`/`TangentZ` (`ATTR1`/`ATTR2`, stride 20), verifying non-zero decoded tangents and `out[3] == 1.0f`.
