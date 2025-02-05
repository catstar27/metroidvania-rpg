extends NPC

var blocked_dialogue: String = "res://dialogue/test_room_npc_blocked.dtl"
var damaged_dialogue: String = "res://dialogue/test_room_npc_hit.dtl"
signal combat_gate_open

func _ready()->void:
	_setup()

func activate()->void:
	if NavMaster.is_pos_occupied(Vector2(32, -608)):
		combat_gate_open.emit()
		while position != Vector2(32, -544):
			if NavMaster.is_pos_occupied(Vector2(32, -544)):
				EventBus.broadcast("ENTER_DIALOGUE", [blocked_dialogue, true])
				move_order.emit(Vector2(-32, -544))
				while state_machine.current_state.state_id != "IDLE":
					await state_machine.state_changed
				ability_order.emit([get_abilities()[0], Vector2(32, -544)])
				while state_machine.current_state.state_id != "IDLE":
					await state_machine.state_changed
			move_order.emit(Vector2(32, -544))
			while state_machine.current_state.state_id != "IDLE":
				await state_machine.state_changed
		interact_order.emit(NavMaster.get_obj_at_pos(Vector2(32, -608)))
		while state_machine.current_state.state_id != "IDLE":
			await state_machine.state_changed
	await get_tree().create_timer(.1).timeout
	while position != Vector2(288, -736):
		move_order.emit(Vector2(288, -736))
		while state_machine.current_state.state_id != "IDLE":
			await state_machine.state_changed
		await get_tree().create_timer(.1).timeout

func _interacted(_interactor: Character)->void:
	if dialogue != null:
		EventBus.broadcast("ENTER_DIALOGUE", [dialogue, true])

func on_damaged()->void:
	EventBus.broadcast("ENTER_DIALOGUE", [damaged_dialogue, true])
	cur_hp = base_stats.max_hp
