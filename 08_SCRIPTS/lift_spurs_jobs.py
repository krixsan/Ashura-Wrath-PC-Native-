#!/usr/bin/env python3
"""
lift_spurs_jobs.py -- Extract & lift Asura's Wrath embedded SPURS job2 binaries.

SPURS job2 binaries in EBOOT.ELF are raw PIC SPU blobs (no ELF header),
not standalone sys_spu_image ELFs, so tools/extract_spu_images.py skips them.
This script extracts each embedded job directly from EBOOT.ELF into a temporary
directory, wraps it as an SPU ELF at base=0, entry=0x10 via ps3recomp's
wrap_spu_elf, lifts it into 03_ASURASWRATH_PORT/spu/spujob_<FP>/, and generates
spu/jobmods_register.c so every SPURS job runs as compiled native C code
instead of dropping to the slow SPU interpreter.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

FNV_OFFSET_BASIS = 1469598103934665603
FNV_PRIME = 1099511628211

# (name, eboot_file_offset, primary_size, alias_sizes)
# Sizes reflect what PPU runtime stores into CellSpursJobHeader::sizeBinary
# ((raw_size + 15) >> 4 << 4, matching spu_workload_dispatch_job's hash input).
SPURS_JOBS: list[tuple[str, int, int, tuple[int, ...]]] = [
    ("ShaderPatching", 0x179F000, 0x8780, ()),
    ("WriteFence",     0x17A7780, 0x0210, ()),
    ("Job3",           0x17A7A00, 0x2F00, (0x11D0,)),
    ("PhysX1",         0x17D7700, 0x0890, ()),
    ("Fluid1",         0x1920580, 0x0380, ()),
    ("Fluid2",         0x1920900, 0x0410, ()),
]


def fnv1a_64(data: bytes) -> int:
    h = FNV_OFFSET_BASIS
    for b in data:
        h ^= b
        h = (h * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF
    return h


def debase_includes(path: Path) -> None:
    """Strip deep relative ../../runtime/spu/ prefixes emitted by spu_lifter."""
    text = path.read_text(encoding="utf-8", errors="replace")
    fixed = re.sub(r'#include "(?:\.\./)+runtime/spu/([A-Za-z0-9_]+\.h)"', r'#include "\1"', text)
    if fixed != text:
        path.write_text(fixed, encoding="utf-8")


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description="Lift Asura's Wrath SPURS job2 binaries.")
    ap.add_argument(
        "--eboot",
        type=Path,
        default=repo_root / "00_GAME_DUMP" / "extracted" / "PS3_GAME" / "USRDIR" / "EBOOT.ELF",
    )
    ap.add_argument(
        "--spu-dir",
        type=Path,
        default=repo_root / "03_ASURASWRATH_PORT" / "spu",
    )
    ap.add_argument(
        "--lifter",
        type=Path,
        default=repo_root / "02_REPOS" / "ps3recomp" / "tools" / "spu_lifter.py",
    )
    ap.add_argument("--base-image-id", type=int, default=40)
    args = ap.parse_args()

    if not args.eboot.is_file():
        print(f"ERROR: EBOOT.ELF not found: {args.eboot}", file=sys.stderr)
        return 1
    if not args.lifter.is_file():
        print(f"ERROR: spu_lifter.py not found: {args.lifter}", file=sys.stderr)
        return 1

    tools_dir = args.lifter.parent
    sys.path.insert(0, str(tools_dir))
    from wrap_spu_elf import wrap  # noqa: E402

    eboot_bytes = args.eboot.read_bytes()
    args.spu_dir.mkdir(parents=True, exist_ok=True)

    registered: list[tuple[str, str, int, list[int]]] = []

    with tempfile.TemporaryDirectory(prefix="aw_spurs_") as tmpdir_str:
        tmpdir = Path(tmpdir_str)
        for idx, (label, off, size, alias_sizes) in enumerate(SPURS_JOBS):
            blob = eboot_bytes[off : off + size]
            if len(blob) != size:
                print(f"ERROR: {label} truncated at 0x{off:X}", file=sys.stderr)
                return 1
            if blob[0x10:0x16] != bytes.fromhex("440128503200"):
                print(
                    f"ERROR: {label} @ 0x{off:X} unexpected +0x10 prologue: {blob[0x10:0x18].hex()}",
                    file=sys.stderr,
                )
                return 1

            fp = fnv1a_64(blob)
            fp_hex = f"{fp:016X}"
            prefix = f"spujob_{fp_hex}"
            out_dir = args.spu_dir / prefix
            if out_dir.exists():
                shutil.rmtree(out_dir)
            out_dir.mkdir(parents=True, exist_ok=True)

            elf_path = tmpdir / f"{prefix}.elf"
            rpt_path = tmpdir / f"{prefix}_report.json"
            elf_path.write_bytes(wrap(blob, base=0, entry=0x10))

            cmd = [
                sys.executable,
                str(args.lifter),
                "--auto-functions",
                str(elf_path),
                "--base",
                "0",
                "--return-entries",
                "--merge-chunks",
                "--symbol-prefix",
                f"{prefix}_",
                "--report",
                str(rpt_path),
                "-o",
                str(out_dir),
            ]
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode != 0:
                print(f"ERROR lifting {label} ({prefix}):\n{res.stderr}", file=sys.stderr)
                return 1

            for fname in ("spu_recomp.h", "spu_recomp.c"):
                p = out_dir / fname
                if not p.is_file():
                    print(f"ERROR: missing {p}", file=sys.stderr)
                    return 1
                debase_includes(p)

            hdr_text = (out_dir / "spu_recomp.h").read_text(encoding="utf-8", errors="replace")
            entry_sym = f"{prefix}_spu_func_00000010"
            if entry_sym not in hdr_text:
                print(f"ERROR: entry symbol {entry_sym} missing from {out_dir / 'spu_recomp.h'}", file=sys.stderr)
                return 1

            rpt = json.loads(rpt_path.read_text(encoding="utf-8")) if rpt_path.is_file() else {}
            real_unsup = {k: v for k, v in (rpt.get("unsupported") or {}).items() if k != ".word"}
            if real_unsup:
                print(f"ERROR: {label} ({prefix}) has unsupported SPU opcodes: {real_unsup}", file=sys.stderr)
                return 1

            fps = [fp]
            for asz in alias_sizes:
                fps.append(fnv1a_64(blob[:asz]))
            image_id = args.base_image_id + idx
            registered.append((label, prefix, image_id, fps))
            print(f"  Lifted {label:15s} -> {prefix} (image_id={image_id}, size=0x{size:X}, fp=0x{fp_hex})")

    lines = [
        "/* jobmods_register.c -- GENERATED by 08_SCRIPTS/lift_spurs_jobs.py.",
        " * Registers all embedded SPURS job2 binaries lifted into spu/spujob_<FP>/",
        " * so CellSpurs jobs run as compiled C rather than hitting spu_interp. */",
        '#include "spu_workload.h"',
        "",
        "extern void spu_begin_image(int image_id);",
        "void asuraswrath_jobmods_register_all(void);",
        "",
    ]
    for label, prefix, _, _ in registered:
        lines.extend([
            f"/* {label} */",
            f"extern void {prefix}_spu_func_00000010(spu_context* ctx);",
            f"extern void {prefix}_spu_recomp_register(void);",
        ])
    lines.extend([
        "",
        "void asuraswrath_jobmods_register_all(void)",
        "{",
    ])
    for label, prefix, image_id, fps in registered:
        lines.append(f"    /* {label} */")
        lines.append(f"    spu_begin_image({image_id});")
        lines.append(f"    {prefix}_spu_recomp_register();")
        for fp in fps:
            lines.extend([
                f"    spu_workload_register_img(0x{fp:016X}ULL,",
                f"                              {prefix}_spu_func_00000010,",
                f"                              {image_id},",
                f'                              "{prefix}");',
            ])
        lines.append("")
    lines.extend([
        "    spu_begin_image(0);",
        "}",
        "",
        "__attribute__((constructor)) static void asuraswrath_jobmods_register_ctor(void)",
        "{",
        "    asuraswrath_jobmods_register_all();",
        "}",
        "",
    ])

    reg_path = args.spu_dir / "jobmods_register.c"
    new_bytes = ("\n".join(lines)).encode("utf-8")
    if reg_path.is_file():
        old_bytes = reg_path.read_bytes()
        bak_path = reg_path.with_name("jobmods_register.c.bak")
        if old_bytes != new_bytes or not bak_path.is_file():
            shutil.copy2(reg_path, bak_path)
    reg_path.write_bytes(new_bytes)

    # Touch CMakeLists.txt so CMake re-globs newly generated spujob_* folders.
    cmake_lists = args.spu_dir.parent / "CMakeLists.txt"
    if cmake_lists.is_file():
        os.utime(cmake_lists, None)

    print(f"Wrote {reg_path} ({len(registered)} SPURS job images)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

