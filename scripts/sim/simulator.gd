class_name Simulator
extends RefCounted

const GameCore = preload("res://scripts/sim/game_core.gd")

# Runs N simulated games with different strategies and collects results.

func run_batch(strategies: Array, runs_per_strategy: int, base_seed: int, modifier_build: Dictionary = {}, shop_strategy: String = "default") -> Array:
	var all_results: Array = []

	for strategy_idx in range(strategies.size()):
		var strategy = strategies[strategy_idx]
		for run_idx in range(runs_per_strategy):
			var seed = base_seed + strategy_idx * 10000 + run_idx
			var result = _run_game(strategy, seed, modifier_build, shop_strategy)
			all_results.append(result)

	return all_results

func _run_game(strategy, seed: int, modifier_build: Dictionary = {}, shop_strategy: String = "default") -> Dictionary:
	var core = GameCore.new(seed, modifier_build, shop_strategy)
	var turn_log: Array = []
	var max_turns = 10000

	while not core.is_game_over and turn_log.size() < max_turns:
		var moves = strategy.pick_moves(core)

		# Caller removes tile from rack; place_pending_tile writes board only.
		var placed_positions: Array = []
		for move in moves:
			var letter = move["letter"]
			var pos = move["pos"]
			var tile_dict: Dictionary = {}
			for i in core.rack.size():
				if core.rack[i].letter == letter:
					tile_dict = core.rack[i]
					core.rack.remove_at(i)
					break
			if tile_dict.is_empty():
				continue
			if core.place_pending_tile(tile_dict, pos):
				placed_positions.append(pos)
			else:
				core.rack.append(tile_dict)

		# End turn and get score
		var score = core.end_turn(placed_positions)
		turn_log.append({
			"round": core.current_round,
			"turn_index": turn_log.size(),
			"placed_count": placed_positions.size(),
			"score": score
		})

	var total_score = 0
	for turn in turn_log:
		total_score += turn["score"]

	var avg_score = float(total_score) / float(turn_log.size()) if turn_log.size() > 0 else 0

	return {
		"strategy": strategy.get_name(),
		"seed": seed,
		"rounds_completed": core.current_round - 1,
		"final_round": core.current_round,
		"final_round_score": core.round_score,
		"final_target": core.target_score,
		"total_turns_played": turn_log.size(),
		"total_score_across_rounds": total_score,
		"avg_score_per_turn": avg_score,
		"turn_log": turn_log
	}
