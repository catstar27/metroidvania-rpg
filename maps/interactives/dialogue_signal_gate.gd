extends Interactive
class_name DialogueSignalGate

@export var locked_texture: Texture
@export var signals_needed: Array[String] = []
@export var dialogic_var: String
var signal_index: int = 0
enum state {locked, unlocked, open}
var cur_state: state = state.locked

func _ready() -> void:
	_setup()
	sprite.texture = locked_texture
	Dialogic.signal_event.connect(advance_unlock)
	Dialogic.VAR.set(dialogic_var, signal_index)

func _interacted(_character: Character):
	if cur_state == state.locked:
		audio.play()
		if dialogue_timeline != null:
			Dialogic.start(dialogue_timeline)
		interacted.emit()
	elif cur_state == state.unlocked:
		sprite.texture = texture
		audio.play()
		collision.disabled = true
		GlobalRes.map.update_occupied_tiles(GlobalRes.map.local_to_map(position))
		interacted.emit()

func advance_unlock(signal_event: String)->void:
	if !signal_index>=signals_needed.size():
		if signal_event==signals_needed[signal_index]:
			signal_index += 1
			Dialogic.VAR.set(dialogic_var, signal_index)
			if signal_index>=signals_needed.size():
				cur_state = state.unlocked
		else:
			signal_index = 0
			Dialogic.VAR.set(dialogic_var, signal_index)