extends Control
## Stage 0 placeholder screen. Later stages replace this with the scenario flow.

const TITLE := "DroneAcharya — synthetic training only"

@onready var _title: Label = $Title


func _ready() -> void:
	_title.text = TITLE
