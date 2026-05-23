extends Panel

var _rounds: int = 0
var _score:  int = 0

func setup(rounds_survived: int, final_score: int) -> void:
	_rounds = rounds_survived
	_score  = final_score

func _ready() -> void:
	$VBox/RoundLabel.text = "You survived %d rounds." % _rounds
	$VBox/ScoreLabel.text = "Final score: %d"         % _score
	$VBox/ButtonRow/RestartButton.pressed.connect(_on_restart)
	$VBox/ButtonRow/QuitButton.pressed.connect(_on_quit)
	$VBox/ButtonRow/RestartButton.grab_focus()

func _on_restart() -> void:
	print("[GameOverDialog] restart")
	RunState.reset()
	get_tree().reload_current_scene()

func _on_quit() -> void:
	print("[GameOverDialog] quit")
	get_tree().quit()
