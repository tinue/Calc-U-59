#!/usr/bin/env python3
"""Headless TI-59 harness: drive Core/ from Python and capture ROM traces.

Loads tools/headless/build/libti59headless.dylib (build with build.sh),
the TI-59 ROM/constant dumps from roms/calculator/, and optionally a
solid-state module from roms/solid-state/.

Library use:
    m = Machine()            # boots to the idle loop
    recs = m.key("5")        # press+release, returns the HRec list
    print(m.format(recs))    # annotated trace

CLI:
    tools/headless/ti59.py 5 + 7 = [--full] [--module ML]
Each argument is one key name (see KEYS); "2nd:x" style is not needed —
press "2nd" then the key, as on the hardware.
"""
from __future__ import annotations

import argparse
import ctypes as C
import os
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
ROMS = REPO / "roms"

# Matrix code = row*10 + col (row 1-9 top to bottom, col 1-5 left to right).
KEYS = {
    "A": 11, "B": 12, "C": 13, "D": 14, "E": 15,
    "2nd": 21, "INV": 22, "lnx": 23, "CE": 24, "CLR": 25,
    "LRN": 31, "x<>t": 32, "x2": 33, "sqrt": 34, "1/x": 35,
    "SST": 41, "STO": 42, "RCL": 43, "SUM": 44, "y^x": 45,
    "BST": 51, "EE": 52, "(": 53, ")": 54, "/": 55,
    "GTO": 61, "7": 62, "8": 63, "9": 64, "*": 65,
    "SBR": 71, "4": 72, "5": 73, "6": 74, "-": 75,
    "RST": 81, "1": 82, "2": 83, "3": 84, "+": 85,
    "R/S": 91, "0": 92, ".": 93, "+/-": 94, "=": 95,
}
# 2nd functions: pressed as 2nd (21) followed by the base key's matrix code.
SECOND = {
    "A'": 11, "B'": 12, "C'": 13, "D'": 14, "E'": 15,
    "log": 23, "CP": 24, "2ndCLR": 25,
    "Pgm": 31, "P>R": 32, "sin": 33, "cos": 34, "tan": 35,
    "Ins": 41, "CMs": 42, "Exc": 43, "Prd": 44, "Ind": 45,
    "Del": 51, "Eng": 52, "Fix": 53, "Int": 54, "|x|": 55,
    "Pause": 61, "x=t": 62, "Nop": 63, "Op": 64, "Deg": 65,
    "Lbl": 71, "x>=t": 72, "S+": 73, "mean": 74, "Rad": 75,
    "StFlg": 81, "IfFlg": 82, "D.MS": 83, "pi": 84, "Grad": 85,
    "Write": 91, "Dsz": 92, "Adv": 93, "Prt": 94, "List": 95,
}
# The PC-100's own PRINT and ADV buttons (TI59Machine::pressPrinterPrint/Adv).
PRINTER_BUTTONS = {"PRINT": "h_printer_print", "PAPER": "h_printer_adv"}
KBITS = [0, 1, 2, 3, 5, 6]  # physical column -> K-line bit (Bridge/TI59MachineWrapper.mm)

# The TI-59's idle-loop window (idleAndKeyDetect in Shared/MachineModelInfo.hpp);
# in_idle() reads every model's from the library.
IDLE_LO, IDLE_HI = 0x0627, 0x0660

FLG_IDLE, FLG_COND = 0x0001, 0x0800


class HRec(C.Structure):
    _pack_ = 1
    _fields_ = [
        ("pc", C.c_uint16), ("opcode", C.c_uint16),
        ("KR", C.c_uint16), ("SR", C.c_uint16), ("fA", C.c_uint16), ("fB", C.c_uint16),
        ("flags", C.c_uint16), ("PREG", C.c_uint16), ("EXT", C.c_uint16), ("libAddr", C.c_uint16),
        ("R5", C.c_uint8), ("digit", C.c_uint8), ("weight", C.c_uint8), ("pad", C.c_uint8),
        ("A", C.c_uint8 * 16), ("B", C.c_uint8 * 16), ("C", C.c_uint8 * 16),
        ("D", C.c_uint8 * 16), ("E", C.c_uint8 * 16),
        ("SCOM", (C.c_uint8 * 16) * 16),
    ]


def _lib():
    path = HERE / "build" / "libti59headless.dylib"
    if not path.exists():
        os.system(str(HERE / "build.sh"))
    lib = C.CDLL(str(path))
    lib.h_new.restype = C.c_void_p
    for name in ("h_free", "h_reset", "h_press",
                 "h_release", "h_printer", "h_trace_sw", "h_stepn", "h_record", "h_snapshot",
                 "h_ram_read", "h_ram_write", "h_write_program", "h_display", "h_pc",
                 "h_lib_exec_pc", "h_printer_lines", "h_printer_code_lines", "h_printer_print",
                 "h_printer_adv"):
        getattr(lib, name).argtypes = None
    lib.h_stepn.argtypes = [C.c_void_p, C.c_uint32]
    lib.h_load_model_roms.argtypes = [C.c_void_p, C.c_int, C.c_char_p]
    lib.h_load_module.argtypes = [C.c_void_p, C.c_char_p, C.c_char_p]
    lib.h_record.argtypes = [C.c_void_p, C.c_void_p, C.c_int, C.c_int]
    lib.h_pc.argtypes = [C.c_void_p]
    lib.h_pc.restype = C.c_uint16
    lib.h_elapsed.argtypes = [C.c_void_p]
    lib.h_elapsed.restype = C.c_uint64
    lib.h_lib_exec_pc.argtypes = [C.c_void_p]
    lib.h_lib_exec_pc.restype = C.c_uint16
    lib.h_disasm.argtypes = [C.c_uint16, C.c_uint16, C.c_char_p, C.c_int]
    lib.h_instruction_hz.argtypes = [C.c_int]
    lib.h_instruction_hz.restype = C.c_double
    lib.h_printer_busy_cycles.argtypes = [C.c_int]
    lib.h_printer_busy_cycles.restype = C.c_uint32
    lib.h_idle_range.argtypes = [C.c_int, C.POINTER(C.c_int)]
    assert lib.h_rec_size() == C.sizeof(HRec), "HRec layout mismatch with capi.cpp"
    return lib


LIB = _lib()

_DIS: dict[tuple[int, int], str] = {}


def disasm(pc: int, op: int) -> str:
    k = (pc, op)
    if k not in _DIS:
        buf = C.create_string_buffer(96)
        LIB.h_disasm(pc, op, buf, 96)
        s = buf.value.decode()
        # TMC0501::disassemble prefixes "PPPP: OOOO  "; keep only the mnemonic.
        _DIS[k] = s.split("  ", 1)[-1].strip() if ":" in s[:6] else s.strip()
    return _DIS[k]


# Machine variants: Core/MachineVariant.hpp enum value (= Shared/MachineModelInfo.hpp Model).
VARIANTS = {"TI59": 0, "TI58": 1, "TI58C": 2}

# TI-59 active-mode instruction rate (instructionHz in Shared/MachineModelInfo.hpp).
INSTR_PER_SEC = LIB.h_instruction_hz(VARIANTS["TI59"])


def _idle_spans(model: int) -> tuple[tuple[int, int], ...]:
    out = (C.c_int * 4)()
    LIB.h_idle_range(model, out)
    return tuple((lo, hi) for lo, hi in ((out[0], out[1]), (out[2], out[3])) if lo <= hi)


IDLE_SPANS = {name: _idle_spans(model) for name, model in VARIANTS.items()}


def in_idle(r, variant: str = "TI59") -> bool:
    """r (HRec) sits in the idle loop."""
    if not r.flags & FLG_IDLE:
        return False
    return any(lo <= r.pc <= hi for lo, hi in IDLE_SPANS[variant])


def nibs(r, msd_first=True) -> str:
    v = list(r)
    return "".join(f"{x:x}" for x in (reversed(v) if msd_first else v))


class Machine:
    def __init__(self, module: str | None = "ML", printer: bool = False, boot: bool = True,
                 variant: str = "TI59"):
        self.variant = variant
        self.h = C.c_void_p(LIB.h_new(VARIANTS[variant]))
        roms = str(ROMS).encode()
        if LIB.h_load_model_roms(self.h, VARIANTS[variant], roms) != 0:
            raise RuntimeError(f"cannot load the {variant} ROM from {ROMS}")
        if module and LIB.h_load_module(self.h, module.encode(), roms) != 0:
            raise KeyError(module)
        LIB.h_printer(self.h, 1 if printer else 0)
        LIB.h_reset(self.h)
        self.boot_recs: list[HRec] = []
        if boot:
            self.boot_recs = self.record(400_000, until_idle=True)

    def __del__(self):
        try:
            LIB.h_free(self.h)
        except Exception:
            pass

    # ── low level ──────────────────────────────────────────────────────────
    def snapshot(self) -> HRec:
        r = HRec()
        LIB.h_snapshot(self.h, C.byref(r))
        return r

    def elapsed(self) -> int:
        """Weighted instruction count since reset (idle steps count 4); divide by
        INSTR_PER_SEC for emulated seconds."""
        return LIB.h_elapsed(self.h)

    def step(self, n: int = 1):
        LIB.h_stepn(self.h, n)

    def record(self, n: int, stop_pc: int = -1, until_idle: bool = False,
               idle_quiet: int = 3000) -> list[HRec]:
        """Run up to n steps, recording each. With until_idle, stop once the CPU
        has stayed inside the idle-loop window for idle_quiet consecutive steps
        (those trailing idle steps are trimmed from the result)."""
        out: list[HRec] = []
        chunk = 4096
        quiet = 0
        while len(out) < n:
            buf = (HRec * chunk)()
            got = LIB.h_record(self.h, buf, min(chunk, n - len(out)), stop_pc)
            for i in range(got):
                r = buf[i]
                out.append(r)
                if until_idle:
                    if in_idle(r, self.variant):
                        quiet += 1
                    else:
                        quiet = 0
                    if quiet >= idle_quiet:
                        return out[:len(out) - quiet + 1]
            if stop_pc >= 0 and got < chunk and out and LIB.h_pc(self.h) == stop_pc:
                return out
        return out

    def press(self, name: str):
        if name in PRINTER_BUTTONS:
            return getattr(LIB, PRINTER_BUTTONS[name])(self.h, 1)
        mc = KEYS[name] if name in KEYS else int(name)
        LIB.h_press(self.h, KBITS[mc % 10], mc // 10)

    def release(self, name: str):
        if name in PRINTER_BUTTONS:
            return getattr(LIB, PRINTER_BUTTONS[name])(self.h, 0)
        mc = KEYS[name] if name in KEYS else int(name)
        LIB.h_release(self.h, KBITS[mc % 10], mc // 10)

    def key(self, name: str, hold: int = 3000, max_steps: int = 2_000_000) -> list[HRec]:
        """Press a key, hold it for `hold` steps, release, run to quiescence."""
        self.press(name)
        recs = self.record(hold)
        self.release(name)
        recs += self.record(max_steps, until_idle=True)
        return recs

    def keys(self, *names: str) -> list[list[HRec]]:
        """Press a sequence of keys; 2nd-function names expand to 2nd + key."""
        out = []
        for n in names:
            if n in SECOND:
                out.append(self.key("2nd"))
                n = str(SECOND[n])
            out.append(self.key(n))
        return out

    def run_until_idle(self, max_steps: int = 50_000_000):
        """Fast-forward (no recording) until back in the idle loop."""
        for _ in range(max_steps // 20000):
            self.step(20000)
            s = self.snapshot()
            if in_idle(s, self.variant):
                # make sure it stays idle
                self.step(5000)
                s = self.snapshot()
                if in_idle(s, self.variant):
                    return True
        return False

    # ── state ──────────────────────────────────────────────────────────────
    def ram(self, reg: int) -> bytes:
        b = (C.c_uint8 * 16)()
        LIB.h_ram_read(self.h, reg, b)
        return bytes(b)

    def write_program(self, keycodes: list[int]):
        LIB.h_write_program(self.h, (C.c_uint8 * len(keycodes))(*keycodes), len(keycodes))

    def display(self) -> str:
        """Display as seen on the LEDs, leftmost digit first (glyph decode as in
        App/Views/LEDDisplayView.swift)."""
        d = (C.c_uint8 * 12)(); c = (C.c_uint8 * 12)(); mk = (C.c_uint16 * 2)()
        LIB.h_display(self.h, d, c, mk)
        out = []
        for i in reversed(range(12)):
            ctl, dig = c[i], d[i]
            if ctl in (0, 1, 8, 9):
                ch = " " if (mk[1] >> i) & 1 else f"{dig:X}"
            elif ctl == 5:
                ch = "-" if dig == 0 else "°"
            elif ctl == 6:
                ch = "-"
            else:
                ch = " "
            out.append(ch + ("." if (mk[0] >> i) & 1 else ""))
        return "".join(out)

    def regA_display(self) -> str:
        """Display image straight from A/B: A digits 13..2, B ctrl codes."""
        s = self.snapshot()
        return f"A={nibs(s.A)} B={nibs(s.B)} R5={s.R5}"

    def card_insert(self, data: bytes = b""):
        buf = (C.c_uint8 * max(1, len(data))).from_buffer_copy(data or b"\0")
        LIB.h_card_insert(self.h, buf, len(data))

    def card_eject(self) -> bytes:
        b = (C.c_uint8 * 1024)()
        n = LIB.h_card_eject(self.h, b, 1024)
        return bytes(b[:n])

    def card_present(self) -> bool:
        return bool(LIB.h_card_present(self.h))

    def card_waiting(self) -> bool:
        """The ROM is polling the card switch with no card in the reader."""
        return bool(LIB.h_card_waiting(self.h))

    def printer_lines(self) -> list[str]:
        b = C.create_string_buffer(65536)
        n = LIB.h_printer_lines(self.h, b, 65536)
        return b.raw[:n].decode("utf-8", "replace").splitlines()

    def printer_code_lines(self) -> list[tuple[list[int], int, int, int]]:
        """New dot-matrix lines since the last call: (20 printer codes, rows,
        columns of the next row started before a cut, cycles the leftmost of
        them was heated)."""
        cap = 65536  # the C side drains its whole queue; lines past cap are lost
        b = C.create_string_buffer(23 * cap)
        n = LIB.h_printer_code_lines(self.h, b, cap)
        return [(list(b.raw[23 * i : 23 * i + 20]), b.raw[23 * i + 20], b.raw[23 * i + 21],
                 b.raw[23 * i + 22]) for i in range(n)]

    # ── formatting ─────────────────────────────────────────────────────────
    @staticmethod
    def format(recs: list[HRec], full: bool = False, collapse_idle: bool = True,
               prev: HRec | None = None, labels: dict[int, str] | None = None,
               variant: str = "TI59") -> str:
        """One line per instruction: PC, opcode, mnemonic, then the registers
        and SCOM rows it changed (post-exec). Long idle-loop stretches collapse."""
        lines = []
        last = prev
        idle_run = 0
        for r in recs:
            if collapse_idle and in_idle(r, variant) and not full:
                idle_run += 1
                last = r
                continue
            if idle_run:
                lines.append(f"      … {idle_run} idle-loop steps …")
                idle_run = 0
            changes = []
            if last is not None:
                for reg in ("A", "B", "C", "D", "E"):
                    if bytes(getattr(r, reg)) != bytes(getattr(last, reg)):
                        changes.append(f"{reg}={nibs(getattr(r, reg))}")
                for f in ("KR", "SR", "fA", "fB"):
                    if getattr(r, f) != getattr(last, f):
                        changes.append(f"{f}={getattr(r, f):04x}")
                if r.R5 != last.R5:
                    changes.append(f"R5={r.R5:x}")
                for i in range(16):
                    if bytes(r.SCOM[i]) != bytes(last.SCOM[i]):
                        changes.append(f"S{i}={nibs(r.SCOM[i])}")
            cond = "" if r.flags & FLG_COND else " c0"
            lab = (labels or {}).get(r.pc, "")
            lab = f"{lab}: " if lab else ""
            lines.append(f"{r.pc:04X} {r.opcode:04X} d{r.digit:x}{cond:3} {lab}{disasm(r.pc, r.opcode):24} "
                         + " ".join(changes))
            last = r
        if idle_run:
            lines.append(f"      … {idle_run} idle-loop steps …")
        return "\n".join(lines)


def summary(recs: list[HRec], labels: dict[int, str] | None = None, variant: str = "TI59") -> str:
    """Each distinct non-idle PC once, in first-execution order, with its hit
    count — a compact map of the code a keystroke runs, loops folded."""
    order: list[int] = []
    count: dict[int, int] = {}
    op: dict[int, int] = {}
    for r in recs:
        if in_idle(r, variant):
            continue
        if r.pc not in count:
            order.append(r.pc)
            count[r.pc] = 0
            op[r.pc] = r.opcode
        count[r.pc] += 1
    out = []
    for pc in order:
        lab = (labels or {}).get(pc, "")
        out.append(f"{pc:04X} ×{count[pc]:<5} {(lab + ': ') if lab else ''}{disasm(pc, op[pc])}")
    return "\n".join(out)


def load_labels(variant: str = "TI59") -> dict[int, str]:
    labels = {}
    p = REPO / "rom" / ("TI58C-labels.asm" if variant == "TI58C" else "TI59-labels.asm")
    if not p.exists():
        return labels
    for line in p.read_text().splitlines():
        parts = line.split()
        if len(parts) >= 2 and len(parts[0]) == 4 and parts[1] != "—":
            try:
                labels[int(parts[0], 16)] = parts[1]
            except ValueError:
                pass
    return labels


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("keys", nargs="*")
    ap.add_argument("--module", default="ML")
    ap.add_argument("--printer", action="store_true")
    ap.add_argument("--full", action="store_true", help="don't collapse idle-loop steps")
    ap.add_argument("--boot", action="store_true", help="also print the boot trace")
    ap.add_argument("--program", help="comma-separated keycodes written to RAM step 0..")
    ap.add_argument("--summary", action="store_true", help="distinct PCs per key with hit counts")
    ap.add_argument("--variant", default="TI59", choices=sorted(VARIANTS))
    args = ap.parse_args()
    m = Machine(module=args.module or None, printer=args.printer, variant=args.variant)
    labels = load_labels(args.variant)
    if args.boot:
        print("=== boot ===")
        print(Machine.format(m.boot_recs, full=args.full, labels=labels, variant=m.variant))
    if args.program:
        m.write_program([int(x) for x in args.program.split(",")])
    prev = m.snapshot()
    seq = []
    for k in args.keys:
        seq += ["2nd", str(SECOND[k])] if k in SECOND else [k]
    for k in seq:
        recs = m.key(k)
        print(f"=== key {k}  ({len(recs)} steps) ===")
        if args.summary:
            print(summary(recs, labels, m.variant))
        else:
            print(Machine.format(recs, full=args.full, prev=prev, labels=labels, variant=m.variant))
        prev = recs[-1] if recs else prev
        print(f"--- display: [{m.display()}]  {m.regA_display()}")
    for line in m.printer_lines():
        print("PRN:", line)


if __name__ == "__main__":
    main()
