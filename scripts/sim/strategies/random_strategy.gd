class_name RandomStrategy
extends "res://scripts/sim/strategy.gd"

# Random strategy: places tiles_per_turn random letters on random empty cells.

func pick_moves(core) -> Array:
	var moves: Array = []
	var tiles_to_place = core.tiles_per_turn
	var rack_ltrs = core.rack_letters()

	for _i in tiles_to_place:
		if rack_ltrs.is_empty():
			break

		# Pick a random letter from rack
		var letter_idx = core.rng.randi() % rack_ltrs.size()
		var letter = rack_ltrs[letter_idx]

		# Find a random empty cell on the board
		var max_attempts = 100
		for _attempt in max_attempts:
			var x = core.rng.randi() % core.BOARD_SIZE
			var y = core.rng.randi() % core.BOARD_SIZE
			var pos = Vector2i(x, y)
			if core.is_cell_empty(pos):
				moves.append({"letter": letter, "pos": pos})
				break

	return moves

func get_name() -> String:
	return "random"
