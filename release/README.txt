Simple Armor Passive Picker 1.2.0
by vibeslacker
Made with AI.

Pick the armor passive and the armor rating you want on the armor you like.

WHAT IT DOES
Two boxes of the same width sit side by side on your player card on the
pre-mission loadout screen.
- The rating box (left) shows the armor's rating, e.g. ARMOR RATING 79.
  Click it to pick 50, 64, 70, 79, 100, 129, 150 or ORIGINAL: every rating
  the game's own armors have, odd ones included. The rating sets speed and
  stamina too, exactly as on a stock armor with that rating (79 is a little
  slower than 50). ORIGINAL gives the armor its own stats back.
  Some armors are built from fewer pieces, so their steps are coarser: the
  grid shows the nearest number that armor can really make (70 comes out as
  71 on most armors). Passive bonuses such as Extra Padding still add on top
  in the Armory, as usual.
- The passive box (right) shows the passive of the armor you are wearing.
  Click it and a grid opens with every passive you own. Pick one and it goes
  on the armor you are wearing.
The look of the armor never changes.

- Only passives from armor you already own are offered.
- A pick is for the armor you are wearing. Put on a different armor and
  the one you left goes back to its own passive and rating. Make your change just
  before you dive.
- Press F6 on the loadout screen to keep the passive and the rating on that
  armor for good, through armor changes and game restarts. The boxes then
  show [SET]. To undo, pick ORIGINAL and the armor's own passive (marked *) and
  press F6 again.
- Mouse, or W/A/S/D and Space once a grid is open.
- The boxes and the grids can be dragged anywhere. Their spots are saved.

REQUIREMENTS
- Bingus Shared Loader v15 or newer. Put the loader last in your load order.
- Made for game build 25480438. After a game update the mod checks the
  game's code first. If the code has changed it switches itself off and says
  why in its log.

INSTALL
1. Close the game.
2. Add this zip to your mod manager, along with Bingus Shared Loader.
3. Enable both and deploy.
4. Start the game and open a mission's loadout screen.

SETTINGS AND FILES
In %LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs:
- SimpleArmorPassivePicker.cfg    settings, each one explained in the file.
                             Re-read while the card is on screen.
- SimpleArmorPassivePicker.saved  your F6 hard sets (passive and rating).
- SimpleArmorPassivePicker.log    what the mod did this session.

set_key is the hard-set key as a Windows key number (117 = F6, 0 = off).
If you also run DiverKit, it is paused while your mouse is on a box or a
grid is open, so a click cannot press a DiverKit button underneath.
hold_diverkit = 0 turns that off.

GOOD TO KNOW
- Made with AI: the code was written by an AI and tested in the game by a
  human.
- This mod changes game memory while the game runs. It is a gameplay change
  in an online game. Use it at your own risk.
- It unlocks no armor and offers only passives from armor you own.
- No network access. Nothing leaves your computer.
- Brewed on Linux with Proton. Windows is untested so far.

UNINSTALL
Close the game, disable or remove the mod, deploy. Delete the three
SimpleArmorPassivePicker files if you want no trace.

THANKS
CowboyBingus for Bingus Shared Loader.
RatInPlat, author of HD2 Transmog Foundation, and tanau4, author of
DiverKit, whose mods showed me where the game keeps things. This mod
contains none of their code and needs neither installed.

CHANGES
1.2.0  Armor rating: the class box now picks a rating number, 50, 64, 70,
       79, 100, 129 or 150, instead of LIGHT, MEDIUM or HEAVY, so the odd
       stock ratings can be picked too, and armors that have one can be
       changed and put back cleanly. Hard sets from 1.1.0 carry over (light,
       medium, heavy become 50, 100, 150).
1.1.0  Armor class: a second box picks LIGHT, MEDIUM, HEAVY or ORIGINAL for
       the armor you are wearing. F6 keeps the class too. The two boxes now
       split the card evenly (your old box spot is reset once). Your other
       settings and your hard sets carry over.
1.0.1  First public release (1.0 renamed).
