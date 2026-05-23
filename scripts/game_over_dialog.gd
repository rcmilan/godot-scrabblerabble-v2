extends Panel

var _round:  int = 0
var _score:  int = 0
var _target: int = 0

func setup(round_num: int, round_score: int, target: int) -> void:
	_round  = round_num
	_score  = round_score
	_target = target

func _ready() -> void:
	$InnerVBox/BodyArea/RoundLabel.text = "Round %d"          % _round
	$InnerVBox/BodyArea/ScoreLabel.text = "Score: %d / %d"    % [_score, _target]
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
