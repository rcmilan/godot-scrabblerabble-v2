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

func _draw_random_letter() -> String:
	# Build a weighted bag from the standard distribution.
	var bag: Array[String] = []
	for letter in GameData.LETTER_DISTRIBUTION.keys():
		for i in GameData.LETTER_DISTRIBUTION[letter]:
			bag.append(letter)
	return bag[randi() % bag.size()]

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
