class_name TestStrategies
extends RefCounted

# TS1 - Random strategy produces only valid moves.
func test_random_valid_moves() -> bool:
	var GameCore = load("res://scripts/sim/game_core.gd")
	var RandomStrategy = load("res://scripts/sim/strategies/random_strategy.gd")
	var core = GameCore.new(111)
	var strategy = RandomStrategy.new()

	for _i in 10:
		var moves = strategy.pick_moves(core)
		for move in moves:
			var letter = move["letter"]
			var pos = move["pos"]

			# Letter must be in rack
			if not core.rack.has(letter):
				push_error("Letter %s not in rack" % letter)
				return false

			# Position must be empty
			if not core.is_cell_empty(pos):
				push_error("Position %s is not empty" % pos)
				return false

		# End turn to refill and continue
		for move in moves:
			core.place_pending(move["letter"], move["pos"])
		core.end_turn([])

	return true

# TS2 - Random strategy returns at most tiles_per_turn moves.
func test_random_max_moves() -> bool:
	var GameCore = load("res://scripts/sim/game_core.gd")
	var RandomStrategy = load("res://scripts/sim/strategies/random_strategy.gd")
	var core = GameCore.new(222)
	var strategy = RandomStrategy.new()

	for _i in 20:
		var moves = strategy.pick_moves(core)
		if moves.size() > core.tiles_per_turn:
			push_error("Strategy returned %d moves, max is %d" % [
				moves.size(), core.tiles_per_turn])
			return false

		# Place and end turn
		for move in moves:
			core.place_pending(move["letter"], move["pos"])
		core.end_turn([])

		if core.is_game_over:
			break

	return true
