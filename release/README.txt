Simple Armor Passive Picker 1.4.1
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
  71 on most armors).
  The Armory adds the armor's own passive bonus on top of the rating you pick:
  Extra Padding adds 50 and Unflinching adds 25, so a pick of 150 reads 200 or
  175 there. The box shows the number you picked; the passive's bonus is extra.
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
- Rest the cursor half a second on a passive (in the grid, or the box) and a
  small box beside it describes what that passive does. Descriptions are from
  the Helldivers wiki, so they can lag a balance patch.
- Controller: click the right stick on the loadout screen to open the
  passive grid. In a grid: D-pad or left stick moves, A picks, B closes,
  Y keeps the pick for good (same as F6), LB goes to the rating grid, RB
  back to the passive grid. Works with Xbox pads and any pad Steam Input
  handles (PlayStation, Switch, most USB pads). See CONTROLLER below.
- New in 1.4.1: click the left stick to open the rating grid (same
  open, close and switch as the right stick does for passives). Three rows,
  Open Passive Grid, Open Rating Grid and Hard Set Armor, also show up under
  MODS > PASSIVE PICKER on the game's keyboard and controller binding pages
  when Mod Bindings Menu is installed, so you can rebind them there.
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

CONTROLLER
pad = 0 turns the controller off. pad_open picks the button that opens
the grid: 1 = right stick click (default), 2 = left stick click (DiverKit
uses that one too), 3 = Back/View, 4 = Start, 0 = none. pad_open_rating
is the same for the rating grid (default 2 = left stick click, 0 = none).
An old USB pad that Windows shows only as a plain joystick (not as an
Xbox pad) works too: it moves with its D-pad or stick, and its buttons
are set by number (joy_open 12, joy_pick 2, joy_close 3, joy_set 4,
joy_prev 5, joy_next 6). Not sure of your numbers? Press the buttons on
the loadout screen and the log names each one.
If Steam Input is on for the game (the default), your pad shows as an
Xbox pad and none of the joy_ settings matter.

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
1.4.1  New: rest the mouse (or the W/S or pad highlight) on a passive in the
       grid, or on the passive box, for half a second and a box beside it
       tells what that passive does. Left stick click opens the rating grid.
       Open Passive Grid, Open Rating Grid and Hard Set Armor rows on the
       MODS tab of the game's binding pages (needs Mod Bindings Menu). Not
       yet confirmed: that a controller button set on that page reaches the
       mod. Keyboard keys
       set there are known to work in other mods. Built for game build
       25480438; it needs the loader and a matching update after later builds.
1.3.0  Fixed: the rating box did nothing on about a third of the armors
       (UF-50 Bloodhound, BP-20 Correct Officer, B-01 Tactical and others).
       Controller support (asked for by a player): right stick click opens
       the grid, D-pad or left stick, A, B, Y, LB, RB do the rest. The
       mod's own time per second goes in its log once a minute, and the
       worn armor is read less often during missions.
       Easier to read: the rating grid is centered and larger, the pick is
       a solid gold bar, and the bar the cursor is on gets a gold frame.
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
