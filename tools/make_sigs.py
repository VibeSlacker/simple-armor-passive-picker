#!/usr/bin/env python3
"""Make this mod's own code signatures from a dump of the game's code.

  make_sigs.py <game.mem> <data/targets.json> <out sigs.json>

game.mem is game.dll copied out of the running game's memory from its base
(the code is only unpacked there), so file offsets equal game.dll offsets.

For each thing the mod needs (a global slot or a function), targets.json gives
its game.dll offset in the dumped build and any code spans to stay away from.
The tool lists every place in the code that points at it, takes them in order,
and for the first one that qualifies writes a pattern: a run of whole
instructions around the reference, with every address field (rip-relative and
call/jump distances) masked out so it can survive a rebuild of the game. A
place qualifies when the disassembly from its function's start lands exactly
on it, and the pattern matches exactly once in the whole dump.
"""
import json
import re
import subprocess
import sys

import numpy as np

CODE_START, MIN_LEN, MAX_LEN, MIN_FIXED = 0x1000, 44, 110, 30


def refs_to(data, code_end, target):
    b = data[CODE_START:code_end].astype(np.int64)
    n = len(b) - 4
    v = b[0:n] | (b[1:n + 1] << 8) | (b[2:n + 2] << 16) | (b[3:n + 3] << 24)
    v = np.where(v >= 2 ** 31, v - 2 ** 32, v)
    pos = np.arange(n) + CODE_START
    return [int(p) for p in pos[(pos + 4 + v) == target]]


def disassemble(path, start, stop):
    out = subprocess.run(
        ["objdump", "-D", "-b", "binary", "-mi386:x86-64", "-Mintel", "--insn-width=16",
         "--start-address=0x%x" % start, "--stop-address=0x%x" % stop, path],
        capture_output=True, text=True, check=True).stdout
    insns = []
    for line in out.splitlines():
        m = re.match(r"^\s*([0-9a-f]+):\t((?:[0-9a-f]{2} )+)\s*\t?(.*)$", line)
        if m:
            raw = bytes.fromhex(m.group(2).replace(" ", ""))
            insns.append((int(m.group(1), 16), raw, m.group(3).strip()))
    return insns


def function_starts(raw, site, reach=0x3000):
    """Candidate starts: 16-aligned addresses just after int3 padding, nearest first."""
    at = site & ~15
    while at > site - reach and at > CODE_START:
        if raw[at - 1] == 0xCC and raw[at] != 0xCC:
            yield at
        at -= 16


def address_fields(insn):
    """Offsets inside the instruction of 4-byte fields that hold a distance to another address."""
    addr, raw, text = insn
    end = addr + len(raw)
    wanted = set()
    for m in re.finditer(r"# 0x([0-9a-f]+)", text):
        wanted.add(int(m.group(1), 16))
    m = re.match(r"^(?:call|jmp|j[a-z]+)\s+0x([0-9a-f]+)$", text)
    if m:
        wanted.add(int(m.group(1), 16))
    fields = []
    for k in range(0, len(raw) - 3):
        rel = int.from_bytes(raw[k:k + 4], "little", signed=True)
        if end + rel in wanted:
            fields.append(k)
    return fields


def find_all(raw, pattern, mask, key_at):
    key = pattern[key_at:key_at + 4]
    out, at = [], raw.find(key)
    while at != -1:
        start = at - key_at
        if start >= 0 and start + len(pattern) <= len(raw):
            window = raw[start:start + len(pattern)]
            if all(m == 0 or a == b for a, b, m in zip(window, pattern, mask)):
                out.append(start)
        at = raw.find(key, at + 1)
    return out


def make(path, raw, data, code_end, target, avoid, want_call):
    for site in refs_to(data, code_end, target):
        if any(lo - MAX_LEN <= site < hi + MAX_LEN for lo, hi in avoid):
            continue
        if want_call and raw[site - 1] != 0xE8:
            continue
        for start in function_starts(raw, site):
            insns = disassemble(path, start, site + MAX_LEN + 32)
            idx = next((i for i, (a, r, _) in enumerate(insns) if a <= site < a + len(r)), None)
            if idx is None:
                continue
            addr, r, text = insns[idx]
            if site - addr not in address_fields(insns[idx]):
                continue   # the disassembly does not see this as a reference to the target
            lo = hi = idx
            ok = lambda i: 0 <= i < len(insns) and "int3" not in insns[i][2] and "(bad)" not in insns[i][2]
            def span(): return insns[hi][0] + len(insns[hi][1]) - insns[lo][0]
            def fixed():
                return sum(len(x[1]) - 4 * len(address_fields(x)) for x in insns[lo:hi + 1])
            grow_back = True
            while (span() < MIN_LEN or fixed() < MIN_FIXED) and span() < MAX_LEN:
                if grow_back and ok(lo - 1):
                    lo -= 1
                elif ok(hi + 1):
                    hi += 1
                elif ok(lo - 1):
                    lo -= 1
                else:
                    break
                grow_back = not grow_back
            if span() < MIN_LEN or fixed() < MIN_FIXED or span() > MAX_LEN:
                break
            first = insns[lo][0]
            pattern, mask = bytearray(), bytearray()
            for x in insns[lo:hi + 1]:
                m = bytearray(b"\xff" * len(x[1]))
                for k in address_fields(x):
                    m[k:k + 4] = b"\0\0\0\0"
                pattern += x[1]
                mask += m
            if bytes(pattern) != raw[first:first + len(pattern)]:
                break
            # the scan key: the rarest fully fixed 4 bytes in the pattern
            best = None
            for k in range(len(pattern) - 3):
                if all(mask[k:k + 4]):
                    count = raw.count(bytes(pattern[k:k + 4]))
                    if best is None or count < best[0]:
                        best = (count, k)
            if best is None:
                break
            hits = find_all(raw, pattern, mask, best[1])
            if hits != [first]:
                break
            for k in range(len(pattern)):
                if mask[k] == 0:
                    pattern[k] = 0
            return {
                "hex": pattern.hex(), "mask": mask.hex(),
                "anchor": bytes(pattern[best[1]:best[1] + 4]).hex(), "anchor_offset": best[1],
                "extract_offset": site - first, "extract_end": addr + len(r) - first,
                "site": "game.dll+0x%X in the function at +0x%X: %s" % (addr, start, text),
            }
    return None


def main():
    path, targets_path, out_path = sys.argv[1:4]
    spec = json.load(open(targets_path, encoding="utf-8"))
    raw = open(path, "rb").read()
    data = np.frombuffer(raw, dtype=np.uint8)
    code_end = int(spec["code_end"], 16)
    out = []
    for t in spec["targets"]:
        target = int(t["rva"], 16)
        avoid = [(int(a, 16), int(b, 16)) for a, b in t.get("avoid", [])]
        sig = make(path, raw, data, code_end, target, avoid, t.get("call", False))
        if not sig:
            sys.exit("no usable place found for " + t["name"])
        # recheck through the same arithmetic the mod uses
        hits = find_all(raw, bytes.fromhex(sig["hex"]), bytes.fromhex(sig["mask"]), sig["anchor_offset"])
        at = hits[0]
        rel = int.from_bytes(raw[at + sig["extract_offset"]:at + sig["extract_offset"] + 4], "little", signed=True)
        if len(hits) != 1 or at + sig["extract_end"] + rel != target:
            sys.exit("self-check failed for " + t["name"])
        entry = {"name": t["name"], **sig, "symbol": t["symbol"]}
        if t.get("optional"):
            entry["optional"] = True
        out.append(entry)
        print("%-16s %3d bytes  %s" % (t["name"], len(sig["hex"]) // 2, sig["site"]))
    for extra in spec.get("keep", []):
        out.append(extra)
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("[\n" + ",\n".join(json.dumps(e, indent=1) for e in out) + "\n]\n")


if __name__ == "__main__":
    main()
