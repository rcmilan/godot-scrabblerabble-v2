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
