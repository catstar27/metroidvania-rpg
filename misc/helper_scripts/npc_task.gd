extends Resource
class_name NPCTask

enum scheduling_choice {ordered, timed}
enum type_choice {wait, guard, interact, wander, patrol}
@export var type: type_choice
@export_range(0,10) var wait_time: float = 0.0
@export var guard_location: Vector2
@export var interact_pos: Vector2
@export var wander_home: Vector2
@export var wander_max_tiles: Vector2i = Vector2i.ZERO
@export var patrol_points: Array[Vector2] = []
@export_group("Schedule")
@export_subgroup("Timed")
@export_range(0,23) var hour_start: int = 0
@export_range(0,23) var hour_end: int = 0
@export_range(0,59) var minute_start: int = 0
@export_range(0,59) var minute_end: int = 0
var user: Character
var executing: bool = false
var paused: bool = false
signal task_completed
signal pause
signal unpause

func _init() -> void:
	pause.connect(pause_execution)
	unpause.connect(unpause_execution)

func pause_execution()->void:
	paused = true

func unpause_execution()->void:
	paused = false

func check_time(time: Array[int])->bool:
	if !executing:
		if time[1] == hour_start:
			if time[0] >= minute_start:
				return true
		elif time[1] > hour_start && time[1] < hour_end:
			return true
		elif time[1] == hour_end:
			if time[0] <= minute_end:
				return true
	return false

func execute_task()->void:
	if user.in_combat || executing:
		return
	executing = true
	if type == type_choice.wait:
		await wait()
	elif type == type_choice.guard:
		await guard()
	elif type == type_choice.interact:
		await interact()
	elif type == type_choice.wander:
		await wander()
	elif type == type_choice.patrol:
		await patrol()
	task_completed.emit()
	executing = false

func wait()->void:
	while user.state_machine.current_state.state_id != "IDLE":
		await user.state_machine.state_changed
	await user.get_tree().create_timer(wait_time).timeout

func guard()->void:
	var attempts: int = 0
	while user.position != guard_location:
		if user.in_combat:
			return
		user.move_order.emit(guard_location)
		while paused:
			await unpause
		while user.state_machine.current_state.state_id != "IDLE":
			await user.state_machine.state_changed
		attempts += 1
		if attempts > 99:
			return

func interact()->void:
	var attempts: int = 0
	var can_interact: bool = (abs(user.position - interact_pos).x+abs(user.position - interact_pos).y)/NavMaster.tile_size <= 1
	while !can_interact:
		if user.in_combat:
			return
		user.move_order.emit(interact_pos)
		while paused:
			await unpause
		while user.state_machine.current_state.state_id != "IDLE":
			await user.state_machine.state_changed
		can_interact = (abs(user.position - interact_pos).x+abs(user.position - interact_pos).y)/NavMaster.tile_size <= 1
		attempts += 1
		if attempts > 99:
			return
	if can_interact:
		while paused:
			await unpause
		user.interact_order.emit(NavMaster.get_obj_at_pos(interact_pos))
		while user.state_machine.current_state.state_id != "IDLE":
			await user.state_machine.state_changed

func wander()->void:
	var max_distance: Vector2 = wander_max_tiles*NavMaster.tile_size
	var x_min: float = wander_home.x - max_distance.x
	var x_max: float = wander_home.x + max_distance.x
	var y_min: float = wander_home.y - max_distance.y
	var y_max: float = wander_home.y + max_distance.y
	var wander_pos: Vector2 = Vector2(randf_range(x_min,x_max),randf_range(y_min,y_max))
	while paused:
		await unpause
	user.move_order.emit(wander_pos)
	while user.state_machine.current_state.state_id != "IDLE":
		await user.state_machine.state_changed

func patrol()->void:
	for pos in patrol_points:
		if user.in_combat:
			return
		while user.position != pos:
			if user.in_combat:
				return
			user.move_order.emit(pos)
			while paused:
				await unpause
			while user.state_machine.current_state.state_id != "IDLE":
				await user.state_machine.state_changed
