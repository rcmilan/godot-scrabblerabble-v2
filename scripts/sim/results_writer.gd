class_name ResultsWriter
extends RefCounted

# Writes simulation results to CSV and JSONL files in user://sim/

func write_batch(results: Array) -> Dictionary:
	var timestamp = _get_timestamp()
	var output_dir = "user://sim/"

	# Create directory if it doesn't exist
	_ensure_dir(output_dir)

	var csv_path = output_dir + "sim_results_%s.csv" % timestamp
	var jsonl_path = output_dir + "sim_results_%s.jsonl" % timestamp

	_write_csv(csv_path, results)
	_write_jsonl(jsonl_path, results)

	return {
		"csv": csv_path,
		"jsonl": jsonl_path,
		"timestamp": timestamp
	}

func _get_timestamp() -> String:
	var dt = Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second
	]

func _ensure_dir(path: String) -> void:
	var dir = DirAccess.open(path.get_base_dir())
	if dir == null:
		DirAccess.make_absolute_path(path, "user://")

func _write_csv(path: String, results: Array) -> void:
	var csv_content = "strategy,seed,rounds_completed,final_round,final_round_score,final_target,total_turns_played,total_score_across_rounds,avg_score_per_turn,wasted_turns\n"

	for result in results:
		var wasted_turns = result.total_turns_played - (result.total_score_across_rounds + 1)
		csv_content += "%s,%d,%d,%d,%d,%d,%d,%d,%.2f,%d\n" % [
			result.strategy,
			result.seed,
			result.rounds_completed,
			result.final_round,
			result.final_round_score,
			result.final_target,
			result.total_turns_played,
			result.total_score_across_rounds,
			result.avg_score_per_turn,
			wasted_turns
		]

	var file = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(csv_content)

func _write_jsonl(path: String, results: Array) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return

	for result in results:
		var json_str = JSON.stringify(result)
		file.store_line(json_str)
