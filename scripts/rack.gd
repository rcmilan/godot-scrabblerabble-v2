# res://scripts/rack.gd
class_name Rack
extends HBoxContainer

const TILE_SCENE: PackedScene = preload("res://scenes/tile.tscn")
const RACK_SIZE: int = 7

var tiles_in_hand: Array[Tile] = []

func _ready() -> void:
	refill()

func refill() -> void:
	# Refills until rack has RACK_SIZE tiles, drawing weighted-random letters.
	while tiles_in_hand.size() < RACK_SIZE:
		var letter := _draw_random_letter()
		var tile := TILE_SCENE.instantiate() as Tile
		tile.letter = letter
		add_child(tile)
		tiles_in_hand.append(tile)
	_apply_modifiers()

func _apply_modifiers() -> void:
	for tile in tiles_in_hand:
		if RunState.letter_modifiers.has(tile.letter):
			tile.set_modifier(RunState.letter_modifiers[tile.letter])
	for mod in RunState.modifier_build.keys():
		_ensure_modifier_count_in_rack(mod, RunState.modifier_build[mod])

func _draw_random_letter() -> String:
	# Build a weighted bag from the standard distribution.
	var bag: Array[String] = []
	for letter in GameData.LETTER_DISTRIBUTION.keys():
		for i in GameData.LETTER_DISTRIBUTION[letter]:
			bag.append(letter)
	return bag[randi() % bag.size()]

func _draw_random_letter_excluding(excluded: String) -> String:
	var bag: Array[String] = []
	for letter in GameData.LETTER_DISTRIBUTION.keys():
		if letter == excluded:
			continue
		for i in GameData.LETTER_DISTRIBUTION[letter]:
			bag.append(letter)
	return bag[randi() % bag.size()]

func discard_replace(old_tile: Tile) -> Dictionary:
	var idx := tiles_in_hand.find(old_tile)
	if idx == -1:
		return {}
	var old_letter := old_tile.letter
	tiles_in_hand.remove_at(idx)
	if old_tile.get_parent() == self:
		remove_child(old_tile)
	var new_tile := TILE_SCENE.instantiate() as Tile
	new_tile.letter = _draw_random_letter_excluding(old_letter)
	add_child(new_tile)
	move_child(new_tile, idx)
	tiles_in_hand.insert(idx, new_tile)
	_apply_modifiers()
	return {"old_tile": old_tile, "new_tile": new_tile, "slot": idx}

func _ensure_modifier_count_in_rack(mod: String, required_count: int) -> void:
	# 1. Count tiles already carrying this modifier.
	var have := 0
	for t in tiles_in_hand:
		if t.modifier == mod:
			have += 1
	# 2. Promote unmodified tiles until we hit required_count.
	#    Binary rule: a tile with ANY modifier is ineligible — never stack.
	while have < required_count:
		var target_idx := -1
		var target_pts := 9999
		for i in tiles_in_hand.size():
			var t: Tile = tiles_in_hand[i]
			if t.modifier != GameData.MOD_NONE:
				continue
			var pts: int = GameData.LETTER_POINTS.get(t.letter, 0)
			if pts < target_pts:
				target_pts = pts
				target_idx = i
		if target_idx < 0:
			return  # no unmodified tiles left; top out silently
		tiles_in_hand[target_idx].set_modifier(mod)
		have += 1

func remove_tile(tile: Tile) -> void:
	tiles_in_hand.erase(tile)
	if tile.get_parent() == self:
		remove_child(tile)

func find_tile_with_letter(letter: String) -> Tile:
	var up := letter.to_upper()
	for t in tiles_in_hand:
		if t.letter == up:
			return t
	return null

# --- Drop target: allow returning a tile from the board to the rack ---
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Tile and (data as Tile).location == "board"

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("on_tile_returned_to_rack"):
		main.on_tile_returned_to_rack(data as Tile)
