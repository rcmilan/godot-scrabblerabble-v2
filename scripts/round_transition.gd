extends CanvasLayer

signal finished

const SLIDE_TIME: float = 0.35
const HOLD_TIME:  float = 1.0

@onready var round_label:     Label = $Overlay/RoundLabel
@onready var completed_label: Label = $Overlay/CompletedLabel

func play(round_num: int) -> void:
	round_label.text = "ROUND %d" % round_num
	var vp_w := get_viewport().get_visible_rect().size.x
	# Both labels are anchored full-width; position.x shifts the whole strip,
	# carrying its centered text off-screen.
	round_label.position.x     = vp_w
	completed_label.position.x = vp_w
	var tw := create_tween()
	tw.tween_property(round_label,     "position:x", 0.0,    SLIDE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(completed_label, "position:x", 0.0,    SLIDE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(HOLD_TIME)
	tw.tween_property(round_label,     "position:x", -vp_w, SLIDE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(completed_label, "position:x", -vp_w, SLIDE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.finished.connect(_on_done)

func _on_done() -> void:
	finished.emit()
	queue_free()
