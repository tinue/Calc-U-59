"""Tiny TI-59 keycode assembler (library, no CLI).

Tokens are keycode ints, mnemonics (see KC), ('L', name)
label definitions, ('A', name) absolute-address operands (2 bytes),
('D2', a, b) the label distance a - b as two digit steps and ('N', text)
notes for the listing."""
KC = {
    'CLR': 25, 'x<>t': 32, 'STO': 42, 'RCL': 43, 'SUM': 44, 'Exc': 48, 'Prd': 49, 'INV': 22,
    '+': 85, '-': 75, '*': 65, '/': 55, '=': 95, '+/-': 94, '.': 93, 'Int': 59, 'Op': 69,
    'HIR': 82, 'RC*': 73, 'GTO': 61, 'SBR': 71, 'RTN': 92, 'x=t': 67, 'x>=t': 77, 'Adv': 98,
    'R/S': 91, 'RST': 81, 'GO*': 83, 'Lbl': 76, 'A': 11, 'CE': 24, 'EE': 52, 'Nop': 68, 'StFlg': 86, 'Fix': 58, 'Dsz': 97, '(': 53, ')': 54,
}


OPERAND = {'STO', 'RCL', 'SUM', 'Exc', 'Prd', 'Op', 'HIR', 'RC*', 'GO*', 'Fix', 'Dsz', 'StFlg', 'Lbl'}


def assemble(tokens, listing=None):
    """keycodes and labels; if a dict is given as listing, it receives
    addr -> (text shown for the step, [notes before it])"""
    # pass 1: addresses
    addr = 0; labels = {}
    for t in tokens:
        if isinstance(t, tuple) and t[0] in ('L', 'N'):
            if t[0] == 'L':
                labels[t[1]] = addr
        elif isinstance(t, tuple) and t[0] in ('A', 'D2'):
            addr += 2
        elif isinstance(t, tuple) and t[0] == 'ORG':
            addr = t[1]
        else:
            addr += 1
    out = {}; addr = 0; notes = []; shown = {}; prev = None
    for t in tokens:
        operand = prev in OPERAND
        if not (isinstance(t, tuple) and t[0] in ('L', 'N')):
            prev = t
        if isinstance(t, tuple):
            if t[0] == 'L':
                notes.append(t[1] + ':'); continue
            if t[0] == 'N':
                notes.append(t[1]); continue
            if t[0] == 'ORG':
                addr = t[1]; continue
            a = labels[t[1]] if t[0] == 'A' else labels[t[1]] - labels[t[2]]
            assert 0 <= a <= (999 if t[0] == 'A' else 99), t
            base = 100 if t[0] == 'A' else 10
            out[addr] = a // base; out[addr + 1] = a % base
            shown[addr] = (t[1] if t[0] == 'A' else str(a), notes); notes = []
            shown[addr + 1] = ('', []); addr += 2
        else:
            out[addr] = KC[t] if isinstance(t, str) else t
            shown[addr] = (t if isinstance(t, str) else '%02d' % t if operand else str(t), notes); notes = []
            addr += 1
    n = max(out) + 1
    if listing is not None:
        listing.update(shown)
    return [out.get(i, 0) for i in range(n)], labels


def digits(s):
    return [93 if c == '.' else int(c) for c in s]
