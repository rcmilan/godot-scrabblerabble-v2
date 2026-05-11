extends Panel

var _rounds: int = 0
var _score:  int = 0

func setup(rounds_survived: int, final_score: int) -> void:
	_rounds = rounds_survived
	_score  = final_score

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	$VBox/BodyVBox/RoundLabel.text = "You survived %d rounds." % _rounds
	$VBox/BodyVBox/ScoreLabel.text = "Final score: %d"         % _score
	$VBox/BodyVBox/ButtonRow/RestartButton.pressed.connect(_on_restart)
	$VBox/BodyVBox/ButtonRow/QuitButton.pressed.connect(_on_quit)

func _on_restart() -> void:
	RunState.reset()
	get_tree().reload_current_scene()

func _on_quit() -> void:
	get_tree().quit()
