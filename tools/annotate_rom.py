#!/usr/bin/env python3
"""Apply a batch of annotations to rom/TI59-commented.asm.

The commented listing is the hand-maintained source of truth; this tool only
makes bulk edits to it safe. Each listing line is "AAAA: OOOO  mnemonic" (the
raw text from rom/TI59.asm) optionally followed by an inline comment, with
continuation lines indented to the comment column. Block headers are
column-0 ';' lines directly above an address line.

Batch file syntax (one directive per line; '#' lines are ignored):

    AAAA {MNEM} text…  optional {MNEM} must prefix-match AAAA's mnemonic (a
                    guard against misaligned comments); stripped before use
    AAAA text…      set AAAA's inline comment (replaces the old one and its
                    continuation lines; long text is wrapped)
    AAAA +text…     append to AAAA's inline comment
    AAAA -          remove AAAA's inline comment
    @AAAA           the following ';' lines become AAAA's block header,
                    replacing any existing header directly above AAAA
    @+AAAA          …same, but inserted below the existing header
    ; text…         (outside an @ block) header lines for the address of the
                    next directive, inserted below any existing header

Usage: tools/annotate_rom.py BATCH [--listing rom/TI59-commented.asm] [--dry-run]
       tools/annotate_rom.py --skeleton 0140 0236   # print a batch template
"""
from __future__ import annotations

import argparse
import re
import sys
import textwrap
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
COMMENT_COL = 30
WIDTH = 96
ADDR_RE = re.compile(r"^([0-9A-F]{4}): ")


def base_texts(raw: Path) -> dict[str, str]:
    out = {}
    for line in raw.read_text().splitlines():
        m = ADDR_RE.match(line)
        if m:
            out[m.group(1)] = line.rstrip()
    return out


def wrap_comment(base: str, text: str) -> list[str]:
    pad = max(COMMENT_COL, len(base) + 1)
    first = base.ljust(pad) + "; "
    avail_first = max(20, WIDTH - len(first))
    avail = WIDTH - COMMENT_COL - 4
    words = text.split()
    lines, cur, limit = [], "", avail_first
    for w in words:
        if cur and len(cur) + 1 + len(w) > limit:
            lines.append(cur)
            cur, limit = w, avail
        else:
            cur = f"{cur} {w}" if cur else w
    if cur:
        lines.append(cur)
    out = [first + lines[0]] if lines else [base]
    out += [" " * COMMENT_COL + ";   " + l for l in lines[1:]]
    return out


def mnemonic(base: str) -> str:
    return base[12:].strip()


def skeleton(listing: list[str], bases: dict[str, str], lo: int, hi: int) -> str:
    out = []
    i = 0
    while i < len(listing):
        m = ADDR_RE.match(listing[i])
        if m and lo <= int(m.group(1), 16) <= hi:
            addr = m.group(1)
            base = bases[addr]
            j = i + 1
            conts = []
            while j < len(listing) and listing[j].startswith(" " * 10) and listing[j].lstrip().startswith(";"):
                conts.append(listing[j].strip()[1:].strip())
                j += 1
            com = listing[i][len(base):].strip().lstrip(";").strip()
            com = " ".join([com] + conts).strip()
            out.append(f"{addr} {{{mnemonic(base)}}} {com}".rstrip())
        i += 1
    return "\n".join(out)


checks: list[tuple[str, str]] = []


def parse_batch(text: str):
    inline: dict[str, tuple[str, str]] = {}
    headers: dict[str, tuple[bool, list[str]]] = {}
    cur_hdr = None
    loose: list[str] = []
    checks.clear()
    for raw in text.splitlines():
        line = raw.rstrip()
        if cur_hdr is not None and line.startswith(";"):
            headers[cur_hdr][1].append(line)
            continue
        cur_hdr = None
        if line.startswith(";"):
            loose.append(line)
            continue
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.startswith("@"):
            add = line.startswith("@+")
            addr = line[2:].strip() if add else line[1:].strip()
            headers[addr.upper()] = (add, [])
            cur_hdr = addr.upper()
            continue
        m = re.match(r"^([0-9A-Fa-f]{4})\s+(.*)$", line)
        if not m:
            sys.exit(f"bad directive: {line!r}")
        addr, rest = m.group(1).upper(), m.group(2).strip()
        if loose:
            prev = headers.get(addr, (True, []))
            headers[addr] = (prev[0], prev[1] + loose)
            loose = []
        if rest.startswith("{"):
            close = rest.index("}")
            want, rest = rest[1:close].strip(), rest[close + 1:].strip()
            checks.append((addr, want))
            if not rest:
                continue
        if rest == "-":
            inline[addr] = ("del", "")
        elif rest.startswith("+"):
            inline[addr] = ("add", rest[1:].strip())
        else:
            inline[addr] = ("set", rest)
    return inline, headers


def apply(listing: list[str], bases: dict[str, str], inline, headers) -> list[str]:
    # Group the listing into entries: (header lines, addr line, continuation lines)
    out: list[str] = []
    i = 0
    n = len(listing)
    pending_hdr: list[str] = []
    while i < n:
        line = listing[i]
        m = ADDR_RE.match(line)
        if not m:
            pending_hdr.append(line)
            i += 1
            continue
        addr = m.group(1)
        conts = []
        j = i + 1
        while j < n and listing[j].startswith(" " * 10) and listing[j].lstrip().startswith(";"):
            conts.append(listing[j])
            j += 1
        # header handling: only the trailing column-0 ';' run is "the header"
        if addr in headers:
            add, new = headers[addr]
            k = len(pending_hdr)
            while k > 0 and pending_hdr[k - 1].startswith(";"):
                k -= 1
            keep, old = pending_hdr[:k], pending_hdr[k:]
            pending_hdr = keep + (old + new if add else new)
        out += pending_hdr
        pending_hdr = []
        base = bases.get(addr)
        if base is None or not line.startswith(base):
            sys.exit(f"{addr}: listing line doesn't start with raw disassembly:\n  {line}\n  {base}")
        old_comment = line[len(base):].strip()
        if old_comment.startswith(";"):
            old_comment = old_comment[1:].strip()
        old_cont = " ".join(c.strip()[1:].strip() for c in conts)
        old_full = (old_comment + " " + old_cont).strip()
        if addr in inline:
            mode, text = inline[addr]
            if mode == "del":
                out.append(base)
            else:
                full = text if mode == "set" else (old_full + " " + text).strip()
                out += wrap_comment(base, full)
        else:
            out.append(line)
            out += conts
        i = j
    out += pending_hdr
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("batch", nargs="?")
    ap.add_argument("--skeleton", nargs=2, metavar=("LO", "HI"))
    ap.add_argument("--listing", default=str(REPO / "rom" / "TI59-commented.asm"))
    ap.add_argument("--raw", default=str(REPO / "rom" / "TI59.asm"))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    listing = Path(args.listing).read_text().splitlines()
    bases = base_texts(Path(args.raw))
    if args.skeleton:
        print(skeleton(listing, bases, int(args.skeleton[0], 16), int(args.skeleton[1], 16)))
        return
    inline, headers = parse_batch(Path(args.batch).read_text())
    bad = [(a, w, mnemonic(bases[a])) for a, w in checks if not mnemonic(bases[a]).startswith(w)]
    if bad:
        for a, w, got in bad:
            print(f"{a}: expected {{{w}}}, ROM has {{{got}}}", file=sys.stderr)
        sys.exit(1)
    out = apply(listing, bases, inline, headers)
    if args.dry_run:
        sys.stdout.write("\n".join(out) + "\n")
    else:
        Path(args.listing).write_text("\n".join(out) + "\n")
        print(f"applied {len(inline)} inline, {len(headers)} header edits", file=sys.stderr)


if __name__ == "__main__":
    main()
