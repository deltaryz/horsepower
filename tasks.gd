extends Node2D

const datastructures = preload("res://datastructures.gd")

@onready var Tutorial = $"../Tutorial"
@onready var tile_map = $"../TileMap"
@onready var building_selector: ItemList = $"BuildingSelector"
@onready var Resources = $"../Resources"
@onready var deathsound = $"../deathsound"
@onready var obelisksound = $"../obelisksound"
@onready var nomoney = $"../nomoney"
var worker = preload("res://worker.tscn")

var taskQueue = []
var workers = []

func _ready():
	Tutorial.visible = true
	Engine.time_scale = 0

# Creates a new worker
func create_worker(pos: Vector2):
	var newWorker = worker.instantiate()
	newWorker.teleport(pos)
	get_parent().add_child(newWorker)
	newWorker._change_state(datastructures.Behavior.IDLE)
	return newWorker

# Creates a task, adds it to the queue, and returns its object
func create_task(taskPosition: Vector2, behavior: datastructures.Behavior):
	var newTask = datastructures.Task.new(taskPosition, behavior)
	taskQueue.append(newTask)
	
	return newTask

# Returns an available task, returns null if no tasks are available
func get_available_task(random = false):
	if taskQueue.size() != 0:
		var available = []
		for task: datastructures.Task in taskQueue:
			if task != null:
				if(task.status == datastructures.Status.AVAILABLE):
					if not random:
						return task
					else:
						available.append(task)
		# Time to pick a random one
		if not available.is_empty():
			return available.pick_random()
			
# Returns array of available tasks in order by distance
func get_available_task_by_distance(pos: Vector2):
	if taskQueue.size() != 0:
		
		# construct available task list
		var available = []
		for task: datastructures.Task in taskQueue:
			if task != null:
				if(task.status == datastructures.Status.AVAILABLE):
					available.append(task)
	
		var distance_tasks = {}
		for task in available:
			var distance = pos.distance_to(task.position)
			distance_tasks[distance] = task
			
		var keys = distance_tasks.keys()
		keys.sort()
		
		var returned_array = []
		for key in keys:
			returned_array.append(distance_tasks[key])
			
		return returned_array
		
# Check if a provided task is present in the current array
func check_task(task: datastructures.Task):
	if taskQueue.has(task):
		return true
	else:
		return false
		
# Make sure tile is in bounds
func check_bounds(tile_id) -> bool:
	var tile = tile_map.get_cell_source_id(0, tile_id)
	if tile_id.y > 12 or tile_id.x > 19: # TODO: Don't hardcode level size
		# Don't use bottom tile
		print("Out of bounds")
	else:
		if tile != -1:
			# something exists here
			print("Obstacle!")
		else:
			return true
	return false

# Process input
func _unhandled_input(event):
	if event.is_action_pressed(&"teleport_to"):
		deathsound.play()
		#obelisksound.play()
		#datastructures.DeadWorker.new(tile_map, get_global_mouse_position(), 3, taskQueue)
		#var newWorker = create_worker(get_global_mouse_position())
		#newWorker.speed = 250
	if event.is_action_pressed(&"move_to"):
		# Remove tutorial & set timescale
		if Engine.time_scale == 0:
			Engine.time_scale = 1
		if Tutorial != null:
			Tutorial.visible = false
			Tutorial.queue_free()
		
		var tile_id = tile_map.local_to_map(get_global_mouse_position())
		
		# Do we have a building selected?
		if building_selector.get_selected_items().size() > 0:
			match building_selector.get_selected_items()[0]:
				
				# TODO: change all of these to use resouces.add_resource()
				
				# Place logger
				datastructures.Buildings.LOGGER:
					if Resources.logs >= 10:
						# Place logger
						if check_bounds(tile_id) == true:
							Resources.logs -= 10
							datastructures.Logger.new(tile_map, get_global_mouse_position(), 3, taskQueue)
					else:
						# We can't afford the logger
						# TODO: sfx for insufficient funds
						print("Can't afford logger")
						nomoney.play()

				# Place rock farm
				datastructures.Buildings.ROCK_FARM:
					if Resources.rocks >= 10:
						# Place rock farm
						if check_bounds(tile_id) == true:
							Resources.rocks -= 10
							datastructures.RockFarm.new(tile_map, get_global_mouse_position(), 3, taskQueue)
					else:
						# Cant afford it
						nomoney.play()
						# TODO: sfx for insufficient funds
						print("Can't afford rock farm")
						
				# Place housing
				datastructures.Buildings.HOUSING:
					if Resources.rocks >= 30 and Resources.logs >= 30 and check_bounds(tile_id) == true:
						Resources.rocks -= 30
						Resources.logs -= 30
						datastructures.Housing.new(tile_map, get_global_mouse_position(), 10, taskQueue)
					else:
						nomoney.play()
						
				# Place worker
				datastructures.Buildings.WORKER:
					# TODO: sfx for insufficient funds
					if Resources.logs >= 20 and Resources.rocks >= 20 and workers.size() < Resources.worker_cap:
						Resources.logs -= 20
						Resources.rocks -= 20
						create_worker(get_global_mouse_position())
					else:
						nomoney.play()
						
				# Place storage
				datastructures.Buildings.STORAGE:
					if Resources.logs >= 10 and Resources.rocks >= 10 and check_bounds(tile_id) == true:
						Resources.logs -= 10
						Resources.rocks -= 10
						
						datastructures.Storage.new(tile_map, get_global_mouse_position(), 3, taskQueue)
					else:
						nomoney.play()
						
				# Place obelisk
				datastructures.Buildings.OBELISK:
					if Resources.logs >= 50 and Resources.rocks >= 50 and check_bounds(tile_id) == true:
						Resources.logs -= 50
						Resources.rocks -= 50
						
						datastructures.Obelisk.new(tile_map, get_global_mouse_position(), 30, taskQueue)
					else:
						nomoney.play()
						
				# Place obstacle
				datastructures.Buildings.OBSTACLE:
					if Resources.occupied_tiles.has(tile_id):
						print("Obstacle")
						nomoney.play()
					else:
						Resources.occupied_tiles.erase(tile_id)
						Resources.occupied_tiles[tile_id] = "OBSTACLE"
						tile_map.set_cell(0, tile_id, 0, datastructures.Textures.OBSTACLE)
						
				# Delete something
				datastructures.Buildings.DELETE:
					# TODO: deal with storage and worker cap
					if Resources.occupied_tiles.has(tile_id):
						nomoney.play()
						if Resources.occupied_tiles[tile_id] is datastructures.Interactable:
							
							if Resources.occupied_tiles[tile_id] is datastructures.Storage:
								Resources.resource_cap -= 50
								
							if Resources.occupied_tiles[tile_id] is datastructures.Housing:
								Resources.worker_cap -= 5
								
							Resources.storages.erase(Resources.occupied_tiles[tile_id])
							Resources.occupied_tiles[tile_id].destroy()
								
						Resources.occupied_tiles.erase(tile_id)
						tile_map.erase_cell(0, tile_id)
