# Upgrade Wizard — Fix Tasks (tile-appearance polish)

> The container rebuild + navigation fixes from the previous version of
> this file are **shipped and confirmed working** (centered modal,
> gray frame covers everything, 2-column grid, banner gradient + title,
> arrow-key navigation). This file now covers the remaining **tile
> appearance** polish on the offer cards.

The offer card's tile face is *almost* the real in-game tile, but two
things make it hard to read and off-brand:

1. It draws a redundant **"2x" / "3x"** label below the tile.
2. The on-tile **point value** is drawn in dark gray, which is nearly
   invisible on the blue/green gradient. The real modifier tile
   (`tile.gd`) draws it **white**.

Goal: the card's tile should look **exactly like the tile will look in
the shop / rack** — gradient body, white 24px letter, white 9px point
value, bevel — and nothing else on the tile. The "X in bag" line below
stays, just bigger.

**File touched:** `scripts/upgrade_item.gd` only.
**Do NOT touch** anything else — layout, navigation, sim, offer
generation are all correct. No `godot` binary here; the human runs the
game to verify.

Reference (the real modifier tile, `scripts/tile.gd::_refresh_visual`):
both the letter and the point value use white (`C_LABEL_MOD =
Color(1,1,1,1)`) when a modifier is present. Every offer card is always
a modifier tile, so both are always white.

---

## Task A — Point value white (the readability fix)

The point value is drawn with `C_LABEL_POINT`, defined as dark gray.
Since every card is a modifier tile, make it white to match the shop
tile. Change the constant definition near the top of
`scripts/upgrade_item.gd`:

```gdscript
# was: const C_LABEL_POINT          := Color(0.251, 0.251, 0.251, 1.0)
const C_LABEL_POINT          := Color(1.0, 1.0, 1.0, 1.0)
```

(`C_LABEL_POINT` is only used for the on-tile point value, so this is
the whole fix. The letter is already white via `C_LABEL_LETTER`.)

---

## Task B — Remove the "2x/3x" label, enlarge "X in bag"

In `scripts/upgrade_item.gd::_draw`, find the block that draws the
modifier text and the bag count below the tile. It currently looks like
this:

```gdscript
	# Draw modifier text below tile (×2 or ×3)
	if font:
		var mod_text := "2x" if modifier == GameData.MOD_2X else "3x"
		var mod_color := C_MOD_TEXT_2X if modifier == GameData.MOD_2X else C_MOD_TEXT_3X
		var font_size_mod := 16
		var mod_size := font.get_string_size(mod_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_mod)
		var mod_pos := Vector2(
			body_x + (BODY_SIZE.x - mod_size.x) * 0.5,
			tile_rect.position.y + BODY_SIZE.y + 2.0
		)
		draw_string(font, mod_pos, mod_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size_mod, mod_color)

		# Draw bag count below modifier (small gray text)
		var bag_count: int = GameData.LETTER_DISTRIBUTION.get(letter, 0)
		var bag_text := "%d in bag" % bag_count
		var font_size_bag := 9
		var bag_size := font.get_string_size(bag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_bag)
		var bag_pos := Vector2(
			body_x + (BODY_SIZE.x - bag_size.x) * 0.5,
			tile_rect.position.y + BODY_SIZE.y + 18.0
		)
		draw_string(font, bag_pos, bag_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size_bag, C_BAG_COUNT)
```

Replace that **entire block** with just the bag count, bigger and moved
up to sit directly under the tile (the "2x/3x" line is gone):

```gdscript
	# Draw "N in bag" below the tile
	if font:
		var bag_count: int = GameData.LETTER_DISTRIBUTION.get(letter, 0)
		var bag_text := "%d in bag" % bag_count
		var font_size_bag := 12
		var bag_size := font.get_string_size(bag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_bag)
		var bag_pos := Vector2(
			body_x + (BODY_SIZE.x - bag_size.x) * 0.5,
			tile_rect.position.y + BODY_SIZE.y + 16.0
		)
		draw_string(font, bag_pos, bag_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size_bag, C_BAG_COUNT)
```

Changes: dropped the modifier-text draw entirely; bag font 9 → 12; bag
baseline `+18` → `+16` so it tucks just under the tile now that the
"2x/3x" line is gone.

---

## Task C (optional cleanup) — Remove now-unused constants

After Task B, `C_MOD_TEXT_2X` and `C_MOD_TEXT_3X` are no longer
referenced. Delete their two `const` lines near the top of
`scripts/upgrade_item.gd` to keep the file clean. (Skip if unsure —
unused constants are harmless and won't break anything.)

---

## Manual check (human, with a window)

At an upgrade round, confirm on each card:

1. The tile looks **identical to a modifier tile in the rack**: blue
   (2x) or green (3x) gradient, white letter, **white point value** in
   the bottom-right corner that is now clearly readable.
2. **No "2x" / "3x" text** below the tile anymore — the gradient color
   is the only modifier indicator (the caption still says
   "double"/"triple").
3. The **"N in bag"** line below the tile is noticeably larger and
   easy to read.
4. Everything else (layout, selection, arrow nav, banner) is unchanged.

## Suggested commit

- `fix: upgrade cards match the shop tile (white points, drop 2x label, bigger bag count)`
