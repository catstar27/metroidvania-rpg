extends Node
## Autoload that manages saving and loading of all data other than settings

const save_file_folder: String = "user://saves/" ## Folder for save files
const main_scene: PackedScene = preload("res://misc/gameplay_managers/main.tscn") ## Filepath of main scene
var main: Node = null ## Main scene pointer
var recent_slot: String = "save1" ## Most recent save slot name
var loading: bool = false ## Whether the game is currently loading
var saving: bool = false ## Whether the game is currently saving
var in_combat: bool = false ## Whether the game is in a combat state
var level_data: Dictionary[String, Dictionary] = {} ## Dictionary containing all map save data
var player_data: Dictionary[String, Dictionary] = {} ## Dictionary containing data of player characters

func _ready() -> void:
	main = get_tree().root.get_child(-1)
	EventBus.subscribe("START_COMBAT", self, "started_combat")
	EventBus.subscribe("COMBAT_ENDED", self, "ended_combat")

## Called when combat starts
func started_combat(_data: Array[Character])->void:
	in_combat = true

## Called when combat ends
func ended_combat()->void:
	in_combat = false

## Checks if given save slot is blank
func is_slot_blank(check_slot: String)->bool:
	if !DirAccess.dir_exists_absolute(save_file_folder+check_slot):
		return true
	return DirAccess.get_files_at(save_file_folder+check_slot).size() == 0

func _unhandled_input(event: InputEvent)->void:
	if event.is_action_pressed("quicksave"):
		save_data("Quicksave", recent_slot)
	if event.is_action_pressed("quickload"):
		load_data("Quicksave", recent_slot)

#region Delete and Reset
## Gets the path of the latest save file
func get_latest_save(slot_to_check: String)->String:
	if !DirAccess.dir_exists_absolute(save_file_folder+slot_to_check):
		return ""
	var files: PackedStringArray = DirAccess.get_files_at(save_file_folder+slot_to_check)
	var latest_time: int = 0
	var best_file: String = files[0]
	for file in files:
		if FileAccess.get_modified_time(save_file_folder+slot_to_check+'/'+file) > latest_time:
			latest_time = FileAccess.get_modified_time(save_file_folder+slot_to_check+'/'+file)
			best_file = file
	return save_file_folder+slot_to_check+'/'+best_file

## Removes all non-autoload nodes and makes a new main scene
func reset_game()->Main:
	while !get_tree().root.is_node_ready():
		await get_tree().root.ready
	main.queue_free()
	await get_tree().process_frame
	var new_main: Main = main_scene.instantiate()
	get_tree().root.add_child(new_main)
	while !new_main.prepped:
		await new_main.ready
	return new_main

## Resets the given save slot to new game state
func reset_save(reset_slot: String)->void:
	delete_slot(reset_slot)
	saving = true
	loading = true
	level_data = {}
	player_data = {}
	Dialogic.VAR.reset()
	await reset_game()
	saving = false
	loading = false

## Deletes the given save slot
func delete_slot(remove_slot: String)->void:
	if !DirAccess.dir_exists_absolute(save_file_folder+remove_slot):
		return
	saving = true
	loading = true
	clear_dir(save_file_folder+remove_slot)
	DirAccess.remove_absolute(save_file_folder+remove_slot)
	saving = false
	loading = false

## Deletes the given save file
func delete_file(save_name: String, slot: String)->void:
	if !FileAccess.file_exists(save_file_folder+slot+'/'+save_name):
		return
	saving = true
	loading = true
	DirAccess.remove_absolute(save_file_folder+slot+'/'+save_name)
	saving = false
	loading = false

## Clears all files in the given directory
func clear_dir(dir: String)->void:
	for filename in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir+"/"+filename)
	for directory in DirAccess.get_directories_at(dir):
		clear_dir(dir+'/'+directory)
#endregion

#region Save and Load
## Loads the given map if it has data
func load_map(map: GameMap)->void:
	if map.name in level_data:
		map.load_save_data(level_data[map.name])

## Loads the given player's data
func load_player(player: Player)->void:
	if player.name in player_data:
		load_save_dict(player, player_data[player.name])

## Saves the given map to level_data
func save_map(map: GameMap)->void:
	level_data[map.name] = map.get_save_data()

## Saves the player to player_data
func save_player(player: Player)->void:
	player_data[player.name] = get_save_dict(player, ["position"])

func get_save_dict(node: Node, skip_values: Array[String] = [])->Dictionary[String, Variant]:
	var dict: Dictionary[String, Variant] = {}
	node.pre_save()
	for value in node.to_save:
		if value in skip_values:
			continue
		dict[value] = node.get(value)
	if node is Player:
		player_data[node.name] = dict
	node.post_save()
	return dict

func load_save_dict(node: Node, dict: Dictionary[String, Variant])->void:
	node.pre_load()
	for key in dict:
		node.set(key, dict[key])
	if node is Player:
		player_data[node.name] = dict
	node.post_load()

## Saves the game, creating the necessary folders if missing
func save_data(save_name: String, slot: String, quiet_save: bool = false)->void:
	if saving || loading:
		return
	if in_combat:
		EventBus.broadcast("PRINT_LOG", "Cannot Save When in Danger!")
		return
	saving = true
	recent_slot = slot
	if !DirAccess.dir_exists_absolute(save_file_folder):
		DirAccess.make_dir_absolute(save_file_folder)
	if !DirAccess.dir_exists_absolute(save_file_folder+slot):
		DirAccess.make_dir_absolute(save_file_folder+slot)
	var file: FileAccess = FileAccess.open(save_file_folder+slot+'/'+save_name+".dat", FileAccess.WRITE)
	file.store_var(NavMaster.map.scene_file_path)
	var dialogic_vars: Dictionary[String, Variant]
	for variable in Dialogic.VAR.variables():
		dialogic_vars[variable] = Dialogic.VAR.get_variable(variable)
	file.store_var(dialogic_vars)
	var global_data: Dictionary[String, Dictionary]
	for node in get_tree().get_nodes_in_group("Persist"):
		if node is Player:
			save_player(node)
		else:
			global_data[node.name] = get_save_dict(node)
	file.store_var(global_data)
	file.store_var(player_data)
	level_data[NavMaster.map.name] = NavMaster.map.get_save_data()
	file.store_var(level_data)
	file.close()
	if !quiet_save:
		EventBus.broadcast("PRINT_LOG", "Saved!")
	saving = false

## Loads the game
func load_data(save_name: String, slot: String)->void:
	if !DirAccess.dir_exists_absolute(save_file_folder+slot):
		printerr("Save Folder Not Found")
		return
	if DirAccess.get_files_at(save_file_folder+slot).size() < 1:
		printerr("No Save Files in Folder")
		return
	if loading || saving:
		return
	loading = true
	in_combat = false
	var file: FileAccess
	if FileAccess.file_exists(save_file_folder+slot+'/'+save_name+".dat"):
		file = FileAccess.open(save_file_folder+slot+'/'+save_name+".dat", FileAccess.READ)
	else:
		file = FileAccess.open(get_latest_save(slot), FileAccess.READ)
	var cur_map: String = file.get_var()
	main = await reset_game()
	var dialogic_vars: Dictionary[String, Variant] = file.get_var()
	for variable in Dialogic.VAR.variables():
		if variable in dialogic_vars:
			Dialogic.VAR.set_variable(variable, dialogic_vars[variable])
	var global_data = file.get_var()
	for node in get_tree().get_nodes_in_group("Persist"):
		if node.name in global_data:
			load_save_dict(node, global_data[node.name])
	player_data = file.get_var()
	level_data = file.get_var()
	file.close()
	await main.load_map(cur_map)
	EventBus.broadcast("LOADED", "NULLDATA")
	EventBus.broadcast("PRINT_LOG", "Loaded!")
	loading = false
#endregion
