# Memory Index

## Project
- [sbr444-quirk-analysis.md](sbr444-quirk-analysis.md) — SBR 444 / R/S printer-interrupt quirk chain analysis; must stay in sync with `rom/TI59-commented.asm` and `examples/historic/texas-print.ti59`

## Traces
CPU traces (`tools/read_trace.py` text) cited by the analysis and the ROM annotations:
- `sbr444.txt`, `rs.txt`, `pr-after-halt1.txt`, `pr-after-halt2.txt` — the printer-interrupt quirk chain (see sbr444-quirk-analysis.md)
- `errorblink.txt` — 1/x of 0 → error blink → CLR (cited in `rom/TI59-commented.asm`)
