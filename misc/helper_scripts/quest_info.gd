extends Node
class_name QuestInfo

@export var quest_name: String
@export var quest_id: String
@export var quest_description: String
@export var quest_icon: Sprite2D
@export var quest_stages: Array[QuestStage]
var stage_count: int
var current_stage: int = 0
var complete: bool = false
signal quest_complete(quest: QuestInfo)
signal objective_updated(stage: QuestObjective)

func _ready() -> void:
	stage_count = quest_stages.size()
	for stage in quest_stages:
		stage.stage_completed.connect(quest_stage_complete)
		stage.objective_updated.connect(update_quest)

func quest_stage_complete(stage: QuestStage)->void:
	stage.stage_completed.disconnect(quest_stage_complete)
	stage.objective_updated.disconnect(update_quest)
	current_stage += 1
	if current_stage == stage_count:
		complete = true
		quest_complete.emit(self)

func update_quest(objective: QuestObjective)->void:
	objective_updated.emit(objective)
