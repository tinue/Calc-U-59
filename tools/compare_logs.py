#!/usr/bin/env python3
"""
compare_logs.py — Compare two trace log files by program counter (PC).

Finds where the logs start to sync up (matching x consecutive PCs) and where
the sync stops. Prints line numbers where end-sync occurs.

Usage:
    python3 compare_logs.py <file1> <file2> <sync_threshold>

Example:
    python3 compare_logs.py trace1.txt trace2.txt 10

This will find sequences of 10+ identical consecutive PCs and report where
the synchronization ends.
"""

import sys
import re

def extract_pcs(filepath):
    """
    Extract (PC, line_number) tuples from a trace log file.

    Looks for lines matching pattern "XXXX YYYY <mnemonic>"
    where the first field is a 4-hex-digit PC value.
    """
    pcs = []
    with open(filepath, 'r') as f:
        for line_num, line in enumerate(f, start=1):
            # Match lines like "07EC 0AA0 WAIT D10"
            match = re.match(r'^([0-9A-F]{4})\s+[0-9A-F]{4}', line)
            if match:
                pc = match.group(1)
                pcs.append((pc, line_num))
    return pcs

def find_sync_range(pcs1, pcs2, threshold):
    """
    Find where pcs1 and pcs2 start to sync up and where they stop.

    Returns:
        (start_idx1, start_idx2, end_idx1, end_idx2) - indices in pcs1/pcs2
        or (None, None, None, None) if no sync found
    """
    if not pcs1 or not pcs2:
        return None, None, None, None

    # Find the first position where we have threshold consecutive matching PCs
    for i in range(len(pcs1)):
        for j in range(len(pcs2)):
            # Check if we have threshold consecutive matches starting at i, j
            if i + threshold <= len(pcs1) and j + threshold <= len(pcs2):
                if all(pcs1[i + k][0] == pcs2[j + k][0] for k in range(threshold)):
                    # Found sync start
                    sync_start_i = i
                    sync_start_j = j

                    # Now find where the sync ends
                    k = threshold
                    while (i + k < len(pcs1) and j + k < len(pcs2) and
                           pcs1[i + k][0] == pcs2[j + k][0]):
                        k += 1

                    sync_end_i = i + k - 1
                    sync_end_j = j + k - 1

                    return sync_start_i, sync_start_j, sync_end_i, sync_end_j

    return None, None, None, None

def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)

    file1 = sys.argv[1]
    file2 = sys.argv[2]
    try:
        threshold = int(sys.argv[3])
    except ValueError:
        print(f"Error: sync_threshold must be an integer, got '{sys.argv[3]}'")
        sys.exit(1)

    print(f"Loading {file1}...", file=sys.stderr)
    pcs1 = extract_pcs(file1)
    print(f"  Found {len(pcs1)} PC entries", file=sys.stderr)

    print(f"Loading {file2}...", file=sys.stderr)
    pcs2 = extract_pcs(file2)
    print(f"  Found {len(pcs2)} PC entries", file=sys.stderr)

    print(f"Finding sync with threshold={threshold}...", file=sys.stderr)
    start_idx1, start_idx2, end_idx1, end_idx2 = find_sync_range(pcs1, pcs2, threshold)

    if start_idx1 is None:
        print(f"No sync found with threshold={threshold}")
        sys.exit(1)

    # Get line numbers (remembering pcs is a list of (pc, line_number) tuples)
    start_line1 = pcs1[start_idx1][1]
    start_line2 = pcs2[start_idx2][1]
    end_line1 = pcs1[end_idx1][1]
    end_line2 = pcs2[end_idx2][1]

    sync_length = end_idx1 - start_idx1 + 1

    print(f"Sync found:")
    print(f"  Start: file1 line {start_line1} ({pcs1[start_idx1][0]}), file2 line {start_line2} ({pcs2[start_idx2][0]})")
    print(f"  End:   file1 line {end_line1} ({pcs1[end_idx1][0]}), file2 line {end_line2} ({pcs2[end_idx2][0]})")
    print(f"  Sync length: {sync_length} PCs")

if __name__ == '__main__':
    main()
