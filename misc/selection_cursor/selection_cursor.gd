extends Node2D
class_name SelectionCursor
## Cursor that allows the player to view the map and select characters
##
## Can have one character selected at a time, and can make that character
## move, interact, activate abilities, etc.

@export var move_arrow_tex: Texture2D ## Texture of movement arrows
@onready var sprite: Sprite2D = %Sprite ## Sprite of the cursor
@onready var selection_area: Area2D = %SelectionArea ## Area which detects objects to select/interact
@onready var camera: Camera2D = %Camera ## Camera node, which is part of this
var selection_marker_scene: PackedScene = preload("res://misc/selection_cursor/selection_marker.tscn") ## Scene for selection markers
var selected: Character = null ## Character the cursor has selected
var hovering: Node2D = null ## Object the cursor is hovering over
var moving: bool = false ## Whether the cursor is moving
var move_dir: Vector2 = Vector2i.ZERO ## Direction to move in
var marker: Node2D = null ## Current selection marker
var move_arrows: Array[Sprite2D] = [] ## Array of sprites making up the movement arrows
var deactivate_requests: int = 0 ## Number of sources attempting to deactivate the cursor; inactive if > 0
var block_deselect: bool = false ## Blocks the cursor from deselecting
signal move_stopped ## Emitted when the cursor stops moving

func _ready() -> void:
	update_color()
	EventBus.subscribe("DEACTIVATE_SELECTION", self, "deactivate")
	EventBus.subscribe("ACTIVATE_SELECTION", self, "activate")
	EventBus.subscribe("COMBAT_STARTED", self, "deselect")
	EventBus.subscribe("ABILITY_BUTTON_PRESSED", self, "select_ability")
	EventBus.subscribe("GAMEPLAY_SETTINGS_CHANGED", self, "update_color")

## Updates the color of the cursor and its markers
func update_color()->void:
	sprite.modulate = Settings.gameplay.selection_tint
	for move_arrow in move_arrows:
		move_arrow.modulate = sprite.modulate

## Takes a float and converts it into -1, 0, or 1
func _scale_float(num: float)->int:
	if num > 0:
		return 1
	if num < 0:
		return -1
	return 0

func _unhandled_input(event: InputEvent) -> void:
	if deactivate_requests > 0:
		return
	if event.is_action("left") || event.is_action("right"):
		move_dir.x = _scale_float(Input.get_axis("left", "right"))
	if event.is_action("up") || event.is_action("down"):
		move_dir.y = _scale_float(Input.get_axis("up", "down"))
	if event.is_action_pressed("interact"):
		act_on_pos(position)
	if event.is_action_pressed("clear"):
		if selected != null:
			if selected.selected_ability == null:
				deselect()
	if event.is_action_pressed("info"):
		update_move_arrows(selected)
	if event.is_action_released("info"):
		clear_move_arrows()

func _physics_process(_delta: float) -> void:
	if !moving && move_dir != Vector2.ZERO:
		move(move_dir)

#region Movement Arrow
## Creates a new movement arrow
func get_move_arrow(pos: Vector2)->Sprite2D:
	var new_arrow: Sprite2D = Sprite2D.new()
	new_arrow.top_level = true
	new_arrow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	new_arrow.z_index = 5
	new_arrow.texture = move_arrow_tex
	new_arrow.hframes = 3
	new_arrow.position = pos
	new_arrow.scale = Vector2.ONE*4
	new_arrow.material = material
	new_arrow.modulate = sprite.modulate
	move_arrows.append(new_arrow)
	return new_arrow

## Makes a path of arrow pieces to display the projected path of movement
func update_move_arrows(character: Character)->void:
	clear_move_arrows()
	if character == null:
		return
	if Input.is_action_pressed("info"):
		var path: Array[Vector2] = NavMaster.request_nav_path(character.global_position, global_position)
		if path.size() == 1 || character.global_position == global_position:
			return
		for index in range(1, path.size()):
			if character != selected:
				break
			var new_arrow: Sprite2D = get_move_arrow(path[index])
			new_arrow.look_at(path[index-1])
			if index > 1 && move_arrows[index-2].rotation != new_arrow.rotation:
				move_arrows[index-2].frame = 1
				var dir_enter: Vector2 = -(path[index-1]-path[index-2]).normalized()
				var dir_exit: Vector2 = -(path[index-1]-path[index]).normalized()
				move_arrows[index-2].rotation = 0
				if (dir_exit == Vector2.DOWN || dir_enter == Vector2.DOWN) && (dir_exit == Vector2.LEFT || dir_enter == Vector2.LEFT):
					move_arrows[index-2].rotation = PI
				elif dir_exit == Vector2.DOWN || dir_enter == Vector2.DOWN:
					move_arrows[index-2].rotation = PI/2
				elif dir_exit == Vector2.LEFT || dir_enter == Vector2.LEFT:
					move_arrows[index-2].rotation = -PI/2
			if index == path.size()-1:
				new_arrow.rotation -= PI
				new_arrow.frame = 2
			add_child(new_arrow)

## Deletes all movement arrow pieces
func clear_move_arrows()->void:
	while move_arrows != []:
		move_arrows.pop_back().queue_free()
#endregion

#region Actions
## Activates the cursor, allowing it to move or act
func activate()->void:
	move_dir = Vector2.ZERO
	if deactivate_requests == 0:
		printerr("Attempted to activate selection cursor that was active")
		return
	deactivate_requests -= 1

## Deactivates the cursor, preventing it from doing anything
func deactivate()->void:
	move_dir = Vector2.ZERO
	deactivate_requests += 1

## Moves the cursor in the given direction
func move(dir: Vector2)->void:
	moving = true
	var new_pos: Vector2 = NavMaster.tile_size*dir+position
	if !NavMaster.is_in_bounds(new_pos):
		pass
	else:
		var tween: Tween = create_tween()
		var time: float = .2
		if Input.is_action_pressed("shift"):
			time = .1
		await tween.tween_property(self, "position", new_pos, time).set_ease(Tween.EASE_IN_OUT).finished
		if NavMaster.is_in_bounds(position):
			update_move_arrows(selected)
	moving = false
	move_stopped.emit()

## Performs an action at given position based on current state
func act_on_pos(pos: Vector2i)->void:
	if hovering is Player && selected == null:
		select(hovering)
	elif selected == null:
		return
	elif selected.selected_ability != null:
		selected.activate_ability(selected.selected_ability, pos)
	elif hovering == null || hovering is GameMap:
		selected.move(pos)
	elif hovering is Interactive || (hovering is Character && hovering != selected):
		await selected_interact(pos)

## Makes the selected character interact with the target
func selected_interact(pos: Vector2)->void:
	var cur_hover = hovering
	selected.move(pos)
	block_deselect = true
	while selected.state_machine.current_state.state_id != "IDLE":
		await selected.state_machine.state_changed
	selected.interact(cur_hover)
	block_deselect = false
#endregion

#region Selection
## Creates a marker to show a character is selected
func _create_marker()->void:
	marker = selection_marker_scene.instantiate()
	marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	marker.modulate = Settings.gameplay.selection_tint
	selected.add_child(marker)

## Deletes the current marker
func _delete_marker()->void:
	if marker != null:
		marker.queue_free()

## Selects the given character
func select(character: Character)->void:
	if character.in_combat && !character.taking_turn:
		return
	if character != null && selected == character:
		return
	if block_deselect:
		return
	if selected != null:
		deselect()
	selected = character
	if selected != null:
		selected.call_deferred("select")
		selected.ended_turn.connect(deselect)
		selected.pos_changed.connect(update_move_arrows)
		_create_marker()
	EventBus.broadcast("SELECTION_CHANGED",selected)

## Deselects the current character
func deselect(_node: Character = null)->void:
	if block_deselect:
		return
	clear_move_arrows()
	_delete_marker()
	if selected == null:
		return
	var prev_select: Character = selected
	selected = null
	prev_select.call_deferred("deselect")
	prev_select.ended_turn.disconnect(deselect)
	prev_select.pos_changed.disconnect(update_move_arrows)
	EventBus.broadcast("SELECTION_CHANGED",selected)

func _selection_area_entered(body: Node2D) -> void:
	if !body is GameMap:
		hovering = body

func _selection_area_exited(body: Node2D) -> void:
	if hovering == body:
		hovering = null
#endregion
