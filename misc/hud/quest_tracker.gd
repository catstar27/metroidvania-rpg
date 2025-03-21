extends Control
class_name QuestTracker
## Tracks the currently tracked quest, displaying information about the current stage

@onready var quest_name: Label = %Name ## Name of the current quest
@onready var quest_container: VBoxContainer = %QuestContainer ## Container holding the display info
@onready var objective_container: VBoxContainer = %ObjectiveContainer ## Container holding the objective info
var objective_labels: Dictionary[QuestObjective, RichTextLabel] ## Array of the labels containing objective info
var tracked_quest: QuestInfo = null ## Currently tracked quest
var in_combat: bool = false ## Whether the game is in combat

func _ready() -> void:
	EventBus.subscribe("QUEST_TRACK", self, "change_quest")
	EventBus.subscribe("QUEST_TRACK_STOP", self, "stop_tracking")
	EventBus.subscribe("COMBAT_STARTED", self, "start_combat")
	EventBus.subscribe("COMBAT_ENDED", self, "end_combat")

## Changes the currently tracked quest
func change_quest(quest: QuestInfo)->void:
	tracked_quest = quest
	quest.quest_complete.connect(complete_quest)
	quest_name.modulate = Color.TRANSPARENT
	quest_name.text = tracked_quest.quest_name
	await get_tree().process_frame
	var copy_label: Label = Label.new()
	copy_label.label_settings = quest_name.label_settings
	copy_label.use_parent_material = true
	copy_label.text = quest_name.text
	copy_label.size = quest_name.size
	add_child(copy_label)
	copy_label.global_position = quest_name.global_position
	copy_label.global_position.y += quest_name.size.y
	await create_tween().tween_property(copy_label, "global_position", quest_name.global_position, .5).finished
	quest_name.modulate = Color.WHITE
	build_labels()
	copy_label.queue_free()
	quest.stage_started.connect(build_labels)
	if !in_combat:
		show()

## Updates the label corresponding to the quest objective given
func update_objective(objective: QuestObjective, play_anim: bool = false)->void:
	if play_anim:
		objective_labels[objective].modulate = Color.TRANSPARENT
	objective_labels[objective].text = ""
	objective_labels[objective].text += objective.description
	if objective.total_count > 0:
		objective_labels[objective].text += " ("+str(objective.current_count)+"/"+str(objective.total_count)+")"
	objective_labels[objective].text += " ["
	if objective.complete:
		objective_labels[objective].text += "✓"
	objective_labels[objective].text += "]"
	await get_tree().process_frame
	await create_tween().tween_property(self, "position", 
	Vector2(position.x, get_viewport_rect().size.y-quest_container.size.y), .1).finished
	if play_anim:
		var copy_label: RichTextLabel = get_objective_label()
		copy_label.text = objective_labels[objective].text
		copy_label.size = objective_labels[objective].size
		add_child(copy_label)
		copy_label.global_position = objective_labels[objective].global_position
		copy_label.global_position.x += objective_labels[objective].size.x
		await create_tween().tween_property(copy_label, "global_position", objective_labels[objective].global_position, .5).finished
		objective_labels[objective].modulate = Color.WHITE
		copy_label.queue_free()

## Updates the quest tracker information
func build_labels(_stage: Resource = null)->void:
	var objectives: Array[QuestObjective] = tracked_quest.get_tracked_objectives()
	for objective in objectives:
		if !objective.objective_updated.is_connected(update_objective):
			objective.objective_updated.connect(update_objective)
		if !objective.objective_completed.is_connected(update_objective):
			objective.objective_completed.connect(update_objective)
		if objective not in objective_labels.keys():
			var new_label: RichTextLabel = get_objective_label()
			objective_container.add_child(new_label)
			objective_labels[objective] = new_label
			update_objective(objective, true)
	for objective in objective_labels.keys():
		if objective not in objectives:
			objective_labels[objective].queue_free()
			objective_labels.erase(objective)
	await create_tween().tween_property(self, "position", 
	Vector2(position.x, get_viewport_rect().size.y-quest_container.size.y), .1).finished

## Makes an objective label and returns it
func get_objective_label()->RichTextLabel:
	var new_label: RichTextLabel = RichTextLabel.new()
	new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	new_label.bbcode_enabled = true
	new_label.add_theme_font_size_override("normal_font_size", 16)
	new_label.fit_content = true
	new_label.use_parent_material = true
	return new_label

## Fades out the tracker when the quest completes
func complete_quest(_quest: QuestInfo)->void:
	await create_tween().tween_property(self, "modulate", Color.TRANSPARENT, 1).finished
	stop_tracking()
	modulate = Color.WHITE

## Starts the combat state and hides the tracker
func start_combat()->void:
	in_combat = true
	hide()

## Ends combat and shows the tracker if it was tracking a quest
func end_combat()->void:
	in_combat = false
	show_if_tracking()

## Stops tracking any quests
func stop_tracking()->void:
	tracked_quest = null
	hide()

## Shows the display if it is currently tracking a quest
func show_if_tracking()->void:
	if tracked_quest != null && !in_combat:
		show()
