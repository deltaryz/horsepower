extends Label

# RESOURCES
@export var logs = 10
@export var rocks = 10
@export var corpses = 0
@export var worker_cap = 5
@export var resource_cap = 200

var storages = []
var food_sources = []
var occupied_tiles = {}
var active_interactables = []

@onready var task_controller = $"../TaskController"
@onready var nomoney: AudioStreamPlayer = $"../nomoney"

# Retrieve a dictionary of storages in order by distance from given location
func get_storage_by_distance(pos: Vector2):
	var distance_storages = {}
	for box in storages:
		var distance = pos.distance_to(box.position)
		distance_storages[distance] = box
	
	var keys = distance_storages.keys()
	keys.sort()
	
	var returned_array = []
	for key in keys:
		returned_array.append(distance_storages[key])
	
	return returned_array
	

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	text = "Workers: " + str(task_controller.workers.size()) + "/" + str(worker_cap)
	text += "\nCapacity: " + str(sum()) + "/" + str(resource_cap)
	text += "\nLogs: " + str(logs)
	text += "\nRocks: " + str(rocks)
	if corpses > 0:
		text += "\nCorpses: " + str(corpses)

# Adds resources (log, rock, corpse) to the stock, making sure we actually have room. Returns 'false' if no room
func add_resource(log: int = 0, rock: int = 0, corpse: int = 0) -> bool:
	var amount = sum() + (log + rock + corpse)
	
	var logCheck = logs + log
	var rockCheck = rocks + rock
	var corpseCheck = corpses + corpse
	var zeroCheck = false
	if logCheck < 0:
		zeroCheck = true
	if rockCheck < 0:
		zeroCheck = true
	if corpseCheck < 0:
		zeroCheck = true
	
	if amount > resource_cap or zeroCheck == true:
		nomoney.play()
		return false
	else:
		logs += log
		rocks += rock
		corpses += corpse
		
		if logs < 0:
			logs = 0
		if rocks < 0:
			rocks = 0
		if corpses < 0:
			corpses = 0
			
		return true
		
func sum() -> int:
	return logs + rocks + corpses
