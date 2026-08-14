#!/usr/bin/env python3
"""Pack the plaintext ROM/module dumps under roms/ into single files under
docs/wasm/roms/, for the web calculator (docs/#play).

Re-runnable any time roms/*.txt changes (e.g. fixing a module ROM error) —
the .txt files stay the editable source of truth; this script never reads
its own output. Mirrors the parsing rules in App/ROMLoader.swift exactly
(parseRomTxt, parseTMCTxt, parseConstantsTxt, parseCueCardFile) so the two
loaders agree on layout without sharing code.

Output is JSON with base64-encoded binary payloads rather than a bespoke
binary container: it's one file per ROM/module (mitigates plaintext,
grep-able firmware dumps being trivially discoverable), needs no custom
binary parser on the JS side (fetch().then(r => r.json())), and the sizes
involved (a few KB each) make base64's ~33% overhead irrelevant.

Usage: tools/pack_roms.py
"""
import base64
import json
import re
import struct
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CALC_ROMS = REPO_ROOT / "roms" / "calculator"
SOLID_STATE = REPO_ROOT / "roms" / "solid-state"
OUT_DIR = REPO_ROOT / "docs" / "wasm" / "roms"

TI59_ROM_CHIPS = ["TMC0582", "TMC0583", "TMC0571B"]
TI59_CONST_CHIPS = ["TMC0582-CONST-K", "TMC0583-CONST-K"]

# TI-59 ROM sanity sentinels (see App/ROMLoader.swift `ROMLoader.load`).
EXPECTED_ROM_WORD_COUNT = 6144
SENTINEL_FIRST = 0x0A01
SENTINEL_LAST = 0x1987


def parse_rom_txt(text: str) -> list[int]:
    """Port of ROMLoader.parseRomTxt: header block terminated by '---',
    then 'AAAA: WWWW WWWW ...' lines. Each word is masked to 13 bits."""
    words: list[int] = []
    in_data = False
    for raw_line in text.splitlines():
        s = raw_line.strip()
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
        if len(addr_str) != 4 or not _is_hex(addr_str):
            continue
        for word_str in parts[1].split():
            words.append(int(word_str, 16) & 0x1FFF)
    return words


def parse_tmc_txt(text: str) -> bytes:
    """Port of ROMLoader.parseTMCTxt: header block terminated by '---',
    optional 'ADDR: ... DATA' header, then 'AAAA: xx xx ...' rows where
    AAAA is decimal and xx are 2-hex-digit BCD-as-hex bytes."""
    buf = bytearray(5000)
    max_addr = 0
    in_data = False
    for raw_line in text.splitlines():
        s = raw_line.strip()
        if not in_data:
            if s.startswith("---"):
                in_data = True
            continue
        if s.upper().startswith("ADDR:") and "DATA" in s.upper():
            continue
        if not s:
            continue
        parts = s.split(":", 1)
        if len(parts) != 2:
            continue
        addr_str = parts[0].strip()
        if not addr_str.lstrip("-").isdigit():
            continue
        addr = int(addr_str)
        for i, tok in enumerate(parts[1].split()):
            idx = addr + i
            if idx < 5000:
                buf[idx] = int(tok, 16)
                max_addr = max(max_addr, idx + 1)
    if max_addr == 0:
        raise ValueError("no data rows found after '---' separator")
    return bytes(buf[:max_addr])


def parse_constants_txt(text: str) -> list[bytes]:
    """Port of ROMLoader.parseConstantsTxt: 32 rows of 16 nibbles under the
    'CONSTANT ROM (NUMBER)' section, nibbles reversed to hardware order."""
    rows: list[bytes] = []
    in_number_section = False
    for raw_line in text.splitlines():
        s = raw_line.strip()
        if "CONSTANT ROM (NUMBER)" in s:
            in_number_section = True
            continue
        if s.startswith("---"):
            if in_number_section:
                break
            continue
        if not in_number_section or not s:
            continue
        parts = s.split(":", 1)
        if len(parts) != 2:
            continue
        addr_str = parts[0].strip()
        if not addr_str.isdigit():
            continue
        hex_str = parts[1].strip()
        if len(hex_str) != 16:
            continue
        nibbles = bytes(int(c, 16) for c in reversed(hex_str))
        rows.append(nibbles)
    return rows


def _is_hex(s: str) -> bool:
    try:
        int(s, 16)
        return True
    except ValueError:
        return False


def pack_ti59_core() -> None:
    words: list[int] = []
    for chip in TI59_ROM_CHIPS:
        words += parse_rom_txt((CALC_ROMS / f"{chip}.txt").read_text())
    if len(words) != EXPECTED_ROM_WORD_COUNT:
        raise ValueError(f"expected {EXPECTED_ROM_WORD_COUNT} ROM words, got {len(words)}")
    if words[0] != SENTINEL_FIRST:
        raise ValueError(f"words[0] expected 0x{SENTINEL_FIRST:04X}, got 0x{words[0]:04X}")
    if words[-1] != SENTINEL_LAST:
        raise ValueError(f"words[-1] expected 0x{SENTINEL_LAST:04X}, got 0x{words[-1]:04X}")
    rom_bytes = struct.pack(f"<{len(words)}H", *words)

    const_rows: list[bytes] = []
    for chip in TI59_CONST_CHIPS:
        const_rows += parse_constants_txt((CALC_ROMS / f"{chip}.txt").read_text())
    if len(const_rows) != 64:
        raise ValueError(f"expected 64 constant rows, got {len(const_rows)}")
    const_bytes = b"".join(const_rows)

    out = {
        "romWords": base64.b64encode(rom_bytes).decode("ascii"),
        "romWordCount": len(words),
        "constants": base64.b64encode(const_bytes).decode("ascii"),
    }
    dest = OUT_DIR / "ti59-core.json"
    dest.write_text(json.dumps(out))
    print(f"wrote {dest.relative_to(REPO_ROOT)} ({len(words)} words, {len(const_bytes)} const bytes)")


# ── Solid-state modules ──────────────────────────────────────────────────

CUECARD_LABEL_KEYS = {
    "a": 5, "b": 6, "c": 7, "d": 8, "e": 9,
    "a'": 0, "a′": 0, "b'": 1, "b′": 1, "c'": 2, "c′": 2,
    "d'": 3, "d′": 3, "e'": 4, "e′": 4,
}


def new_card() -> dict:
    return {
        "template": "CueCard",
        "title": "",
        "banks": [None, None],
        "id": "",
        "labels": [""] * 10,
        "row1": "", "row1Align": "center",
        "row2": "", "row2Align": "left",
        "row2R": "", "row2RAlign": "left",
        "style": "none",
    }


def apply_cuecard_line(card: dict, line: str) -> None:
    """Port of CueCardContent.parseLine — mirrors field names 1:1 so the
    same JSON shape can be consumed by docs/cuecard.js for both module and
    preset-embedded cards."""
    parts = line.split(":", 1)
    if len(parts) < 2:
        return
    key = parts[0].strip().lower()
    value = parts[1].strip()

    if key == "template":
        if value in ("CueCard", "MagnetCard", "SolidStateCard"):
            card["template"] = value
    elif key == "title":
        card["title"] = value
    elif key == "banks":
        bank_parts = value.split(",")
        left = bank_parts[0].strip() if len(bank_parts) > 0 else ""
        right = bank_parts[1].strip() if len(bank_parts) > 1 else ""
        card["banks"] = [int(left) if left.isdigit() else None,
                          int(right) if right.isdigit() else None]
    elif key == "id":
        card["id"] = value
    elif key == "idalign":
        pass  # deprecated, ignored (matches Swift)
    elif key == "row1":
        card["row1"] = value
    elif key == "row2":
        card["row2"] = value
    elif key == "row2r":
        card["row2R"] = value
    elif key == "style":
        if value.lower() in ("none", "button"):
            card["style"] = value.lower()
    elif key == "row1align":
        card["row1Align"] = _align(value)
    elif key == "row2align":
        card["row2Align"] = _align(value)
    elif key == "row2ralign":
        card["row2RAlign"] = _align(value)
    elif key in CUECARD_LABEL_KEYS:
        card["labels"][CUECARD_LABEL_KEYS[key]] = value


def _align(value: str) -> str:
    v = value.lower()
    return v if v in ("left", "right", "center") else "left"


def parse_cuecards_file(text: str) -> list[dict]:
    """Port of ROMLoader.parseCueCardFile, but collects every module in one
    pass instead of filtering to a single target ID (we pack all of them)."""
    modules: list[dict] = []
    current_module: dict | None = None
    current_card: dict | None = None
    current_key = 0

    def flush_card():
        if current_module is not None and current_card is not None:
            current_module["cuecards"][str(current_key)] = current_card

    for raw_line in text.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        upper = line.upper()

        if upper.startswith("MODULE-ID:"):
            flush_card()
            current_card = None
            current_module = {
                "id": line[len("MODULE-ID:"):].strip(),
                "title": "", "menuTitle": "", "menuSort": 0, "romFile": "",
                "cuecards": {},
            }
            modules.append(current_module)
            continue

        if current_module is None:
            continue

        if upper.startswith("MODULE-TITLE:"):
            current_module["title"] = line[len("MODULE-TITLE:"):].strip()
        elif upper.startswith("MODULE-MENU-TITLE:"):
            current_module["menuTitle"] = line[len("MODULE-MENU-TITLE:"):].strip()
        elif upper.startswith("MODULE-MENU-SORT:"):
            v = line[len("MODULE-MENU-SORT:"):].strip()
            if v.lstrip("-").isdigit():
                current_module["menuSort"] = int(v)
        elif upper.startswith("MODULE-ROM:"):
            current_module["romFile"] = line[len("MODULE-ROM:"):].strip()
        elif upper.startswith("CUECARD:"):
            flush_card()
            rest = line[len("CUECARD:"):].strip()
            current_key = int(rest) if rest.isdigit() else 0
            current_card = new_card()
        else:
            if current_card is not None:
                apply_cuecard_line(current_card, line)

    flush_card()
    return modules


def pack_solid_state_modules() -> None:
    cuecards_text = (SOLID_STATE / "cuecards.txt").read_text()
    modules = parse_cuecards_file(cuecards_text)
    modules.sort(key=lambda m: m["menuSort"])

    manifest = []
    for m in modules:
        rom_file = m["romFile"]
        if not rom_file:
            raise ValueError(f"module {m['id']} has no MODULE-ROM entry")
        rom_bytes = parse_tmc_txt((SOLID_STATE / rom_file).read_text())

        out = {
            "id": m["id"],
            "title": m["title"],
            "menuTitle": m["menuTitle"],
            "menuSort": m["menuSort"],
            "rom": base64.b64encode(rom_bytes).decode("ascii"),
            "cuecards": m["cuecards"],
        }
        slug = m["id"].lower()
        dest = OUT_DIR / f"module-{slug}.json"
        dest.write_text(json.dumps(out))
        print(f"wrote {dest.relative_to(REPO_ROOT)} ({len(rom_bytes)} rom bytes, "
              f"{len(m['cuecards'])} cue cards) — {m['menuTitle']!r}")
        manifest.append({"id": m["id"], "menuTitle": m["menuTitle"], "menuSort": m["menuSort"],
                          "file": f"module-{slug}.json"})

    dest = OUT_DIR / "modules.json"
    dest.write_text(json.dumps(manifest))
    print(f"wrote {dest.relative_to(REPO_ROOT)} ({len(manifest)} modules)")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    pack_ti59_core()
    pack_solid_state_modules()


if __name__ == "__main__":
    main()
