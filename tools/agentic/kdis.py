"""Disassemble a TI-59 keycode program into one line per instruction.

CLI: kdis.py file.ti59
  Prints the program as "step  mnemonic operands" (operand bytes folded into
  their instruction; Ind, addresses and the Dsz/If flg register shown), then
  the REGISTERS, the KEYSTROKES and the partition (total steps).
Library: dis(keycodes, start=0, end=None) -> list of lines."""
import os
import sys
MN = {
 11:'A',12:'B',13:'C',14:'D',15:'E',16:"A'",17:"B'",18:"C'",19:"D'",10:"E'",
 21:'2nd',22:'INV',23:'lnx',24:'CE',25:'CLR',26:'2nd2nd',27:'2ndINV',28:'log',29:'CP',20:'2ndCLR',
 31:'LRN',32:'x<>t',33:'x2',34:'sqrt',35:'1/x',36:'Pgm',37:'P>R',38:'sin',39:'cos',30:'tan',
 41:'SST',42:'STO',43:'RCL',44:'SUM',45:'y^x',46:'Ins',47:'CMs',48:'Exc',49:'Prd',40:'Ind',
 51:'BST',52:'EE',53:'(',54:')',55:'/',56:'Del',57:'Eng',58:'Fix',59:'Int',50:'|x|',
 61:'GTO',62:'Pg*',63:'Ex*',64:'Pd*',65:'*',66:'Pause',67:'x=t',68:'Nop',69:'Op',60:'Deg',
 71:'SBR',72:'ST*',73:'RC*',74:'SM*',75:'-',76:'Lbl',77:'x>=t',78:'S+',79:'mean',70:'Rad',
 81:'RST',82:'HIR',83:'GO*',84:'OP*',85:'+',86:'StFlg',87:'IfFlg',88:'D.MS',89:'pi',80:'Grad',
 91:'R/S',92:'RTN',93:'.',94:'+/-',95:'=',96:'Write',97:'Dsz',98:'Adv',99:'Prt',90:'List'}
ONE = {42,43,44,48,49,58,69,36,76,82,62,63,64,72,73,74,83,84,40}   # one operand byte
ADDR = {61,71,67,77}                                               # address operand
TWO = {97,87}                                                      # reg/flag byte + address


def dis(p, start=0, end=None):
    out = []; i = start; end = len(p) if end is None else end
    while i < end:
        k = p[i]; s = f'{i:03d}  {MN.get(k, "%02d" % k) if k >= 10 else str(k)}'
        j = i + 1
        def addr(j):
            if j < len(p) and p[j] < 10:
                return f'{p[j]}{p[j+1]:02d}' if j + 1 < len(p) else '?', j + 2
            return (MN.get(p[j], str(p[j])) if j < len(p) else '?'), j + 1
        if k in ONE and j < len(p):
            if p[j] == 40 and k not in (40,):
                s += f' Ind {p[j+1]:02d}'; j += 2
            else:
                s += f' {p[j]:02d}' if k != 76 else f' {MN.get(p[j], p[j])}'; j += 1
        elif k in ADDR and j < len(p):
            if p[j] == 40:
                s += f' Ind {p[j+1]:02d}'; j += 2
            else:
                a, j = addr(j); s += f' {a}'
        elif k in TWO and j < len(p):
            s += f' {p[j]:02d}'; j += 1
            a, j = addr(j); s += f' {a}'
        out.append(s); i = j
    return out


if __name__ == '__main__':
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from ti59file import parse
    prog, regs, part, keys = parse(sys.argv[1])
    for l in dis(prog):
        print(l)
    print('REGISTERS', {k: v for k, v in sorted(regs.items())})
    print('KEYS', keys, 'PARTITION', part)
