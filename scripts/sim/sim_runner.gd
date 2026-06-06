extends SceneTree

# CLI entry point for the simulator.
# Usage: godot --headless --path . --script res://scripts/sim/sim_runner.gd -- --runs 100 --strategies random,greedy --seed 42

const Simulator = preload("res://scripts/sim/simulator.gd")
const ResultsWriter = preload("res://scripts/sim/results_writer.gd")
const GameCore = preload("res://scripts/sim/game_core.gd")
const RandomStrategy = preload("res://scripts/sim/strategies/random_strategy.gd")
const GreedyStrategy = preload("res://scripts/sim/strategies/greedy_strategy.gd")
const WordSearchStrategy = preload("res://scripts/sim/strategies/word_search_strategy.gd")
const DiagonalClusterStrategy = preload("res://scripts/sim/strategies/diagonal_cluster_strategy.gd")
const HybridWordDiagonalStrategy = preload("res://scripts/sim/strategies/hybrid_word_diagonal_strategy.gd")
const CornerSpiralStrategy = preload("res://scripts/sim/strategies/corner_spiral_strategy.gd")

func _initialize() -> void:
	var args = _parse_args()

	var runs_per_strategy = int(args.get("runs", "100"))
	var strategies_str = args.get("strategies", "random")
	var base_seed = int(args.get("seed", "42"))
	var output_dir = args.get("out", "user://sim/")
	var build_str = args.get("build", "")

	var strategies = _build_strategies(strategies_str)
	if strategies.is_empty():
		print("ERROR: No strategies specified")
		quit(1)

	var modifier_build = _parse_build(build_str)

	print("Running simulation...")
	print("  Strategies: %s" % strategies_str)
	print("  Runs per strategy: %d" % runs_per_strategy)
	print("  Base seed: %d" % base_seed)
	if not modifier_build.is_empty():
		print("  Build: %s" % _build_to_string(modifier_build))

	var sim = Simulator.new()
	var results = sim.run_batch(strategies, runs_per_strategy, base_seed, modifier_build)

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
	# In Godot 4.6, use OS.get_cmdline_user_args() for arguments after --
	var raw_args = OS.get_cmdline_user_args()

	var i = 0
	while i < raw_args.size():
		var arg = raw_args[i]

		if arg.begins_with("--"):
			var key_value = arg.trim_prefix("--").split("=")
			var key = key_value[0]
			var value = ""

			if key_value.size() > 1:
				# --key=value format
				value = key_value[1]
			elif i + 1 < raw_args.size() and not raw_args[i + 1].begins_with("--"):
				# --key value format
				value = raw_args[i + 1]
				i += 1

			args[key] = value

		i += 1

	return args

func _build_strategies(strategies_str: String) -> Array:
	var strategy_names = strategies_str.split(",")
	var strategies = []

	for name in strategy_names:
		name = name.strip_edges().to_lower()
		if name == "random":
			strategies.append(RandomStrategy.new())
		elif name == "greedy":
			strategies.append(GreedyStrategy.new())
		elif name == "word_search":
			strategies.append(WordSearchStrategy.new())
		elif name == "diagonal_cluster":
			strategies.append(DiagonalClusterStrategy.new())
		elif name == "hybrid_word_diagonal":
			strategies.append(HybridWordDiagonalStrategy.new())
		elif name == "corner_spiral":
			strategies.append(CornerSpiralStrategy.new())
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

func _parse_build(build_str: String) -> Dictionary:
	var result: Dictionary = {}
	if build_str.is_empty():
		return result

	# Parse comma-separated key:count pairs
	var pairs = build_str.split(",")
	for pair in pairs:
		pair = pair.strip_edges()
		var parts = pair.split(":")
		if parts.size() != 2:
			print("[Sim] invalid build format: %s" % pair)
			continue

		var cli_key = parts[0].strip_edges()
		var count_str = parts[1].strip_edges()
		var count = int(count_str)

		# Map CLI key to GameCore constant
		var mod_const = ""
		match cli_key:
			"mod_2x": mod_const = GameCore.MOD_2X
			"mod_3x": print("[Sim] unknown build mod: %s" % cli_key); continue
			_: print("[Sim] unknown build mod: %s" % cli_key); continue

		if mod_const != "":
			result[mod_const] = count

	return result

func _build_to_string(build: Dictionary) -> String:
	var parts: Array = []
	for mod in build.keys():
		parts.append("%s:%d" % [mod, build[mod]])
	return "{%s}" % ", ".join(parts)
