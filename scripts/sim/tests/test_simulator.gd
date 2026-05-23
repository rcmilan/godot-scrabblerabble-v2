class_name TestSimulator
extends RefCounted

# TSM1 - Same seed produces identical results.
func test_same_seed_identical_results() -> bool:
	var Simulator = load("res://scripts/sim/simulator.gd")
	var RandomStrategy = load("res://scripts/sim/strategies/random_strategy.gd")
	var sim = Simulator.new()
	var strategy = RandomStrategy.new()
	var strategies = [strategy]

	var results1 = sim.run_batch(strategies, 5, 1000)
	var results2 = sim.run_batch(strategies, 5, 1000)

	if results1.size() != results2.size():
		push_error("Result count mismatch")
		return false

	for i in range(results1.size()):
		var r1 = results1[i]
		var r2 = results2[i]
		if r1.seed != r2.seed or r1.total_turns_played != r2.total_turns_played:
			push_error("Run %d differs: turns %d vs %d" % [
				i, r1.total_turns_played, r2.total_turns_played])
			return false

	return true

# TSM3 - Games terminate (don't hang).
func test_games_terminate() -> bool:
	var Simulator = load("res://scripts/sim/simulator.gd")
	var RandomStrategy = load("res://scripts/sim/strategies/random_strategy.gd")
	var sim = Simulator.new()
	var strategy = RandomStrategy.new()
	var strategies = [strategy]

	var results = sim.run_batch(strategies, 5, 9999)

	for result in results:
		if result.total_turns_played <= 0:
			push_error("Game didn't play any turns")
			return false
		if result.total_turns_played > 10000:
			push_error("Game exceeded max turns: %d" % result.total_turns_played)
			return false

	return true

# TSM4 - Results have turn_log structure.
func test_results_have_turn_log() -> bool:
	var Simulator = load("res://scripts/sim/simulator.gd")
	var RandomStrategy = load("res://scripts/sim/strategies/random_strategy.gd")

	var sim = Simulator.new()
	var results = sim.run_batch([RandomStrategy.new()], 3, 8888)

	if results.size() != 3:
		push_error("Expected 3 results, got %d" % results.size())
		return false

	for result in results:
		if not result.has("turn_log"):
			push_error("Result missing turn_log")
			return false
		if typeof(result.turn_log) != TYPE_ARRAY:
			push_error("turn_log is not an array")
			return false

	return true

# TSM5 - Results are JSON-serializable.
func test_results_json_serializable() -> bool:
	var Simulator = load("res://scripts/sim/simulator.gd")
	var RandomStrategy = load("res://scripts/sim/strategies/random_strategy.gd")

	var sim = Simulator.new()
	var results = sim.run_batch([RandomStrategy.new()], 2, 9999)

	for result in results:
		var json_str = JSON.stringify(result)
		if json_str.is_empty():
			push_error("Failed to serialize result to JSON")
			return false

	return true

# TSM6 - Determinism under modifier: same seed + strategy produces identical results.
func test_determinism_under_modifier() -> bool:
	var Simulator = load("res://scripts/sim/simulator.gd")
	var GreedyStrategy = load("res://scripts/sim/strategies/greedy_strategy.gd")
	var sim = Simulator.new()

	var results1 = sim.run_batch([GreedyStrategy.new()], 3, 7777)
	var results2 = sim.run_batch([GreedyStrategy.new()], 3, 7777)

	if results1.size() != results2.size():
		push_error("TSM6: result count mismatch")
		return false

	for i in range(results1.size()):
		var r1 = results1[i]
		var r2 = results2[i]
		if r1.total_turns_played != r2.total_turns_played:
			push_error("TSM6 run %d: turns differ %d vs %d" % [i, r1.total_turns_played, r2.total_turns_played])
			return false
		if r1.total_score_across_rounds != r2.total_score_across_rounds:
			push_error("TSM6 run %d: total score differs %d vs %d" % [i, r1.total_score_across_rounds, r2.total_score_across_rounds])
			return false
		for t in range(r1.turn_log.size()):
			var t1 = r1.turn_log[t]
			var t2 = r2.turn_log[t]
			if t1.score != t2.score or t1.placed_count != t2.placed_count:
				push_error("TSM6 run %d turn %d: score/placed_count differs" % [i, t])
				return false

	return true
