extends SceneTree

var test_results: Array = []

func _initialize() -> void:
	print("--- Running Simulation Tests ---")

	# Load and run test files.
	_run_test_file("res://scripts/sim/tests/test_game_core.gd")

	# Print summary.
	print("")
	print("=== Test Summary ===")
	var total := test_results.size()
	var failures := test_results.filter(func(r): return r["pass"] == false).size()
	for result in test_results:
		if result["pass"]:
			print("PASS %s" % result["name"])
		else:
			print("FAIL %s: %s" % [result["name"], result["reason"]])

	print("")
	print("%d tests, %d failures" % [total, failures])

	if failures > 0:
		quit(1)
	else:
		quit()

func _run_test_file(path: String) -> void:
	var script = load(path)
	if script == null:
		print("ERROR: Could not load test file: %s" % path)
		return

	var test_obj = script.new()

	# Find all test_* methods.
	for method_info in test_obj.get_method_list():
		var test_name = method_info.get("name", "")
		if test_name.begins_with("test_"):
			var result = {"name": test_name, "pass": true, "reason": ""}

			if test_obj.call(test_name) == false:
				result["pass"] = false
				result["reason"] = "assertion failed"

			test_results.append(result)
