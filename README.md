# Simple Armor Passive Picker

Helldivers 2 mod by **vibeslacker**. Made with AI: the code was written by an AI and tested in the game by a human.

Pick which of your owned armor passives goes on the armor you are wearing, from a small box on the player card of the pre-mission loadout screen. F6 keeps it on that armor across armor changes and game restarts.

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
