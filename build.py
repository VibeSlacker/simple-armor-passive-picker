#!/usr/bin/env python3
"""Build the Passive Picker mod: fill the data tables into the Lua and pack it.

  build.py            -> build/9ba626afa44a3aa3.patch_0 (+ two empty side files)
  build.py public     -> build-public/ the same, without the personal-only parts

The personal build carries extras that reach into other mods' territory (the
equipment tile redraw after a DiverKit preset switch). They sit between
--@PERSONAL_BEGIN@ and --@PERSONAL_END@ lines in the source and under
"personal": true in data/sigs.json; the public build drops both.

Data in data/*.json is reference fact about game build 25480438 (signatures,
armor ids with their default passive, passive names). After a game update the
signatures may stop matching; the mod then stops itself and says so in its log.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pack  # noqa: E402


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def strip_personal(src, public):
    out, keep, depth = [], True, 0
    for line in src.split("\n"):
        mark = line.strip()
        if mark == "--@PERSONAL_BEGIN@":
            depth += 1
            if depth != 1:
                sys.exit("nested --@PERSONAL_BEGIN@")
            keep = not public
        elif mark == "--@PERSONAL_END@":
            depth -= 1
            if depth != 0:
                sys.exit("--@PERSONAL_END@ without a begin")
            keep = True
        elif keep:
            out.append(line)
    if depth:
        sys.exit("--@PERSONAL_BEGIN@ never closed")
    return "\n".join(out)


def main():
    public = sys.argv[1:] == ["public"]
    if sys.argv[1:] and not public:
        sys.exit("usage: build.py [public]")
    load = lambda name: json.load(open(os.path.join(HERE, "data", name), encoding="utf-8"))
    sigs, armors, passives = load("sigs.json"), load("armors.json"), load("passives.json")
    descs = load("passive_desc.json")
    if public:
        sigs = [s for s in sigs if not s.get("personal")]
    sig_lua = "{\n" + "".join(
        "\t{ name = %s, symbol = %s, anchor_offset = %d, extract_offset = %d, extract_end = %d, optional = %s,\n"
        "\t  hex = %s,\n\t  mask = %s,\n\t  anchor = %s },\n" % (
            lua_str(s["name"]), lua_str(s["symbol"]), s["anchor_offset"], s["extract_offset"],
            s["extract_end"], "true" if s.get("optional") else "false",
            lua_str(s["hex"]), lua_str(s["mask"]), lua_str(s["anchor"]))
        for s in sigs) + "}"
    pas_lua = "{\n" + "".join("\t[%d] = %s,\n" % (int(k), lua_str(v))
                              for k, v in sorted(passives.items(), key=lambda kv: int(kv[0]))) + "}"
    desc_lua = "{\n" + "".join("\t[%d] = { %s },\n" % (int(k), ", ".join(lua_str(x) for x in v))
                               for k, v in sorted(descs.items(), key=lambda kv: int(kv[0]))) + "}"
    arm_lua = "{\n" + "".join("\t[%d] = { n = %s, p = %d },\n" % (int(k), lua_str(v["n"]), v["p"])
                              for k, v in sorted(armors.items(), key=lambda kv: int(kv[0]))) + "}"
    with open(os.path.join(HERE, "src", "passive_picker.lua"), encoding="utf-8") as fh:
        src = strip_personal(fh.read(), public)
    if public:
        spec = load("public.json")
        for change in spec["replace"]:
            if src.count(change["from"]) != 1:
                sys.exit("public.json: text must appear exactly once: %r" % change["from"][:60])
            src = src.replace(change["from"], change["to"])
        first = "-- HD2-Addon: mods/jarvis/passive_picker\n"
        if not src.startswith(first):
            sys.exit("addon line not where expected")
        src = src[len(first):]
        joined = spec["name"].replace(" ", "")
        src = src.replace("JarvisPassivePicker", joined)
        src = src.replace("JarvisPP", "".join(w[0] for w in spec["name"].split()) + "_")
        lead = spec["name"][:-len("Passive Picker")]   # e.g. "Simple Armor ": skip names already renamed
        src = re.sub(r"(?<!%s)PassivePicker" % re.escape(lead.replace(" ", "")), joined, src)
        src = re.sub(r"(?<!%s)Passive Picker" % re.escape(lead), spec["name"], src)
        src = "-- HD2-Addon: mods/%s/%s\n" % (spec["author"], spec["addon"]) + src
        if "passive_picker" in src.replace(spec["addon"], "") or "Jarvis" in src:
            sys.exit("public build still carries a personal name")
        for word in ("redraw", "card_refresh", "PERSONAL"):
            if word in src:
                sys.exit("public build still mentions %s" % word)
    for mark, text in (("--@SIGS@", sig_lua), ("--@PASSIVES@", pas_lua), ("--@ARMORS@", arm_lua), ("--@DESCS@", desc_lua)):
        if src.count(mark) != 1:
            sys.exit("placeholder %s must appear exactly once" % mark)
        src = src.replace(mark, text)
    out = os.path.join(HERE, "build-public" if public else "build")
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "passive_picker.built.lua"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write(src)
    name, blob = pack.build(src.encode("utf-8"))
    base = os.path.join(out, pack.ARCHIVE + ".patch_0")
    with open(base, "wb") as fh:
        fh.write(blob)
    if public:
        with open(os.path.join(out, "sigs.public.json"), "w", encoding="utf-8") as fh:
            json.dump(sigs, fh)
    for ext in (".gpu_resources", ".stream"):
        open(base + ext, "wb").close()
    print("built %s: %d bytes of Lua -> %s" % (name, len(src.encode("utf-8")), base))


if __name__ == "__main__":
    main()
