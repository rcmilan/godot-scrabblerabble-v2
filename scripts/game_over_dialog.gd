extends Panel

var _rounds: int = 0
var _score:  int = 0

func setup(rounds_survived: int, final_score: int) -> void:
	_rounds = rounds_survived
	_score  = final_score

func _ready() -> void:
	$InnerVBox/BodyArea/RoundLabel.text = "You survived %d rounds." % _rounds
	$InnerVBox/BodyArea/ScoreLabel.text = "Final score: %d"         % _score
	$InnerVBox/BodyArea/ButtonRow/RestartButton.pressed.connect(_on_restart)
	$InnerVBox/BodyArea/ButtonRow/QuitButton.pressed.connect(_on_quit)
	# The X in the title bar matches Win95: closes the window → quits the game.
	$InnerVBox/TitleBar/TitleContent/WinButtons/CloseBtn.pressed.connect(_on_quit)
	$InnerVBox/BodyArea/ButtonRow/RestartButton.grab_focus()

func _on_restart() -> void:
	print("[GameOverDialog] restart")
	RunState.reset()
	get_tree().reload_current_scene()

func _on_quit() -> void:
	print("[GameOverDialog] quit")
	get_tree().quit()
