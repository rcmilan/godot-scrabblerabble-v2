extends SceneTree

# Quick smoke test: run 3 games and verify results structure.

func _initialize() -> void:
	var Simulator = load("res://scripts/sim/simulator.gd")
	var RandomStrategy = load("res://scripts/sim/strategies/random_strategy.gd")

	var sim = Simulator.new()
	var strategy = RandomStrategy.new()
	var strategies = [strategy]

	var results = sim.run_batch(strategies, 3, 99999)

	if results.size() != 3:
		print("SMOKE FAIL: expected 3 results, got %d" % results.size())
		quit(1)

	var expected_keys = [
		"strategy", "seed", "rounds_completed", "final_round", "final_round_score",
		"final_target", "total_turns_played", "total_score_across_rounds", "avg_score_per_turn"
	]

	for i in range(results.size()):
		var result = results[i]
		for key in expected_keys:
			if not result.has(key):
				print("SMOKE FAIL: result %d missing key '%s'" % [i, key])
				quit(1)

	print("SMOKE OK")
	quit(0)
