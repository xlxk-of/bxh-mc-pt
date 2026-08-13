# Block X Hell — Godot 4.7 port

Port of the pygame build (`../../main.py`, `game_state.py`, `drawing.py`) to
Godot 4.7, targeting desktop and mobile from one codebase.

Built and tested with **GodotSteam 4.7.1** (`godotsteam.471.editor.win64.exe`).
It also opens in stock Godot 4.7 — the Steam layer degrades to a no-op.

## Layout

```
scripts/
  autoload/     cfg, cards, save_game, profile, audio_director, layout, juice,
                steam_manager, sin_tree_data
  core/         game_session.gd     -- the whole rules engine, no visuals
  game/         board_view.gd       -- playfield rendering + pointer input
  ui/           ui_kit, hud, screens, dialogs, card_icon, piece_preview,
                skill_tree_screen, touch_drag_scroll
  fx/           level_background, menu_shape_field, shockwave, crt.gdshader
scenes/main.tscn      entry point (a router; every screen is built in code)
assets/
  audio/{music,sfx}   3 tracks, 20 cues
  cards/frames/       26 x 15-frame turntable strips (fallback icons)
  models/             54 card/item models (27 sculpted .glb, 27 primitive .tscn)
  fonts/              Warpixes (display), Sixtyfour Convergence (numerals)
web/head_include.html themed loader for the web/PWA build
test/                 loop, meta, model_frames, scroll_touch, mobile_shots,
                      screenshot, diag harnesses
```

`GameSession` owns no nodes that draw. It mutates state and emits signals;
scenes render from those signals. That is what lets `test/loop_test.tscn` play
thousands of turns headlessly.

## Content and progression

40 cards, 14 items, 12 perks, 5 contracts. Every entry declares an `asset` key
that resolves to `assets/models/<key>/<key>.{glb,tscn}`; `Cards.model_scene()`
tries both, so a hand-sculpted model and one composed from primitive meshes are
indistinguishable to the UI.

`Profile` is the only state that outlives a run. Dying pays out **Soul Embers**
(scaled to rounds survived and score), spent in the **Sin Tree**: seven sins of
five tiers each, 35 nodes, reached from the main menu. A node is only readable
once its prerequisite is owned, so the tree reveals itself as it is bought.
`SinTreeData` holds the graph; each node names one `effect_key`, and
`Profile.bonus(key)` returns the summed value of everything owned that carries
it - so two nodes in a branch stack rather than overwrite. `game_session.gd`
reads those bonuses at the natural site for each (starting money and slots in
`reset_run()`, score and combo at their calculation sites). The sums are cached
and invalidated on purchase, because `bonus()` is called per placement.

## Running the tests

```bash
godot --headless --path . res://test/loop_test.tscn     # 645 assertions, rules
godot --headless --path . res://test/meta_test.tscn     # 325 assertions, Sin Tree
godot --path . res://test/model_frames.tscn             # every model, 8 angles
godot --path . res://test/scroll_touch.tscn             # drag vs tap
godot --path . res://test/mobile_shots.tscn             # phone layouts + metrics
godot --path . res://test/screenshot.tscn               # writes user://shots/
godot --path . res://test/diag.tscn                     # layout + font probe
```

`loop_test` covers every card, item, perk and contract, both revive paths, the
Giga Boss cycle, a JSON save round-trip, column collapse, and a six-run soak. It
also asserts that every table entry is named somewhere in `game_session.gd` -
content that buys, equips and renders while doing nothing is the failure mode
that no behavioural test notices.

`meta_test` asserts the Sin Tree is an acyclic graph whose prerequisites all
exist, that embers cannot be spent twice or into debt, that a locked node stays
hidden until it is reachable, and that the lot survives a save round trip.

`model_frames` renders every card and item model at icon size through eight
turntable angles and fails on any pixel touching the border. That is what "the
model is cut off" looks like in pixels, and it caught 6 of 27 before the camera
fit was rewritten.

`mobile_shots` fakes an iPhone 16 Pro's CSS geometry and asserts the physical
metrics (tap targets in points, body type, drag lift), that no screen overflows
its viewport width, that a drag starting on a Buy button scrolls without buying,
and that a tap on that same button still buys.

## Controls

| Action | Touch | Mouse / keyboard |
| --- | --- | --- |
| Place a piece | drag from the tray, release on the board | click a piece, then click a cell — or drag |
| Aim | piece floats ~112pt above the finger and tracks finger *motion* at 1.5x (Settings → Drag speed, 1.0–3.0), so a short flick from the tray reaches the top row; drops snap up to 2 cells | ghost follows the cursor 1:1 |
| Aim, Direct mode | piece sits under the finger, 1:1 | — |
| Board ghost | only while a piece is held or a finger is down on the board | always, tracking the cursor |
| Scroll a list | drag anywhere, including across buttons and cards | wheel or scrollbar |
| Card special action | press and hold | right-click |
| Pocket Dimension | double-tap a piece / the pocket | double-click |
| Cancel a targeted item | back gesture | Esc or right-click |
| Pause / settings | ≡ button | Esc |

## Scaling

`Layout` pins the window's stretch base to the live window size, so
`content_scale_factor` is the only scale knob. It targets a fixed number of
logical pixels on the **short** side — 720 desktop landscape, 640 desktop
portrait, 640/560 phone, 820 tablet — which is what makes a tall narrow window
scale *up* instead of shrinking the UI into a corner. `HUD` rebuilds between a
three-column landscape layout and a stacked portrait layout on orientation
change.

Anything that has to be *physically* big — tap targets, body copy, the drag
lift — is specified in points and multiplied by `Layout.points_to_logical()`.
A phone is deliberately handed more logical pixels than it has points (620
logical across a 402pt screen), so a raw "60px" button really renders at 39pt,
under the 44pt HIG floor. Touch mode itself is detected from the platform, then
the browser's pointer hardware, and finally from the first real touch event —
whichever fires first wins, and **Settings → Touch layout** overrides all three
for browsers that report a desktop user agent from a home-screen PWA.

## Steam

`SteamManager` initialises through whichever `steamInitEx` signature the build
exposes, runs callbacks when needed, and no-ops when the singleton is missing.
Eight achievements are defined in `ACHIEVEMENTS` and fired from `main.gd`.
Set your real AppID in `steam_appid.txt` (currently `480`, the public test app)
and create matching achievement API names in Steamworks.

## Notes on differences from the pygame build

* **Star Streak worked as a no-op.** The card was declared `"Star Streak"` but
  every effect lookup asked for `"Star Streaks"`, so it never granted its extra
  combo miss. The port uses one spelling and the card now works as described.
* **The Giga Boss picked two targets per placement.** The first random pick was
  immediately overwritten by the warned target (or by `-1`), so its
  "Targeting Row N!" message was always a lie. The port keeps only the
  warn-then-fire path.
* **PixelGamer is not used for any player-facing text.** The bundled build is
  the personal-use version, which substitutes a watermark glyph for every digit
  and punctuation mark. Titles and buttons use Warpixes, numerals use Sixtyfour
  Convergence, body copy uses the engine default — the same split the pygame
  build had, where only the title used a custom face.
* **CRT curvature defaults to 0.** The pass draws over the live UI, so warping
  would move pixels out from under the cursor and the player's finger. The
  original compensated by inverse-distorting the mouse; scanlines, grille,
  aberration and vignette are all still on.
* **Two cards had no 3D model.** Shape Shifter had only a Blockbench source, and
  Barrel had nothing. `Shape Shifter` was converted from `shapeshifter.bbmodel`;
  `Barrel` was authored from scratch in the same voxel style.
