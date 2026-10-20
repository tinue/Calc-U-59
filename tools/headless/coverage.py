#!/usr/bin/env python3
"""ROM coverage by scenario: which keystroke scenarios execute which ROM words.

    tools/headless/coverage.py build            # run all SCENARIOS → coverage.json
    tools/headless/coverage.py show 0400 04FF   # per-address scenario list
    tools/headless/coverage.py unique sqrt      # addresses only that scenario hits
    tools/headless/coverage.py gaps             # never-executed address ranges
    tools/headless/coverage.py --variant TI58C build   # same for the TI-58C ROM

Each scenario starts from a freshly booted machine. A scenario's "setup"
keys run untraced; only its "keys" are attributed. Boot is a scenario of
its own ("boot"). The idle-loop window is excluded from attribution except
in "boot", so common idle code doesn't swamp every scenario.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ti59 import Machine, SECOND, in_idle  # noqa: E402

VARIANT = "TI59"
if "--variant" in sys.argv:
    _i = sys.argv.index("--variant")
    VARIANT = sys.argv[_i + 1]
    del sys.argv[_i:_i + 2]
OUT = Path(__file__).resolve().parent / "build" / (
    "coverage.json" if VARIANT == "TI59" else f"coverage-{VARIANT}.json")

# name: (setup keys, traced keys[, options])
S = lambda *k: list(k)  # noqa: E731
SCENARIOS: dict[str, tuple] = {
    # ── digit entry ──
    "digit5": ([], S("5")),
    "digits123": ([], S("1", "2", "3")),
    "dpt": ([], S("1", ".", "5")),
    "ee": ([], S("5", "EE", "3")),
    "ee_neg": ([], S("5", "EE", "3", "+/-")),
    "chs": ([], S("5", "+/-")),
    "ce": ([], S("5", "CE")),
    "clr": ([], S("5", "+", "3", "CLR")),
    "ee_inv": ([], S("1", "2", "3", "4", "EE", "INV", "EE")),
    "eng": ([], S("1", "2", "3", "4", "5", "Eng")),
    "fix2": ([], S("2", "/", "3", "=", "Fix", "2")),
    "fix_inv": ([S("Fix", "2")], S("INV", "Fix")),
    # ── binary arithmetic ──
    "add": ([], S("5", "+", "3", "=")),
    "sub": ([], S("5", "-", "3", "=")),
    "mul": ([], S("5", "*", "3", "=")),
    "div": ([], S("5", "/", "3", "=")),
    "ypowx": ([], S("2", "y^x", "3", "=")),
    "xroot": ([], S("8", "INV", "y^x", "3", "=")),
    "aos_prec": ([], S("5", "+", "7", "*", "3", "=")),
    "aos_paren": ([], S("(", "5", "+", "7", ")", "*", "3", "=")),
    "aos_deep": ([], S("2", "+", "3", "*", "4", "y^x", "2", "=")),
    "paren_close": ([], S("5", "*", "(", "2", "+", "3", ")", "=")),
    "pct_add": ([], S("2", "0", "0", "+", "5", "2nd", "x2")),  # placeholder, overwritten below
    "div0": ([], S("1", "/", "0", "=")),
    "overflow": ([], S("9", "EE", "9", "9", "x2")),
    "cp": ([S("5", "+", "3")], S("CP")),
    # ── unary ──
    "sqrt": ([], S("2", "sqrt")),
    "sqrt_neg": ([], S("2", "+/-", "sqrt")),
    "x2": ([], S("3", "x2")),
    "recip": ([], S("4", "1/x")),
    "lnx": ([], S("2", "lnx")),
    "exp": ([], S("2", "INV", "lnx")),
    "log": ([], S("2", "log")),
    "tenx": ([], S("2", "INV", "log")),
    "sin": ([], S("3", "0", "sin")),
    "cos": ([], S("6", "0", "cos")),
    "tan": ([], S("4", "5", "tan")),
    "asin": ([], S(".", "5", "INV", "sin")),
    "acos": ([], S(".", "5", "INV", "cos")),
    "atan": ([], S("1", "INV", "tan")),
    "sin_rad": ([S("Rad")], S("1", "sin")),
    "sin_grad": ([S("Grad")], S("5", "0", "sin")),
    "rad": ([], S("Rad")),
    "grad": ([], S("Grad")),
    "deg": ([S("Rad")], S("Deg")),
    "pi": ([], S("pi")),
    "abs": ([], S("5", "+/-", "|x|")),
    "int": ([], S("2", ".", "7", "Int")),
    "frac": ([], S("2", ".", "7", "INV", "Int")),
    "dms": ([], S("1", ".", "3", "0", "D.MS")),
    "dms_inv": ([], S("1", ".", "5", "INV", "D.MS")),
    "p2r": ([S("2", "x<>t")], S("3", "0", "P>R")),
    "r2p": ([S("3", "x<>t")], S("4", "INV", "P>R")),
    "xt": ([], S("5", "x<>t")),
    # ── memory ──
    "sto": ([S("5")], S("STO", "0", "5")),
    "rcl": ([S("5", "STO", "0", "5", "CLR")], S("RCL", "0", "5")),
    "sum": ([S("5", "STO", "0", "5")], S("3", "SUM", "0", "5")),
    "inv_sum": ([S("5", "STO", "0", "5")], S("3", "INV", "SUM", "0", "5")),
    "prd": ([S("5", "STO", "0", "5")], S("3", "Prd", "0", "5")),
    "inv_prd": ([S("6", "STO", "0", "5")], S("3", "INV", "Prd", "0", "5")),
    "exc": ([S("5", "STO", "0", "5")], S("3", "Exc", "0", "5")),
    "sto_ind": ([S("7", "STO", "0", "1", "5")], S("STO", "Ind", "0", "1")),
    "rcl_ind": ([S("7", "STO", "0", "1", "5", "STO", "0", "7")], S("RCL", "Ind", "0", "1")),
    "cms": ([S("5", "STO", "0", "5")], S("CMs")),
    "op17": ([], S("3", "Op", "1", "7")),
    "op16": ([], S("Op", "1", "6")),
    # ── statistics ──
    "sigma": ([], S("3", "S+")),
    "sigma_inv": ([S("3", "S+")], S("3", "INV", "S+")),
    "mean": ([S("3", "S+", "5", "S+")], S("mean")),
    "stddev": ([S("3", "S+", "5", "S+")], S("INV", "mean")),
    "op11": ([S("1", "x<>t", "2", "S+", "2", "x<>t", "4", "S+")], S("Op", "1", "2")),
    # ── comparison / flags (keyboard) ──
    "stflg": ([], S("StFlg", "3")),
    "inv_stflg": ([S("StFlg", "3")], S("INV", "StFlg", "3")),
    # ── programming ──
    "lrn_enter": ([], S("LRN")),
    "lrn_keys": ([S("LRN")], S("5", "+", "3", "=", "R/S")),
    "lrn_2nd": ([S("LRN")], S("sin", "Lbl", "A")),
    "lrn_sto": ([S("LRN")], S("STO", "1", "2")),
    "lrn_exit": ([S("LRN", "5")], S("LRN")),
    "lrn_sst": ([S("LRN", "5", "+", "3")], S("BST", "BST", "SST")),
    "lrn_ins": ([S("LRN", "5", "+", "3", "BST")], S("Ins")),
    "lrn_del": ([S("LRN", "5", "+", "3", "BST")], S("Del")),
    "gto_nnn": ([], S("GTO", "0", "1", "2")),
    "lrn_gto": ([S("GTO", "0", "1", "2")], S("LRN")),
    "rst": ([S("GTO", "0", "1", "2")], S("RST")),
    "run_simple": ([S("LRN", "5", "+", "3", "=", "R/S", "LRN", "RST")], S("R/S")),
    "sst_run": ([S("LRN", "5", "+", "3", "=", "R/S", "LRN", "RST")], S("SST", "SST")),
    "run_label": ([S("LRN", "Lbl", "A", "7", "x2", "INV", "SBR", "LRN")], S("A")),
    "run_label_e": ([S("LRN", "Lbl", "E'", "7", "INV", "SBR", "LRN")], S("E'")),
    "run_sbr": ([S("LRN", "Lbl", "A", "7", "INV", "SBR", "LRN")], S("SBR", "A")),
    "run_gto_lbl": ([S("LRN", "Lbl", "B", "8", "R/S", "LRN")], S("GTO", "B")),
    "run_loop_dsz": ([S("3", "STO", "0", "0", "LRN", "Lbl", "A", "Dsz", "0", "A", "R/S", "LRN")], S("A")),
    "run_pause": ([S("LRN", "Lbl", "A", "5", "Pause", "R/S", "LRN")], S("A")),
    "run_xeqt": ([S("LRN", "Lbl", "A", "x=t", "B", "1", "R/S", "Lbl", "B", "2", "R/S", "LRN", "5", "x<>t")], S("5", "A")),
    "run_ifflg": ([S("LRN", "Lbl", "A", "IfFlg", "1", "B", "1", "R/S", "Lbl", "B", "2", "R/S", "LRN", "StFlg", "1")], S("A")),
    "run_sbr_nested": ([S("LRN", "Lbl", "A", "SBR", "B", "R/S", "Lbl", "B", "SBR", "C", "INV", "SBR", "Lbl", "C", "4", "INV", "SBR", "LRN")], S("A")),
    "run_ind_gto": ([S("1", "0", "STO", "0", "1", "LRN", "GTO", "Ind", "0", "1", "LRN")], S("RST", "R/S")),
    "run_op_ind": ([S("1", "0", "STO", "0", "1", "LRN", "RCL", "Ind", "0", "1", "R/S", "LRN")], S("RST", "R/S")),
    "nop": ([S("LRN", "Nop", "R/S", "LRN", "RST")], S("R/S")),
    "cp_prog": ([S("LRN", "5", "LRN")], S("CP")),
    # ── library ──
    "pgm01": ([], S("Pgm", "0", "1", "SBR", "2ndCLR")),  # placeholder, overwritten below
    "pgm_select": ([], S("Pgm", "0", "2")),
    "pgm_run_a": ([S("Pgm", "0", "2")], S("1", "2", "A")),
    "pgm_sbr": ([], S("Pgm", "0", "1", "SBR", "0", "0", "0")),
    "pgm_lrn_view": ([S("Pgm", "0", "2")], S("LRN")),
    # ── printer ──
    "prt": ([S("5")], S("Prt"), {"printer": True}),
    "adv": ([], S("Adv"), {"printer": True}),
    "list": ([S("LRN", "5", "+", "3", "=", "LRN", "RST")], S("List"), {"printer": True}),
    "trace_key": ([], S("5", "+", "3", "="), {"printer": True, "trace": True}),
    "op_print": ([S("1", "7", "Op", "0", "1")], S("Op", "0", "5"), {"printer": True}),
    "op_alpha": ([], S("1", "7", "Op", "0", "1"), {"printer": True}),
}

# ── Op codes, printer, cards (added for the printer/card/Op passes) ──
for n in ["00","01","02","03","04","05","06","07","08","09","10","11","12","13","14","15","16","17","18","19","20","25","30","35"]:
    SCENARIOS["op"+n] = ([S("1", "2", ".", "5")], S("Op", n[0], n[1]), {"printer": True})
SCENARIOS["op_alpha_line"] = ([S("1","3","2","1","0","0","Op","0","1")], S("Op", "0", "5"), {"printer": True})
SCENARIOS["op06"] = ([S("1","3","2","1","0","0","Op","0","4","7")], S("Op", "0", "6"), {"printer": True})
SCENARIOS["op07"] = ([S("5")], S("Op", "0", "7"), {"printer": True})
SCENARIOS["op08_labels"] = ([S("LRN","Lbl","A","5","Lbl","B","LRN")], S("Op", "0", "8"), {"printer": True})
SCENARIOS["op09_pgm"] = ([S("Pgm","0","2")], S("Op", "0", "9"))
SCENARIOS["list_labels"] = ([S("LRN","Lbl","A","STO","1","2","GTO","A","LRN","RST")], S("List"), {"printer": True})
SCENARIOS["prt_lrn"] = ([S("LRN","5","+")], S("Prt"), {"printer": True})
SCENARIOS["trace_run"] = ([S("LRN","5","+","3","=","R/S","LRN","RST")], S("R/S"), {"printer": True, "trace": True})
SCENARIOS["pause_run"] = ([S("LRN","5","Pause","Pause","R/S","LRN","RST")], S("R/S"))
SCENARIOS["write_card"] = ([S("LRN","5","+","3","=","LRN")], S("1", "Write"), {"card": "blank"})
# a bank-1 image written by the scenario above (headless run): program 5 + 3 =
_CARD = bytes.fromhex("161110000000005930582010" + "00" * 232 + "0808")
SCENARIOS["read_card"] = ([], S(), {"card": _CARD})
SCENARIOS["lib_return"] = ([S("Pgm","0","2","5")], S("C"))
SCENARIOS["op09_copy"] = ([S("0","Op","1","7","CLR","Pgm","0","2")], S("Op", "0", "9"))
SCENARIOS["op17_big"] = ([], S("1","3","Op","1","7"))
SCENARIOS["ins_del"] = ([S("LRN","1","2","3","4","BST","BST")], S("Ins","Del","LRN"))
SCENARIOS["cms_regs"] = ([S("5","STO","0","5")], S("CMs","RCL","0","5"))
SCENARIOS["hir"] = ([], S("5","STO","0","5","CLR","RCL","0","5","x2","="))
SCENARIOS["ind_sbr"] = ([S("LRN","Lbl","A","9","INV","SBR","LRN","1","1","STO","0","1")], S("SBR","Ind","0","1"))

# Fix placeholders with real sequences
SCENARIOS["pct_add"] = ([], S("2", "+", "3", "x>=t"))  # x>=t from keyboard = no-op test
SCENARIOS["pgm01"] = ([], S("Pgm", "0", "1", "SBR", "0", "0", "0"))

# ── added in the second ROM documentation pass ──
_PCARD = _CARD[:3] + b"\x10" + _CARD[4:]          # same bank, protect byte set
SCENARIOS["write_card_prot"] = ([S("LRN","5","+","3","=","LRN")], S("1", "+/-", "Write"), {"card": "blank"})
SCENARIOS["read_card_prot"] = ([], S(), {"card": _PCARD})
SCENARIOS["read_card_part"] = ([S("3","Op","1","7","CLR")], S(), {"card": _CARD})
SCENARIOS["read_card_inv"] = ([], S("1", "INV", "Write"), {"card": _CARD})
SCENARIOS["lrn_ind_merge"] = ([S("LRN")], S("STO","Ind","0","5","GTO","Ind","0","3","Op","Ind","0","4","Exc","Ind","0","1","Fix","Ind","0","2"))
SCENARIOS["p2r_deep_aos"] = ([S("1","+","(","2","*","(","3","+","(","4","*","(","5","+","(")], S("3","x<>t","4","P>R"))
SCENARIOS["p2r_in_program"] = ([S("LRN","Lbl","A","3","x<>t","4","Nop","Nop","P>R","R/S","LRN")], S("A"))
SCENARIOS["label_keys"] = ([S("LRN","Lbl","E'","5","R/S","Lbl","x2","R/S","LRN")], S("GTO","E'","GTO","x2","SBR","E'"))
SCENARIOS["sto_abandon"] = ([], S("5","STO","x2"))
SCENARIOS["op09_short"] = ([S("Pgm","2","3")], S("Op","0","9"))
SCENARIOS["inv_list"] = ([S("7","STO","5","8","5","8")], S("INV","List"), {"printer": True})
SCENARIOS["sbr_overflow"] = ([S("LRN","Lbl","A","SBR","B","R/S","Lbl","B","SBR","C","INV","SBR","Lbl","C","SBR","D","INV","SBR",
                                "Lbl","D","SBR","E","INV","SBR","Lbl","E","SBR","A'","INV","SBR","Lbl","A'","SBR","B'","INV","SBR",
                                "Lbl","B'","SBR","C'","INV","SBR","Lbl","C'","INV","SBR","LRN")], S("A"))
SCENARIOS["bst_boundary"] = ([S("LRN","1","2","3","4","5","6","7","8")], S("BST", "RST", "BST"))
SCENARIOS["prog_reg_100"] = ([S("0","Op","1","7","CLR","GTO","8","5","0","LRN","Lbl","A","5","R/S","LRN","RST","CLR")], S("A"))
SCENARIOS["kbd_lbl"] = ([], S("5","Lbl","3","2ndCLR"))
SCENARIOS["prt_sci_err"] = ([], S("1",".","5","EE","3","+/-","Prt","1","/","0","=","Prt",".","5","Prt"), {"printer": True})
SCENARIOS["trace_ind"] = ([S("5","STO","0","1")], S("RCL","Ind","0","1"), {"printer": True, "trace": True})


def expand(keys):
    out = []
    for k in keys:
        if isinstance(k, list):
            out += expand(k)
        else:
            out += ["2nd", str(SECOND[k])] if k in SECOND else [k]
    return out


def run(name: str, spec) -> set[int]:
    setup, keys = spec[0], spec[1]
    opts = spec[2] if len(spec) > 2 else {}
    m = Machine(printer=opts.get("printer", False), variant=VARIANT)
    run.last_card = b""
    if opts.get("trace"):
        from ti59 import LIB
        LIB.h_trace_sw(m.h, 1)
    for k in expand(setup):
        m.key(k)
    pcs: set[int] = set()
    recs_all = []
    for k in expand(keys):
        recs_all += m.key(k)
    card = opts.get("card")
    if card is not None:          # feed a card: b"" = blank (write), bytes = read
        m.card_insert(card if isinstance(card, bytes) else b"")
        for _ in range(40):
            recs_all += m.record(20000)
            if not m.card_present():
                break
        recs_all += m.record(50000)
        run.last_card = m.card_eject()
    for r in recs_all:
        if not in_idle(r, VARIANT):
            pcs.add(r.pc)
    run.last_display = m.display()
    run.last_printer = m.printer_lines()
    return pcs


def build():
    cov: dict[str, list[int]] = {}
    m = Machine(variant=VARIANT)
    cov["boot"] = sorted({r.pc for r in m.boot_recs})
    for name, spec in SCENARIOS.items():
        if VARIANT != "TI59" and len(spec) > 2 and "card" in spec[2]:
            continue                  # no card reader on the TI-58/58C
        pcs = run(name, spec)
        cov[name] = sorted(pcs)
        prn = " | ".join(run.last_printer)
        print(f"{name:16} {len(pcs):5} words  [{run.last_display}] {prn}", file=sys.stderr)
    OUT.write_text(json.dumps(cov))
    allpcs = set().union(*map(set, cov.values()))
    print(f"total covered: {len(allpcs)} / 6144", file=sys.stderr)


def load():
    return {k: set(v) for k, v in json.loads(OUT.read_text()).items()}


def by_addr(cov):
    d: dict[int, list[str]] = {}
    for name, pcs in cov.items():
        for p in pcs:
            d.setdefault(p, []).append(name)
    return d


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "build"
    if cmd == "build":
        build()
        return
    cov = load()
    d = by_addr(cov)
    if cmd == "show":
        lo, hi = int(sys.argv[2], 16), int(sys.argv[3], 16)
        n = len(cov)
        for a in range(lo, hi + 1):
            names = d.get(a, [])
            tag = "ALL" if len(names) > n * 0.6 else ",".join(names[:12]) + ("…" if len(names) > 12 else "")
            print(f"{a:04X} [{len(names):3}] {tag}")
    elif cmd == "unique":
        name = sys.argv[2]
        only = sorted(a for a in cov[name] if d[a] == [name])
        print(" ".join(f"{a:04X}" for a in only))
    elif cmd == "gaps":
        run_start = None
        for a in range(0, 0x1800 + 1):
            hit = a in d
            if not hit and run_start is None:
                run_start = a
            elif hit and run_start is not None:
                if a - run_start >= 4:
                    print(f"{run_start:04X}-{a - 1:04X} ({a - run_start})")
                run_start = None


if __name__ == "__main__":
    main()
