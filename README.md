# Simple Armor Passive Picker

Helldivers 2 mod by **vibeslacker**. Made with AI: the code was written by an AI and tested in the game by a human.

Pick which of your owned armor passives goes on the armor you are wearing, and its armor rating (50 to 150, including the odd stock ones: 64, 70, 79, 129), from two small boxes on the player card of the pre-mission loadout screen. The look stays the same. F6 keeps both on that armor across armor changes and game restarts. Mouse, keyboard or controller (XInput, read only, plus a plain-joystick fallback through winmm).

A rating change swaps one 8-byte pointer: the armor's record (+48) points at its body pieces, each carrying a weight (0 light, 1 medium, 2 heavy). Rating = 50 + 50 x the average weight of the armor pieces in slots 2, 4, 5, 6, 7, 8 and 9 (slots 1 and 3 count for nothing); speed and stamina follow it. This reproduces every stock armor's rating. The mod copies the pieces once per armor and rating with the weights set for that rating (slots 6, 7, 8, 9 raised first, then 2, 4, 5, as the stock odd armors do), points the record at the copy, and never writes or frees the game's own pieces. Kit records are only 4-byte aligned, so the write is allowed only inside one 64-byte cache line. Layout learned from HD2 Transmog 0.2.2; `tools/probe_classes.py` reads it read-only from the running game.

- **Download:** the zip under [Releases](../../releases), or on [Nexus Mods](https://www.nexusmods.com/helldivers2/mods/17393).
- **Needs:** [Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader) v15 or newer, loaded last.
- **Player docs:** [`release/README.txt`](release/README.txt) (the readme inside the zip).

## Building from source

Python 3 and LuaJIT.

```
python3 build.py public          # build-public/: the mod as released
python3 build.py                 # build/: the author's personal build (extra DiverKit tile redraw)
luajit test/harness.lua build-public/passive_picker.built.lua build-public/sigs.public.json <scratch dir> [nofont|badinput|saved]
luajit check.lua build-public/passive_picker.built.lua    # lists accidental globals; no output = clean
python3 tools/make_release.py build-public release Simple-Armor-Passive-Picker-<version>.zip
```

- `src/passive_picker.lua` is the one source. Lines between `--@PERSONAL_BEGIN@` and `--@PERSONAL_END@` are left out of the public build; `data/public.json` holds the public build's name and defaults.
- `data/` holds facts about game build 25480438: code signatures, armor ids with their default passive, passive names. `tools/make_sigs.py` remakes the signatures from a dump of the game's code after an update.
- `test/harness.lua` runs the built mod against a fake game, frame by frame. It proves the mod's own logic, not the game's layout.

## Thanks

CowboyBingus for Bingus Shared Loader. RatInPlat (HD2 Transmog Foundation) and tanau4 (DiverKit), whose mods showed where the game keeps things. This mod contains none of their code and needs neither installed.

## Support

If you like my mods, you can support me at https://ko-fi.com/vibeslacker
