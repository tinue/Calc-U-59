#!/usr/bin/env python3
"""TI-59 ROM Disassembler — Phase 1

Reads roms/rom-59.hex, decodes every 13-bit opcode, and writes refs/rom.asm.

Decode logic follows the TMC0501 instruction set encoding (US Patents 3,900,722 and 4,153,937).
See planning/DISASM-PLAN.md for the full reverse-engineering roadmap.

Mnemonic names are defined in tools/mnemonics.tsv (single source of truth).
Run with --emit-cpp to print C++ lookup arrays for TMC0501.cpp.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


# ── Load mnemonics.tsv ────────────────────────────────────────────────────────

def _load_tsv(path: Path) -> dict[str, dict[int, str]]:
    """Parse mnemonics.tsv into {CATEGORY: {hex_index: template_string}}."""
    tables: dict[str, dict[int, str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t", 2)
        if len(parts) != 3:
            continue
        cat, idx_str, mnem = parts
        tables.setdefault(cat, {})[int(idx_str, 16)] = mnem
    return tables


_TSV = _load_tsv(ROOT / "tools" / "mnemonics.tsv")

_MASK   = [_TSV["MASK"][i]   for i in range(16)]
_N      = [_TSV["N"][i]      for i in range(16)]
_DST    = [_TSV["DST"][i]    for i in range(8)]
_BRANCH = [_TSV["BRANCH"][i] for i in range(2)]
_FLAG   = [_TSV["FLAG"][i]   for i in range(16)]
_CTRL   = _TSV["CTRL"]   # sparse dict (not all indices present)
_PRN    = _TSV["PRN"]
_LIB    = _TSV["LIB"]
_MEM    = _TSV["MEM"]


# ── ALU assignment notation ───────────────────────────────────────────────────
#
# Each entry is a format string for the assignment-style notation used in the
# original TI58C ROM listing (e.g. "C=C-B ALL", "IO=C+0 ALL", "B=SLB MANT").
#
# Placeholders: {d}=destination, {f}=field, {n}=immediate constant,
#               {s}=primary source, {s2}=secondary source.
#
# Indices 24-31 (0x18-0x1F) are handled by the special-case block below
# because their source operands vary by field mask rather than by entry index.

_ALU_FMT = [
    "{d}={s}+{n} {f}",     # 00  ADD dst, A, #n
    "{d}={s}-{n} {f}",     # 01  SUB dst, A, #n
    "{d}={s} {f}",         # 02  MOV dst, B
    "{d}=-{s} {f}",        # 03  NEG dst, B
    "{d}={s}+{n} {f}",     # 04  ADD dst, C, #n
    "{d}={s}-{n} {f}",     # 05  SUB dst, C, #n
    "{d}={s} {f}",         # 06  MOV dst, D
    "{d}=-{s} {f}",        # 07  NEG dst, D
    "{d}=SL{s} {f}",       # 08  SHL dst, by A
    "{d}=SR{s} {f}",       # 09  SHR dst, by A
    "{d}=SL{s} {f}",       # 0A  SHL dst, by B
    "{d}=SR{s} {f}",       # 0B  SHR dst, by B
    "{d}=SL{s} {f}",       # 0C  SHL dst, by C
    "{d}=SR{s} {f}",       # 0D  SHR dst, by C
    "{d}=SL{s} {f}",       # 0E  SHL dst, by D
    "{d}=SR{s} {f}",       # 0F  SHR dst, by D
    "{d}={s}+{s2} {f}",    # 10  ADD dst, A, B
    "{d}={s}-{s2} {f}",    # 11  SUB dst, A, B
    "{d}={s}+{s2} {f}",    # 12  ADD dst, C, B
    "{d}={s}-{s2} {f}",    # 13  SUB dst, C, B
    "{d}={s}+{s2} {f}",    # 14  ADD dst, C, D
    "{d}={s}-{s2} {f}",    # 15  SUB dst, C, D
    "{d}={s}+{s2} {f}",    # 16  ADD dst, A, D
    "{d}={s}-{s2} {f}",    # 17  SUB dst, A, D
]

# Primary source register per ALU entry index
_ALU_SRC1 = [
    "A","A","B","B","C","C","D","D",
    "A","A","B","B","C","C","D","D",
    "A","A","C","C","C","C","A","A",
]

# Secondary source register for two-register entries (indices 16-23)
_ALU_SRC2 = [
    "","","","","","","","",
    "","","","","","","","",
    "B","B","B","B","D","D","D","D",
]


# ── Disassembler ─────────────────────────────────────────────────────────────

def disasm(addr: int, opcode: int, model: str = "59") -> str:
    """Disassemble one 13-bit opcode at address `addr`."""

    # ── Branch  (bit 12 set) ────────────────────────────────────────────────
    if opcode & 0x1000:
        offset = (opcode >> 1) & 0x03FF
        dest   = addr - offset if (opcode & 1) else addr + offset
        cond   = 1 if (opcode & 0x0800) else 0
        s = f"{_BRANCH[cond]} {dest:04X}"
        if (opcode & 0x17FF) == 0x1002:
            s += " ; clear COND"
        return s

    hi = (opcode >> 8) & 0x0F

    # ── Flag operations  (hi = 0x0) ─────────────────────────────────────────
    if hi == 0x0:
        subop = opcode & 0x0F
        bit   = (opcode >> 4) & 0x0F
        s = _FLAG[subop].format(b=bit)
        if opcode == 0x0015:
            s += " ; PREG"
        return s

    # ── Keyboard scan  (hi = 0x8) ───────────────────────────────────────────
    if hi == 0x8:
        return f"KEY {opcode & 0xFF:02X}"

    # ── Wait / control  (hi = 0xA) ──────────────────────────────────────────
    if hi == 0xA:
        lo  = opcode & 0x0F
        arg = (opcode >> 4) & 0x0F

        if lo == 0x8:                          # PRN / CRD ops
            return _PRN.get(arg, f"PRN {arg:X}")

        if lo == 0x6:                          # FLGR5: copy fA or fB[1..4] → R5
            # Opcodes 0x0A76 and 0x0A86 are special MEMWR/MEMRD ops (TI-58C)
            if opcode == 0x0A76:
                return "MEMWR"
            if opcode == 0x0A86:
                return "MEMRD"
            reg = "fB" if (opcode & 0xF0) else "fA"
            return f"MOV R5,{reg}[1..4]"

        if lo == 0xF:                          # STOF / RCLF
            return _MEM.get((opcode >> 4) & 1, f"MEM.{arg:X}")

        if lo == 0xE:                          # LIB / NOP variants
            return _LIB.get(arg, f"NOP {arg:X}")

        return _CTRL.get(lo, f"CTRL {lo:X}").format(a=arg)

    # ── ALU  (all remaining hi values) ──────────────────────────────────────
    dst_i = opcode & 0x07
    fld_i = (opcode >> 8) & 0x0F
    alu_i = (opcode >> 3) & 0x1F

    dst = _DST[dst_i]
    fld = _MASK[fld_i]
    n   = _N[fld_i]

    # Exchange: destination name contains '<>' (e.g. "A<>B", "C<>D", "A<>E")
    # and bits 7..4 of opcode == 0xD
    if "<>" in dst and (opcode & 0xF0) == 0xD0:
        d1, d2 = dst.split("<>")
        return f"{d1}<>{d2} {fld}"

    # Special-case entries 24-31 (0x18-0x1F): immediate / R5 / const operands
    spOp = opcode & 0xF8
    if spOp == 0xC0:    # 18: ADD dst, A, const
        return f"{dst}={_ALU_SRC1[0]}+CON {fld}"
    if spOp == 0xC8:    # 19: SUB dst, A, const
        return f"{dst}={_ALU_SRC1[0]}-CON {fld}"
    if spOp == 0xD0:    # 1A: MOV dst, #N  (io-read latch)
        return f"{dst}=LOAD {fld}"
    if spOp == 0xD8:    # 1B: MOV dst, #-N
        if n == "0":
            return f"{dst}=0 {fld}"
        return f"{dst}=-{n} {fld}"
    if spOp == 0xE0:    # 1C: ADD dst, C, const
        return f"{dst}={_ALU_SRC1[4]}+CON {fld}"
    if spOp == 0xE8:    # 1D: SUB dst, C, const
        return f"{dst}={_ALU_SRC1[4]}-CON {fld}"
    if spOp == 0xF0:    # 1E: MOV dst, R5
        return f"{dst}=R5 {fld}"
    if spOp == 0xF8:    # 1F: MOV dst, -R5
        return f"{dst}=-R5 {fld}"

    if alu_i < len(_ALU_FMT):
        src1 = _ALU_SRC1[alu_i]
        src2 = _ALU_SRC2[alu_i]

        # For immediate entries (00-01, 04-05): substitute the destination as
        # left-hand side of the arithmetic when dst matches src1 (common case),
        # otherwise show both operands.
        if n != "0" and src2 == "" and alu_i in (0, 1, 4, 5):
            # Entries 00/01 use A; 04/05 use C — show +N / -N
            sign = "+" if alu_i in (0, 4) else "-"
            return f"{dst}={src1}{sign}{n} {fld}"
        if src2 == "" and alu_i in (0, 1, 4, 5):
            # n == "0": ADD/SUB with #0 — identical to a register copy
            return f"{dst}={src1} {fld}"

        result = _ALU_FMT[alu_i].format(d=dst, f=fld, n=n, s=src1, s2=src2)
        return result

    return f"ALU {opcode:04X}"


# ── --emit-cpp helper ────────────────────────────────────────────────────────

def emit_cpp() -> None:
    """Print C++ lookup arrays matching the current mnemonics.tsv tables."""

    def cpp_str(s: str) -> str:
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

    print("// ── Auto-generated by: python3 tools/disasm.py --emit-cpp ──────────────────")
    print("// Do not edit by hand; update tools/mnemonics.tsv and re-run.")
    print()

    # kMaskName[16]
    print("static const char* const kMaskName[16] = {")
    row = [cpp_str(_MASK[i]) for i in range(16)]
    print("    " + ", ".join(row[:8]) + ",")
    print("    " + ", ".join(row[8:]))
    print("};")
    print()

    # kFlagFmt[16]  — templates use %u for {b}
    flag_cpp = [f.replace("{b}", "%u") for f in _FLAG]
    print("static const char* const kFlagFmt[16] = {")
    for i, s in enumerate(flag_cpp):
        comma = "," if i < 15 else ""
        print(f"    {cpp_str(s)}{comma}")
    print("};")
    print()

    # kBranch[2]
    print("static const char* const kBranch[2] = {")
    print(f"    {cpp_str(_BRANCH[0])}, {cpp_str(_BRANCH[1])}")
    print("};")
    print()

    # kPrn[16]  — sparse; missing entries → ""
    prn_list = [_PRN.get(i, "") for i in range(16)]
    print("static const char* const kPrn[16] = {")
    for i, s in enumerate(prn_list):
        comma = "," if i < 15 else ""
        print(f"    {cpp_str(s)}{comma}  // {i:X}")
    print("};")
    print()

    # kLib[16]
    lib_list = [_LIB.get(i, "") for i in range(16)]
    print("static const char* const kLib[16] = {")
    for i, s in enumerate(lib_list):
        comma = "," if i < 15 else ""
        print(f"    {cpp_str(s)}{comma}  // {i:X}")
    print("};")
    print()

    # kMem[2]
    print("static const char* const kMem[2] = {")
    print(f"    {cpp_str(_MEM[0])}, {cpp_str(_MEM[1])}")
    print("};")
    print()

    print("// Note: CTRL entries with format args ({a}) must be handled inline.")
    print("// See mnemonics.tsv [CTRL] section for the full template list.")


# ── ROM loader ───────────────────────────────────────────────────────────────

def load_chip_txt(path: Path) -> list[tuple[int, int]]:
    """Parse a chip .txt file (header block + '---' separator, then 'AAAA: WWWW ...' lines).
    Returns an ordered list of (address, opcode) tuples."""
    words: list[tuple[int, int]] = []
    in_data = False
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if not in_data:
            if s.startswith("---"):
                in_data = True
            continue
        if not s:
            continue
        parts = s.split(":", 1)
        if len(parts) != 2:
            continue
        addr_str = parts[0].strip()
        if len(addr_str) != 4:
            continue
        try:
            base_addr = int(addr_str, 16)
        except ValueError:
            continue
        for i, word_str in enumerate(parts[1].split()):
            try:
                words.append((base_addr + i, int(word_str, 16) & 0x1FFF))
            except ValueError:
                continue
    return words


def load_chips(chip_names: list[str], roms_dir: Path) -> list[tuple[int, int]]:
    """Load and concatenate multiple chip .txt files in order."""
    words: list[tuple[int, int]] = []
    for name in chip_names:
        path = roms_dir / f"{name}.txt"
        chip_words = load_chip_txt(path)
        print(f"  {path.name}: {len(chip_words)} words")
        words += chip_words
    return words


def load_rom(path: Path) -> list[tuple[int, int]]:
    """Parse a legacy flat .hex ROM file → ordered list of (address, opcode) tuples."""
    hex_str = "".join(
        line.strip()
        for line in path.read_text(encoding="ascii").splitlines()
        if line.strip()
    )
    raw = bytes.fromhex(hex_str)
    return [
        (i // 2, ((raw[i] << 8) | raw[i + 1]) & 0x1FFF)
        for i in range(0, len(raw), 2)
    ]


# ── Section markers ──────────────────────────────────────────────────────────

# Section markers and ROM metadata keyed by first address of each region.
# Each entry is (section_comment, expected_word_count, last_addr, model_name).

_ROM_META: dict[str, dict] = {
    "59": {
        "chips": ["TMC0582", "TMC0583", "TMC0571B"],
        "sections": {
            0x0000: "; ── TMC0582  0x0000–0x09FF  2,560 words  (ROM chip 1) " + "─" * 20,
            0x0A00: "; ── TMC0583  0x0A00–0x13FF  2,560 words  (ROM chip 2) " + "─" * 20,
            0x1400: ("; ── TMC0571B 0x1400–0x17FF  1,024 words  (SCOM constant table) " + "─" * 10
                     + "\n; NOTE: this block is constant data used by the SCOM chip,\n"
                     + ";       not executable code.  Disassembly shown for reference."),
        },
        "expected": 6144,
        "addr_range": "0x0000–0x17FF",
        "title": "TI-59 ROM Disassembly — Phase 1 (raw, unlabeled)",
        "checksums": [(0x0000, 0x0A01), (0x17FF, 0x1987)],
    },
    "58C": {
        "chips": ["CD2400", "CD2401", "TMC0573"],
        "sections": {
            0x0000: "; ── CD2400   0x0000–0x09FF  2,560 words  (ROM chip 1) " + "─" * 20,
            0x0A00: "; ── CD2401   0x0A00–0x13FF  2,560 words  (ROM chip 2) " + "─" * 20,
            0x1400: "; ── TMC0573  0x1400–0x17FF  1,024 words  (SCOM constant table) " + "─" * 10,
        },
        "expected": 6144,
        "addr_range": "0x0000–0x17FF",
        "title": "TI-58C ROM Disassembly — Phase 1 (raw, unlabeled)",
        "checksums": [(0x0000, 0x0A01)],
    },
}

# Default section map used by cfg.py (TI-59)
_SECTIONS: dict[int, str] = _ROM_META["59"]["sections"]


# ── Main ─────────────────────────────────────────────────────────────────────

def _sibling_roms() -> Path:
    """Return the roms/ directory, preferring a local symlink."""
    local = ROOT / "roms"
    return local if local.exists() else ROOT.parent / "public" / "Calc-U-59" / "roms"


def disasm_rom(words: list[tuple[int, int]], out_path: Path, meta: dict) -> None:
    """Disassemble a word list and write the result to out_path."""
    print(f"  {len(words)} words total")

    if len(words) != meta["expected"]:
        print(f"WARNING: expected {meta['expected']} words, got {len(words)}", file=sys.stderr)

    addr_map = dict(words)
    for addr, expected_val in meta["checksums"]:
        got = addr_map.get(addr)
        ok  = got == expected_val
        print(f"  Checksum words[0x{addr:04X}]==0x{expected_val:04X} : {'PASS' if ok else f'FAIL (got 0x{got:04X})'}")

    lines: list[str] = [
        "; " + "═" * 74,
        f"; {meta['title']}",
        "; Generated by tools/disasm.py",
        f"; {len(words)} × 13-bit words  |  addresses {meta['addr_range']}",
        "; " + "═" * 74,
    ]

    sections = meta["sections"]
    for addr, opcode in words:
        if addr in sections:
            lines.append("")
            lines.append(sections[addr])
            lines.append("")
        # Extract model from metadata title or use from caller
        model = "59" if "TI-59" in meta["title"] else "58C"
        lines.append(f"{addr:04X}: {opcode:04X}  {disasm(addr, opcode, model)}")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Written → {out_path}  ({len(lines)} lines)")


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="TI-59/58C ROM disassembler")
    parser.add_argument("--emit-cpp", action="store_true", help="Print C++ lookup arrays and exit")
    parser.add_argument("--input",  "-i", type=Path,
                        help="Legacy flat .hex ROM file (overrides per-chip .txt loading)")
    parser.add_argument("--output", "-o", type=Path, help="Output .asm file")
    parser.add_argument("--model",  "-m", choices=["59", "58C"], default="59",
                        help="ROM model (default: 59)")
    args = parser.parse_args()

    if args.emit_cpp:
        emit_cpp()
        return

    roms = _sibling_roms()
    meta = _ROM_META[args.model]
    out_path = args.output or ROOT / "rom" / f"TI{args.model}.asm"

    if args.input:
        print(f"Loading {args.input} (legacy .hex) …")
        words = load_rom(args.input)
    else:
        print(f"Loading chips: {', '.join(meta['chips'])} …")
        words = load_chips(meta["chips"], roms)

    disasm_rom(words, out_path, meta)


if __name__ == "__main__":
    main()
