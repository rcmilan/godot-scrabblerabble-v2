# Upgrade Wizard — Implementation Tasks

Implementation plan for `docs/upgrade_wizard_design.md`. Read that
file first; this file says *what to build in what order*, the design
doc says *why*.

## How to work through this file

- Do the slices **in order**. Each slice leaves the game fully
  working (boots, plays, autoplay run exits 0), so commit and push
  after every slice.
- Run the **verification steps at the end of each slice** before
  moving on. If verification fails, fix the slice — do not start the
  next one.
- One commit per slice. Style: `feat:`/`fix:` headline + 2–5 body
  lines, like recent commits.
- Conventions (from `CLAUDE.md`):
  - snake_case files/nodes-in-scripts/vars/functions; tabs in GDScript.
  - Log state transitions with a prefix. New prefix for this feature:
    `[UpgradeWizard]`. Sim-side logs keep `[GameCore]`.
  - Project theme `themes/win95.tres` is the default — use
    `theme_type_variation`, never set `theme` on nodes inside the
    main scene tree.
  - No comments that restate code. No `randi()`/`randf()` in sim code
    (use `GameCore`'s seeded `rng`); global `randi()` is fine in live
    UI code (`main.gd` already does this).
  - If you change offer logic in `main.gd`, mirror it in
    `scripts/sim/game_core.gd` in the SAME slice.

## Verification commands (used by every slice)

```
# sim tests — all TC/TS/TSM cases must pass:
godot --headless --path . --script res://scripts/sim/tests/run_tests.gd

# full autoplay loop — must exit 0 (124 = hung) and reach an upgrade
# round (round 4) in most runs:
timeout 180 godot --headless --path . -- --autoplay=word_search; echo "exit: $?"
```

## Facts you need (verified against the codebase)

- Upgrade flow lives in `scripts/main.gd`: `_show_upgrade_dialog`
  (~line 296), `_show_letter_picker` (~329), `_generate_letter_options`
  (~357), `_autoplay_pick_letter` (~367), `_autoplay_pick_upgrade_dialog`
  (~381). Trigger: `_on_transition_finished` → `RunState.is_upgrade_due()`.
- Dialog scenes: `scenes/upgrade_dialog.tscn` (240×160) +
  `scripts/upgrade_dialog.gd`; `scenes/letter_picker_dialog.tscn` +
  `scripts/letter_picker_dialog.gd`; cards: `scripts/upgrade_item.gd`
  (gradient/bevel/nav code), `scripts/letter_item.gd` (tile face
  drawing). Both dialogs go on a CanvasLayer, `layer = 50`.
- `RunState.letter_modifiers` is the owned-modifier dict
  (`{"E": "2x"}`); `RunState.set_letter_modifier` stores;
  `rack.refill()` applies. `RunState.is_upgrading` gates
  `main.gd::_unhandled_input` (line 50).
- Sim mirror: `scripts/sim/game_core.gd:206-217` (upgrade auto-pick
  inside `end_turn`), `_generate_letter_options` further down in the
  same file. Test TSM10: `scripts/sim/tests/test_game_core.gd:352`.
- `LETTER_DISTRIBUTION` and `LETTER_POINTS` live in
  `scripts/game_data.gd` (autoload `GameData`) and are mirrored as
  consts in `game_core.gd`.
- Focus-border bug: `upgrade_item.gd:47-48` draws the focus rect on
  the whole control instead of the body rect (drawn at y=4).
- Win95 navy `Color(0, 0, 0.5019)`; 2x gradient navy→sky-blue and 3x
  gradient dark-green→green constants are in `upgrade_item.gd:16-19`.
- Center dialogs with `custom_minimum_size`, never `size`, in
  `_ready` (Godot layout quirk; see `main.gd:396-399`).

---

## Slice 1 — Modal blocker + focus-border fix (current dialogs)

**Goal:** ship the two bug fixes on the EXISTING dialogs before any
redesign. Players can no longer click the board/rack while a modal is
up; the yellow cursor hugs the tile.

### 1a. Full-screen blocker under the upgrade dialogs

In `main.gd::_show_upgrade_dialog`, right after creating the
CanvasLayer and BEFORE adding the dialog, add:

```gdscript
var blocker := Control.new()
blocker.name = "ModalBlocker"
blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
blocker.mouse_filter = Control.MOUSE_FILTER_STOP
layer.add_child(blocker)
```

The dialog is added after, so it draws above the blocker. The letter
picker is added to the same layer, so it is covered too. Do the same
in `_on_game_over` for the game-over dialog layer.

### 1b. Tight focus border

In `upgrade_item.gd::_draw`, the body rect is already computed
(`body_rect`). Change the focus draw from the control rect to:

```gdscript
if has_focus():
    draw_rect(body_rect.grow(2.0), C_FOCUS_BORDER, false, 2.0)
```

In `letter_item.gd::_draw`, the tile face fills the control only at
minimum size; compute the same centered 56×56 rect and draw the focus
border around it (mirror the `body_rect` approach: centered x, full
BODY_SIZE), instead of `Rect2(Vector2.ZERO, size)`.

### Verify slice 1

1. Sim tests pass; autoplay run exits 0 (neither touches drawing).
2. With a window: reach round 4 (or temporarily set
   `UPGRADE_EVERY_N_ROUNDS = 1` in `run_state.gd` while testing —
   REVERT before committing). While the upgrade dialog is up: click
   board cells, drag rack tiles — nothing happens, focus stays in the
   dialog. The yellow border sits exactly around the tile body.

Commit slice 1.

---

## Slice 2 — Composite offer generation + sim mirror

**Goal:** the data model changes from "one modifier, then a letter"
to "three `{letter, modifier}` offers". The LIVE UI still shows the
old two-step flow in this slice (wired to offer[0]'s modifier); the
full UI lands in slice 3. The sim switches to the new generator NOW
so live/sim never diverge.

### 2a. Live generator in `main.gd`

Add (near `_generate_letter_options`):

```gdscript
const UPGRADE_OFFER_COUNT: int = 3

func _generate_upgrade_offers() -> Array[Dictionary]:
    var pool: Array[String] = []
    for letter in GameData.LETTER_DISTRIBUTION:
        if RunState.letter_modifiers.has(letter):
            continue
        for i in GameData.LETTER_DISTRIBUTION[letter]:
            pool.append(letter)
    var offers: Array[Dictionary] = []
    var picked: Array[String] = []
    while offers.size() < UPGRADE_OFFER_COUNT and not pool.is_empty():
        var letter: String = pool[randi() % pool.size()]
        if picked.has(letter):
            continue
        picked.append(letter)
        var mod: String = GameData.MOD_3X if randi() % 3 == 0 else GameData.MOD_2X
        offers.append({"letter": letter, "modifier": mod})
    if offers.size() < UPGRADE_OFFER_COUNT:
        print("[UpgradeWizard] letter pool exhausted — offering %d" % offers.size())
    return offers
```

Notes: weighting comes from pushing each letter `distribution` times
into the pool; distinctness from the `picked` check; unowned from the
`letter_modifiers` skip. **Required guard:** the `while` spins forever
once every distinct pool letter is in `picked` — count the distinct
letters in `pool` up front and break when `picked` reaches that count.

### 2b. Sim mirror in `game_core.gd`

Replace lines 206–217 (the auto-pick block inside `end_turn`) with a
mirror: build the same weighted pool from the mirrored
`LETTER_DISTRIBUTION` consts, excluding `letter_modifiers` keys, using
`rng.randi()` (NEVER global `randi()`), produce 3
`{letter, modifier}` offers, then pick the offer maximizing
`LETTER_DISTRIBUTION[letter] * LETTER_POINTS[letter] * (3 if mod == MOD_3X else 2)`,
ties broken by offer order. Keep the
`print("[GameCore] upgrade auto-pick — %s → %s" % [mod, letter])` log.
Extract the generator into a named func (`_generate_upgrade_offers`)
so TSM tests can call it directly.

### 2c. Update TSM10, add TSM11 in `test_game_core.gd`

- TSM10 (line ~352): still asserts `letter_modifiers` has entries
  after rounds 4 and 7 and values are MOD_2X/MOD_3X. Should pass
  unchanged — run it; if it inspects letter choice specifics, adapt.
- New TSM11: with a fixed seed, (a) call `_generate_upgrade_offers`
  with some letters pre-owned in `letter_modifiers` and assert no
  offer contains an owned letter and all 3 letters are distinct;
  (b) run the same seed twice and assert identical offers (determinism).
  Register TSM11 in `run_tests.gd` following how TSM10 is registered.

### 2d. Temporary live wiring

In `_show_upgrade_dialog`, replace the `offered_id := ...randi()...`
line with:

```gdscript
var offers := _generate_upgrade_offers()
var offered_id: String = offers[0]["modifier"] if not offers.is_empty() else GameData.MOD_2X
```

(The old dialog still shows one modifier and the letter picker still
runs — that's fine for this slice; slice 3 replaces it.)

### Verify slice 2

1. Sim tests: TSM10 passes, TSM11 passes, everything else unchanged.
2. Autoplay run exits 0 and the log shows
   `[GameCore]`-style... correction: live autoplay logs come from the
   live game — confirm `[RunState] letter modifier set — ...` still
   appears after round 4 and the chosen letter is never repeated
   across two upgrades in one run.

Commit slice 2.

---

## Slice 3 — Single-dialog card UI (replaces the letter picker)

**Goal:** the upgrade dialog shows three composite offer cards;
selecting one and confirming applies it immediately. The letter
picker is DELETED. Chrome is still the plain old dialog — the
InstallShield dressing lands in slice 4.

### 3a. Evolve `scripts/upgrade_item.gd` into the offer card

Keep `class_name UpgradeItem`, nav signals, gradient/bevel helpers.
Changes:

- New state: `var letter: String`, `var modifier: String`,
  `var is_selected: bool = false` (plus `item_index` as today).
- `BODY_SIZE` stays 56×56 (tile size). Control min size ≈ 88×96
  (tile + "×2" line + "12 in bag" line + padding).
- `_draw()`: centered 56×56 tile face — modifier gradient body
  (reuse `_draw_mod2x_body`/`_draw_mod3x_body` gradients), bevel,
  letter centered white 24px, point value white 9px bottom-right
  (absorb the face-drawing from `letter_item.gd::_draw`, but white
  labels since every offer has a modifier — `tile.gd` modifier
  variant uses white). Below the tile: `×2`/`×3` (16px, navy for 2x /
  dark-green for 3x), then `%d in bag` (9px, gray
  `Color(0.251, 0.251, 0.251)`).
- **Selection border** (yellow, 2px) drawn around
  `tile_rect.grow(2.0)` when `is_selected` — NOT around the control
  rect, and NOT keyed on `has_focus()` alone (focus follows selection
  but selection is the source of truth).
- Signals: replace `pick_requested` with `selected(index: int)` and
  `confirmed(index: int)`. Wiring in `_gui_input` / focus:
  - single left click → `grab_focus()` + emit `selected`
  - double-click (`event.double_click`) → emit `confirmed`
  - `ui_accept` (Enter/Space) → emit `confirmed` — this IS the
    "Enter activates the default Next button" behavior from the
    design, implemented at the card level (same outcome, no extra
    default-button plumbing)
  - `focus_entered` → emit `selected` (so keyboard arrows select)

### 3b. Rework `scripts/upgrade_dialog.gd` + scene

- `populate(offers: Array[Dictionary])` builds one card per
  `{letter, modifier}` dict; first card `is_selected = true` and
  grabs focus.
- Track `_selected_index`; on any card's `selected`, update it and
  `queue_redraw` all cards; update the caption label (add a Label
  under the card row in the scene, 2 lines reserved height,
  `autowrap_mode = 3`): text per design copy
  (`Every E tile scores double points for the rest of the run.` /
  `triple` for 3x).
- Signal out: keep `upgrade_picked` but change payload to the full
  offer Dictionary (`upgrade_picked(offer: Dictionary)`); keep
  `skipped`.
- Skip button keeps working as today (Cancel/wizard row is slice 4).

### 3c. Rewire `main.gd`

In `_show_upgrade_dialog`:

```gdscript
var offers := _generate_upgrade_offers()
...
dialog.populate(offers)
dialog.upgrade_picked.connect(func(offer: Dictionary) -> void:
    RunState.set_letter_modifier(offer["letter"], offer["modifier"])
    rack.refill()
    layer.queue_free()
    RunState.is_upgrading = false
    board.focus_cell(cursor)
    _update_hud()
)
```

(This is the body that used to live in the letter picker's
`letter_picked` handler — move it, don't reinvent it.)

### 3d. Delete dead code

Delete: `scenes/letter_picker_dialog.tscn`,
`scripts/letter_picker_dialog.gd`, `scripts/letter_item.gd`, their
`.uid` files, and in `main.gd`: `_show_letter_picker`,
`_generate_letter_options`, `_autoplay_pick_letter`, and the
`LETTER_PICKER_SCENE` preload. Grep for `letter_picker` and
`letter_item` afterwards — zero hits outside docs/ and git history.

### 3e. Autoplay pick (heuristic)

Replace `_autoplay_pick_upgrade_dialog` with:

```gdscript
func _autoplay_pick_upgrade_dialog(dialog: UpgradeDialog, offers: Array[Dictionary]) -> void:
    await get_tree().create_timer(1.0).timeout
    if not is_instance_valid(dialog) or offers.is_empty():
        return
    var best: Dictionary = offers[0]
    for offer in offers:
        if _offer_value(offer) > _offer_value(best):
            best = offer
    print("[UpgradeWizard] autoplay pick — %s ×%s" % [best["letter"], best["modifier"]])
    dialog.upgrade_picked.emit(best)

func _offer_value(offer: Dictionary) -> int:
    var mult := 3 if offer["modifier"] == GameData.MOD_3X else 2
    return GameData.LETTER_DISTRIBUTION[offer["letter"]] * GameData.LETTER_POINTS[offer["letter"]] * mult
```

Same heuristic as `game_core.gd` (slice 2b) — they must agree.

### Verify slice 3

1. Sim tests pass.
2. Autoplay exits 0; log shows `[UpgradeWizard] autoplay pick — ...`
   then `[RunState] letter modifier set — ...` at rounds 4, 7…
3. Grep check from 3d is clean.
4. With a window: at round 4 the dialog shows 3 distinct cards;
   arrows move the yellow selection; caption updates; Enter or
   double-click applies; new rack tiles of that letter show the
   gradient; board/rack unclickable behind the blocker; Skip works.

Commit slice 3.

---

## Slice 4 — InstallShield chrome

**Goal:** the dialog becomes the full wizard: banner, slim title bar,
`< Back | Next > | Cancel` row, X = Skip.

All in `scenes/upgrade_dialog.tscn` + `scripts/upgrade_dialog.gd`:

- **Size:** `custom_minimum_size = Vector2(430, 260)`.
- **Title bar:** text "Upgrade Wizard". DELETE MinBtn and MaxBtn from
  the scene; keep CloseBtn, wired to the same handler as Skip.
- **Body becomes an HBoxContainer:** left = Banner (Control,
  `custom_minimum_size = Vector2(96, 0)`, full height), right = the
  existing content VBox (header label "Choose an upgrade to
  install:", card row, caption, button row).
- **Banner drawing** (script on the Banner node or in the dialog's
  `_draw` — banner node is cleaner): vertical navy→black gradient
  (adapt `_draw_horizontal_gradient` to vertical: iterate rows,
  `Color(0, 0, 0.5019).lerp(Color.BLACK, t)`), then a child Label,
  text "ScrabbleRabble 95", white, `rotation = -PI / 2`, positioned
  to read bottom-to-top, font size ~16.
- **Button row** (right-aligned HBox): `BackButton` text "< Back",
  `disabled = true`, `focus_mode = FOCUS_NONE`; `NextButton` text
  "Next >", commits the selected offer (same path as `confirmed`);
  `CancelButton` text "Cancel" = Skip. Wire `ui_accept` fallthrough:
  cards' `ui_accept` already confirms (slice 3a), which is
  functionally Enter-activates-Next; ALSO `grab_focus`-able Next must
  confirm on press. 88×24 buttons, 8px separation.
- **Logs:** `[UpgradeWizard] shown — 3 offers`,
  `[UpgradeWizard] selected — E ×2`,
  `[UpgradeWizard] confirmed — E ×2`, `[UpgradeWizard] skipped`.
- Keep the blocker and layer wiring untouched.

### Verify slice 4

1. Sim tests pass; autoplay exits 0 (autoplay emits `upgrade_picked`
   directly, so wizard chrome must not break that signal path —
   verify the round-4 pick still lands).
2. With a window: banner gradient + rotated title render; Back is
   gray and unreachable by Tab/arrows; Next commits the selection;
   Cancel and X both skip; Enter confirms from anywhere in the dialog.

Commit slice 4.

---

## Slice 5 — Docs

**Goal:** record the new contract where sim docs live.

Append to `scripts/sim/README.md` (after the start-screen section):
a short "Upgrade wizard parity" section stating:

- Offers: 3 distinct, distribution-weighted, unowned letters;
  independent 67/33 2x/3x rolls. Generator duplicated in `main.gd`
  and `game_core.gd::_generate_upgrade_offers` — change both together.
- Auto-pick heuristic (autoplay + sim):
  `LETTER_DISTRIBUTION × LETTER_POINTS × multiplier`, ties by offer
  order.
- Test coverage: TSM10 (intervals), TSM11 (distinct/unowned/
  deterministic offers).
- Expected autoplay log lines at upgrade rounds:
  `[UpgradeWizard] autoplay pick — ...` →
  `[RunState] letter modifier set — ...`.

Also update `CLAUDE.md`'s tile-modifiers section sentence listing the
mirror-relevant files if it names the letter picker (grep
`letter_picker` in CLAUDE.md; update if present).

### Verify slice 5

1. Sim tests one final time → pass.
2. One final autoplay run → exit 0, upgrade log lines present.

Commit slice 5. Push the branch.

---

## Out of scope — do NOT build these

Upgrade paths on owned letters, skip compensation, build-visibility
strip/HUD chips, upgrade telegraphing, modal open animations, new
modifier types, per-entry-point input guards (blocker only — one
accepted edge: a drag started before the modal can still drop after).
If something seems missing, check `docs/upgrade_wizard_design.md`
"Explicitly out of scope" first.
