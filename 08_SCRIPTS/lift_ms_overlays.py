#!/usr/bin/env python3
"""lift_ms_overlays.py -- Extract and statically lift MultiStream SPU DSP PIC overlays from EBOOT.ELF.

MultiStream (spu_0000_at_017AA900) streams two DSP overlay payloads via MFC DMA
into local store at 0x37000..0x39EFF during audio processing:
  - image 30 (spu_ms_ovl_17DB480): mstream_dsp_i3dl2.pic (0x37000) + mstream_dsp_para_eq.pic (0x39800)
  - image 31 (spu_ms_ovl_17DDF00): mstream_dsp_filter.pic (0x37000)

Reads directly from EBOOT.ELF into a temporary directory that is discarded after
lifting so no raw game binary blobs remain in the workspace, then emits
<spu-dir>/ms_ovl_register.c registering both 16-byte overlay signatures via
spu_overlay_register_sig().
"""
import argparse
import json
import os
import re
import struct
import subprocess
import sys
import tempfile

_INC_RE = re.compile(r'#include\s+"(?:\.\./)+runtime/spu/([A-Za-z0-9_]+\.h)"')


def debase_includes(path: str) -> None:
    try:
        txt = open(path, encoding="utf-8", errors="ignore").read()
    except OSError:
        return
    new = _INC_RE.sub(r'#include "\1"', txt)
    if new != txt:
        open(path, "w", encoding="utf-8", newline="\n").write(new)


def va_to_file_offset(elf_buf: bytes, va: int) -> int:
    if elf_buf[:4] != b"\x7fELF":
        raise ValueError("EBOOT input is not a valid ELF")
    e_phoff = struct.unpack(">Q", elf_buf[0x20:0x28])[0]
    e_phentsize = struct.unpack(">H", elf_buf[0x36:0x38])[0]
    e_phnum = struct.unpack(">H", elf_buf[0x38:0x3A])[0]
    for i in range(e_phnum):
        po = e_phoff + i * e_phentsize
        p_type, _flags, p_offset, p_vaddr, _paddr, p_filesz = struct.unpack(
            ">IIQQQQ", elf_buf[po : po + 0x28]
        )
        if p_type == 1 and p_vaddr <= va < p_vaddr + p_filesz:
            return p_offset + (va - p_vaddr)
    raise ValueError(f"VA 0x{va:08X} not covered by any PT_LOAD file range")


def lift_overlay(
    lifter: str,
    tmpdir: str,
    spu_dir: str,
    name: str,
    prefix: str,
    base: int,
    payload: bytes,
    bounds: list[tuple[int, int]],
    extra_funcs: list[int] | None = None,
) -> bytes:
    bin_path = os.path.join(tmpdir, f"{name}.bin")
    fn_path = os.path.join(tmpdir, f"{name}.functions.json")
    rpt_path = os.path.join(tmpdir, f"{name}.report.json")
    outdir = os.path.join(spu_dir, name)
    os.makedirs(outdir, exist_ok=True)

    with open(bin_path, "wb") as f:
        f.write(payload)
    with open(fn_path, "w", encoding="utf-8") as f:
        json.dump([{"start": f"0x{s:X}", "end": f"0x{e:X}"} for s, e in bounds], f, indent=1)

    cmd = [
        sys.executable,
        lifter,
        bin_path,
        "--base",
        f"0x{base:X}",
        "--functions",
        fn_path,
        "--return-entries",
        "--merge-chunks",
        "--symbol-prefix",
        prefix,
        "--report",
        rpt_path,
        "-o",
        outdir,
    ]
    if extra_funcs:
        cmd.extend(["--extra-funcs", ",".join(f"0x{a:X}" for a in extra_funcs)])
    print(f"[lift_ms_overlays] LIFT {name} ({len(payload)} bytes, {len(bounds)} seeds)")
    res = subprocess.run(cmd)
    if res.returncode != 0:
        sys.exit(f"[lift_ms_overlays] spu_lifter FAILED for {name}")

    debase_includes(os.path.join(outdir, "spu_recomp.h"))
    debase_includes(os.path.join(outdir, "spu_recomp.c"))

    rpt = json.load(open(rpt_path, encoding="utf-8"))
    unsup = rpt.get("unsupported", [])
    if unsup:
        sys.exit(f"[lift_ms_overlays] ERROR: {name} had unsupported insns: {unsup[:5]}")
    print(f"[lift_ms_overlays]   {name}: {len(rpt.get('functions', []))} function(s), 0 unsupported")
    return payload[:16]


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--eboot",
        default=os.path.join(root, "00_GAME_DUMP", "extracted", "PS3_GAME", "USRDIR", "EBOOT.ELF"),
    )
    ap.add_argument(
        "--spu-dir",
        default=os.path.join(root, "03_ASURASWRATH_PORT", "spu"),
    )
    ap.add_argument(
        "--lifter",
        default=os.path.join(root, "02_REPOS", "ps3recomp", "tools", "spu_lifter.py"),
    )
    args = ap.parse_args()

    if not os.path.isfile(args.eboot):
        sys.exit(f"[lift_ms_overlays] EBOOT.ELF not found: {args.eboot}")

    eb = open(args.eboot, "rb").read()
    off_i3dl2 = va_to_file_offset(eb, 0x017DB480)
    off_paraeq = va_to_file_offset(eb, 0x017DE700)
    off_filter = va_to_file_offset(eb, 0x017DDF00)

    part_i3dl2 = eb[off_i3dl2 : off_i3dl2 + 0x26E8]
    part_paraeq = eb[off_paraeq : off_paraeq + 0x668]
    part_filter = eb[off_filter : off_filter + 0x4E0]

    # Sanity check against known EBOOT header bytes (prevents corrupting wrong ELF version).
    if part_i3dl2[:8] != bytes.fromhex("42636a0243df3682"):
        sys.exit("[lift_ms_overlays] Unexpected header at VA 0x017DB480 (expected mstream_dsp_i3dl2)")
    if part_paraeq[:8] != bytes.fromhex("43176e0242b08e82"):
        sys.exit("[lift_ms_overlays] Unexpected header at VA 0x017DE700 (expected mstream_dsp_para_eq)")
    if part_filter[:8] != bytes.fromhex("4305f80242c0f282"):
        sys.exit("[lift_ms_overlays] Unexpected header at VA 0x017DDF00 (expected mstream_dsp_filter)")

    ovl_17DB480 = part_i3dl2 + b"\x00" * (0x2800 - len(part_i3dl2)) + part_paraeq
    ovl_17DDF00 = part_filter

    bounds_17DB480 = [
        (0x37010, 0x37018),
        (0x37018, 0x37078),
        (0x37078, 0x37108),
        (0x37108, 0x373A0),
        (0x373A0, 0x37478),
        (0x37478, 0x379F8),
        (0x379F8, 0x37C20),
        (0x37C20, 0x396E8),
        (0x39810, 0x39818),
        (0x39818, 0x39878),
        (0x39878, 0x39B50),
        (0x39B50, 0x39E68),
    ]
    bounds_17DDF00 = [
        (0x37010, 0x37070),
        (0x37070, 0x37344),
        (0x37344, 0x37348),
        (0x37348, 0x374E0),
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        sig_30 = lift_overlay(
            args.lifter, tmpdir, args.spu_dir,
            "spu_ms_ovl_17DB480", "spu_ms_ovl_17DB480_",
            0x37000, ovl_17DB480, bounds_17DB480,
            extra_funcs=[
                0x380E0, 0x387C0, 0x388DC,
                0x395FC, 0x39D38, 0x39D40, 0x39D74, 0x39E30, 0x39E3C,
            ],
        )
        sig_31 = lift_overlay(
            args.lifter, tmpdir, args.spu_dir,
            "spu_ms_ovl_17DDF00", "spu_ms_ovl_17DDF00_",
            0x37000, ovl_17DDF00, bounds_17DDF00,
        )

    def fmt_sig(b: bytes) -> str:
        return ", ".join(f"0x{x:02X}" for x in b)

    reg_path = os.path.join(args.spu_dir, "ms_ovl_register.c")
    reg_src = f"""/* ms_ovl_register.c -- GENERATED by 08_SCRIPTS/lift_ms_overlays.py.
 * Registers the lifted MultiStream DSP PIC overlays streamed into LS 0x37000
 * so SPU execution stays compiled instead of dropping to spu_interp. */
#include <stdint.h>

extern void spu_begin_image(int image_id);
extern void spu_overlay_register_sig(const uint8_t sig[16], int image_id);

extern void spu_ms_ovl_17DB480_spu_recomp_register(void);
extern void spu_ms_ovl_17DDF00_spu_recomp_register(void);

void asuraswrath_ms_ovl_register_all(void)
{{
    static const uint8_t sig_17DB480[16] = {{ {fmt_sig(sig_30)} }};
    static const uint8_t sig_17DDF00[16] = {{ {fmt_sig(sig_31)} }};
    spu_begin_image(30); spu_ms_ovl_17DB480_spu_recomp_register();
    spu_overlay_register_sig(sig_17DB480, 30);
    spu_begin_image(31); spu_ms_ovl_17DDF00_spu_recomp_register();
    spu_overlay_register_sig(sig_17DDF00, 31);
    spu_begin_image(0);
}}

__attribute__((constructor)) static void asuraswrath_ms_ovl_register_ctor(void)
{{
    asuraswrath_ms_ovl_register_all();
}}
"""
    with open(reg_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(reg_src)
    print(f"[lift_ms_overlays] wrote {reg_path}")


if __name__ == "__main__":
    main()

