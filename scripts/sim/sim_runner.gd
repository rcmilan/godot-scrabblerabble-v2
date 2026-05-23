extends SceneTree

# CLI entry point for the simulator.
# Usage: godot --headless --path . --script res://scripts/sim/sim_runner.gd -- --runs 100 --strategies random,greedy --seed 42

const Simulator = preload("res://scripts/sim/simulator.gd")
const ResultsWriter = preload("res://scripts/sim/results_writer.gd")
const RandomStrategy = preload("res://scripts/sim/strategies/random_strategy.gd")

func _initialize() -> void:
	var args = _parse_args()

	var runs_per_strategy = int(args.get("runs", "100"))
	var strategies_str = args.get("strategies", "random")
	var base_seed = int(args.get("seed", "42"))
	var output_dir = args.get("out", "user://sim/")

	var strategies = _build_strategies(strategies_str)
	if strategies.is_empty():
		print("ERROR: No strategies specified")
		quit(1)

	print("Running simulation...")
	print("  Strategies: %s" % strategies_str)
	print("  Runs per strategy: %d" % runs_per_strategy)
	print("  Base seed: %d" % base_seed)

	var sim = Simulator.new()
	var results = sim.run_batch(strategies, runs_per_strategy, base_seed)

	var writer = ResultsWriter.new()
	var file_info = writer.write_batch(results)

	_print_summary(results, strategies)

	print("")
	print("Results written to:")
	print("  CSV: %s" % file_info.csv)
	print("  JSONL: %s" % file_info.jsonl)

	quit(0)

func _parse_args() -> Dictionary:
	var args = {}
	var raw_args = OS.get_cmdline_args()
	var in_script_args = false

	for arg in raw_args:
		if arg == "--":
			in_script_args = true
			continue

		if not in_script_args:
			continue

		if arg.begins_with("--"):
			var key_value = arg.trim_prefix("--").split("=")
			var key = key_value[0]
			var value = key_value[1] if key_value.size() > 1 else ""
			args[key] = value

	return args

func _build_strategies(strategies_str: String) -> Array:
	var strategy_names = strategies_str.split(",")
	var strategies = []

	for name in strategy_names:
		name = name.strip_edges().to_lower()
		if name == "random":
			strategies.append(RandomStrategy.new())
		else:
			print("WARNING: Unknown strategy '%s'" % name)

	return strategies

func _print_summary(results: Array, strategies: Array) -> void:
	print("")
	print("=== Summary ===")
	print("")

	var by_strategy = {}
	for result in results:
		var strat = result.strategy
		if not by_strategy.has(strat):
			by_strategy[strat] = []
		by_strategy[strat].append(result)

	print("%-15s %10s %10s %10s %10s" % ["Strategy", "Mean Rounds", "Median", "P90", "Mean Score"])
	print("------------------------------------------------------------")

	for strat_name in by_strategy.keys():
		var runs = by_strategy[strat_name]
		var rounds = []
		var scores = []

		for run in runs:
			rounds.append(run.rounds_completed)
			scores.append(run.final_round_score)

		rounds.sort()
		scores.sort()

		var mean_rounds = 0.0
		for r in rounds:
			mean_rounds += float(r)
		mean_rounds /= float(rounds.size())

		var median_rounds = rounds[rounds.size() / 2]
		var p90_rounds = rounds[int(rounds.size() * 0.9)]

		var mean_score = 0.0
		for s in scores:
			mean_score += float(s)
		mean_score /= float(scores.size())

		print("%-15s %10.1f %10d %10d %10.1f" % [
			strat_name, mean_rounds, median_rounds, p90_rounds, mean_score
		])
