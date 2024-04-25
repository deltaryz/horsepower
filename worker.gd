extends Node2D

const datastructures = preload("res://datastructures.gd")

const MASS = 10.0
const ARRIVE_DISTANCE = 12.0

@export var speed: float = 200.0

var _state = datastructures.Behavior.IDLE # start as idle
var _velocity = Vector2()

var hungerLevel: int = 3

@onready var _tile_map: TileMap = $"../TileMap"
@onready var TaskController = $"../TaskController"
@onready var HeldItemSprite: Sprite2D = $"HeldItemSprite"
@onready var Resources = $"../Resources"
@onready var Target: Sprite2D = $"Target"
@onready var HungerTimer: Timer = $"HungerTimer"
@onready var HungerBar: ProgressBar = $"HungerBar"

# got this is awful please make this better
@onready var ticker: AudioStreamPlayer = $"../ticker"
@onready var woosher: AudioStreamPlayer = $"../woosher"
@onready var wooder: AudioStreamPlayer = $"../wooder"
@onready var tapper: AudioStreamPlayer = $"../tapper"
@onready var setter: AudioStreamPlayer = $"../setter"
@onready var nomoney: AudioStreamPlayer = $"../nomoney"
@onready var deathsound: AudioStreamPlayer = $"../deathsound"

var particles: GPUParticles2D

const CELL_SIZE = Vector2i(64, 64)
const BASE_LINE_WIDTH = 3.0
const DRAW_COLOR = Color.WHITE * Color(1, 1, 1, 0.5)
const BOUNDS = Rect2i(0, 0, 20, 13)

# The object for pathfinding on 2D grids.
var _astar = AStarGrid2D.new()

var _start_point = Vector2i()
var _end_point = Vector2i()

var current_task: datastructures.Task

var _path = PackedVector2Array()
var _next_point = Vector2()

# Teleport to coordinates
func teleport(pos):
	global_position = pos
	
# Handle changing of hunger states, kill if starved
func _reduce_hunger_state():
	match hungerLevel:
		3:
			hungerLevel -= 1
			HungerBar.value = hungerLevel
		2:
			hungerLevel -= 1
			HungerBar.value = hungerLevel
		1:
			hungerLevel -= 1
			kill()

# Run when object initializes
func _ready():
	# Add ourselves to the task controller's array
	TaskController.workers.append(self)
	
	ticker.play()
	
	HungerTimer.timeout.connect(_reduce_hunger_state)
	
	# This way it doesn't rotate with the worker
	remove_child(Target)
	_tile_map.add_child(Target)
	
	remove_child(HungerBar)
	_tile_map.add_child(HungerBar)
	
	_state = datastructures.Behavior.IDLE
	# Region should match the size of the playable area plus one (in tiles).
	_astar.region = BOUNDS
	_astar.cell_size = CELL_SIZE
	_astar.offset = CELL_SIZE * 0.5
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()

# Recalculate collision
func recalculate_solids():
	# Determine which tiles are solid
	for i in range(_astar.region.position.x, _astar.region.end.x):
		for j in range(_astar.region.position.y, _astar.region.end.y):
			var pos = Vector2i(i, j)
			
			# Check for the presence of anything
			# NOTE: if anything is added to other layers or tilemaps, this needs to be adjusted
			if _tile_map.get_cell_source_id(0, pos) == 0:
				_astar.set_point_solid(pos)
			else:
				_astar.set_point_solid(pos, false)

# Check if tile is solid based on local position
func is_point_walkable(local_position: Vector2, solid_destination: bool = false):
	var map_position = _tile_map.local_to_map(local_position)
	if _astar.is_in_boundsv(map_position):
		recalculate_solids()
		
		# Make sure destination is walkable
		if solid_destination == false:
			_astar.set_point_solid(_tile_map.local_to_map(local_position), false)
			
		return not _astar.is_point_solid(map_position)
	return false

# Clear path if not empty
func clear_path():
	if not _path.is_empty():
		_path.clear()
		
# Perform pathfinding from local_start_point to local_end_point
func find_path(local_start_point, local_end_point, solid_destination = false):
	clear_path()
	
	recalculate_solids()

	# Convert local coords to map tiles
	_start_point = _tile_map.local_to_map(local_start_point)
	_end_point = _tile_map.local_to_map(local_end_point)
	
	# Clamp _start_point and _end_point to be within BOUNDS
	_start_point.x = clamp(_start_point.x, BOUNDS.position.x, BOUNDS.position.x + BOUNDS.size.x - 1)
	_start_point.y = clamp(_start_point.y, BOUNDS.position.y, BOUNDS.position.y + BOUNDS.size.y - 1)
	_end_point.x = clamp(_end_point.x, BOUNDS.position.x, BOUNDS.position.x + BOUNDS.size.x - 1)
	_end_point.y = clamp(_end_point.y, BOUNDS.position.y, BOUNDS.position.y + BOUNDS.size.y - 1)
	
	# Make sure destination is walkable
	if solid_destination == false:
		_astar.set_point_solid(_end_point, false)
	
	# Perform pathfinding
	_path = _astar.get_point_path(_start_point, _end_point)

	return _path.duplicate()

# Run every frame
func _process(_delta):
	
	# Update held item sprite's rotation
	HeldItemSprite.rotation = _tile_map.global_rotation - global_rotation
	HungerBar.rotation = 0
	HungerBar.position = position
	HungerBar.position += Vector2(-16,12)
	HungerBar.z_index = 100
	
	if particles != null:
		particles.position = position
	
	# Update target crosshair
	if current_task != null and _state != datastructures.Behavior.IDLE:
		Target.visible = true
		Target.position = current_task.position
	else:
		Target.visible = false
	
	match _state:
		
		datastructures.Behavior.IDLE:
			HeldItemSprite.visible = false
			_change_state(datastructures.Behavior.IDLE, false)
			
		datastructures.Behavior.WALK, datastructures.Behavior.EAT:
			HeldItemSprite.visible = false
			
			if current_task.interactable != null:
				if current_task.interactable is datastructures.Obelisk and Resources.corpses > 0:
					set_texture(datastructures.Textures.DeadWorker)
					HeldItemSprite.visible = true
			
			if is_point_walkable(current_task.position, false):
				if travel() == true:
					if current_task.interactable != null:
						# Let the object tell us what to do next
						_change_state(current_task.interactable.interact(self))
					else:
						print("Tried to walk to something that doesnt exist anymore")
						TaskController.taskQueue.erase(current_task)
						_change_state(datastructures.Behavior.IDLE, false)
			else:
				# try again lol
				current_task.reset()
				_change_state(datastructures.Behavior.IDLE, false)
					
		datastructures.Behavior.PLANT_SAPLING:
			HeldItemSprite.visible = true
			set_texture(datastructures.Textures.Tree1)
			
			
			if is_point_walkable(current_task.position, true):
				if travel() == true:
					if _tile_map.get_cell_source_id(0, _tile_map.local_to_map(current_task.position)) == -1:
						datastructures.Plant.new(_tile_map, current_task.position, 3, TaskController.taskQueue)
						_change_state(datastructures.Behavior.IDLE)
						tapper.play()
					else:
						print("Can't plant here")
						_change_state(datastructures.Behavior.PLANT_SAPLING)
			else:
				# try again lol
				_change_state(datastructures.Behavior.PLANT_SAPLING)
				
		datastructures.Behavior.PLANT_ROCK:
			HeldItemSprite.visible = true
			set_texture(datastructures.Textures.Rock1)
			
			
			if is_point_walkable(current_task.position, true):
				if travel() == true:
					# TODO: play sfx
					if _tile_map.get_cell_source_id(0, _tile_map.local_to_map(current_task.position)) == -1:
						datastructures.Rock.new(_tile_map, current_task.position, 3, TaskController.taskQueue)
						_change_state(datastructures.Behavior.IDLE)
						tapper.play()
					else:
						print("Can't plant here")
						_change_state(datastructures.Behavior.PLANT_ROCK)
			else:
				# try again lol
				_change_state(datastructures.Behavior.PLANT_ROCK)
				
		datastructures.Behavior.PLANT_FARM:
			HeldItemSprite.visible = true
			set_texture(datastructures.Textures.Hoe)
			
			if is_point_walkable(current_task.position, true):
				if travel() == true:
					if Resources.add_resource(-5,-5,0) == true:
						datastructures.Farm.new(_tile_map, current_task.position, 15, TaskController.taskQueue)
						_change_state(datastructures.Behavior.IDLE)
						tapper.play()
						HeldItemSprite.visible = false
					else:
						# Can't afford it
						nomoney.play()
						_change_state(datastructures.Behavior.IDLE)
			else:
				# try again
				_change_state(datastructures.Behavior.PLANT_FARM)
				
		datastructures.Behavior.DEPOSIT_LOG:
			HeldItemSprite.visible = true
			set_texture(datastructures.Textures.Tree3)
			
			if travel() == true:
				# Successfully made it to storage
				# TODO: indication when full
				wooder.play()
				HeldItemSprite.visible = false
				var amount = randi_range(5, 10)
				Resources.add_resource(amount,0,0)
				_change_state(datastructures.Behavior.IDLE)
				
		datastructures.Behavior.DEPOSIT_ROCK:
			HeldItemSprite.visible = true
			set_texture(datastructures.Textures.Rock3)
			
			if travel() == true:
				# Successfully made it to storage
				# TODO: indication when full
				wooder.play()
				HeldItemSprite.visible = false
				var amount = randi_range(5, 10)
				Resources.add_resource(0,amount,0)
				_change_state(datastructures.Behavior.IDLE)
				
		datastructures.Behavior.DEPOSIT_CORPSE:
			HeldItemSprite.visible = true
			set_texture(datastructures.Textures.DeadWorker)
			
			if travel() == true:
				# Successfully made it to storage
				# TODO: indication when full
				wooder.play()
				Resources.add_resource(0,0,1)
				_change_state(datastructures.Behavior.IDLE)

# Takes a datastructures.Textures input to set HeldItemSprite's texture
func set_texture(img):
	HeldItemSprite.region_rect.position.x = img.x * 64
	HeldItemSprite.region_rect.position.y = img.y * 64

func start_task(task: datastructures.Task):
	current_task = task
	
	task.status = datastructures.Status.WORKING
	task.worker = self
	_change_state(task.behavior)

func travel():
	_path = find_path(position, current_task.position)
	
	# make sure our target still exits
	if _state == datastructures.Behavior.WALK or _state == datastructures.Behavior.EAT:
		#this ignores non-tile bodies
		if Resources.active_interactables.has(current_task.interactable) == false:
			# Can't do this anymore
			var task: datastructures.Task = TaskController.get_available_task(true)
			if task != null:
				start_task(task)
			return false
	
	# check if we're boxed in
	if _path.size() > 1:
		_next_point = _path[1]
	elif _path.size() == 1:
		_next_point = _path[0]
	else:
		# The worker has been boxed in!
		
		current_task.reset()
		
		if _state == datastructures.Behavior.WALK:
			# Find a new thing to do, we can't reach this one
			var task: datastructures.Task = TaskController.get_available_task(true)
			if task != null:
				start_task(task)
			return false
		else:
			# Try to do this thing again
			_change_state(_state)
			return false
	
		
	if is_point_walkable(_next_point):
		# our next point is still traversible
		var arrived_to_next_point = _walk_to(_next_point)
		if arrived_to_next_point:
			# Remove this point from path
			_path.remove_at(0)
			
			if _path.is_empty():
				# We're done moving!
				return true
				
			_next_point = _path[0]
			return false

# Move with velocity, returns 'true' if destination has been reached
func _walk_to(local_position):
	var desired_velocity = (local_position - position).normalized() * speed
	var steering = desired_velocity - _velocity
	_velocity += steering / MASS
	position += _velocity * get_process_delta_time()
	rotation = _velocity.angle()
	return position.distance_to(local_position) < ARRIVE_DISTANCE

# Transition between states
func _change_state(new_state, randomDeath: bool = true):
	Target.visible = false
	match new_state:
		
		datastructures.Behavior.IDLE:
			
			clear_path()
			
			# Random change to change state depending on hunger level
			match hungerLevel:
				# Don't do anything different for 3
				
				2:
					var rng = randi_range(0,5)
					if rng == 1:
						_change_state(datastructures.Behavior.PLANT_FARM)
						new_state = datastructures.Behavior.PLANT_FARM
						
				1:
					# Seek a fully grown farm
					var rng = randi_range(0,4) # TODO: tweak frequency
					if rng != 1 and Resources.food_sources.size() > 0:
						_change_state(datastructures.Behavior.EAT)
						new_state = datastructures.Behavior.EAT
						
			# Are we still idle??
			if new_state == datastructures.Behavior.IDLE:
				
				# Pick closest accessible task
				var tasks = TaskController.get_available_task_by_distance(position)
				if tasks != null:
					
					# Removing inaccessible
					for task in tasks:
						var path = find_path(position, task.position)
						if path.size() == 0:
							# Not accessible
							tasks.erase(task)
							
					if tasks.size() > 0:
						start_task(tasks[0])
						new_state = tasks[0].behavior
						
		datastructures.Behavior.EAT:
			var target: datastructures.Farm = Resources.food_sources.pick_random()
			# TODO: pick closest
			current_task = target.task
			new_state = current_task.behavior
						
		datastructures.Behavior.PLANT_FARM:
			
			# TODO: make player zone where farms can be placed
			var location = _tile_map.map_to_local(random_coordinates())
			while is_point_walkable(location, true) == false:
				# Keep randomizing until we find a valid spot
				location = _tile_map.map_to_local(random_coordinates())
				
			current_task = datastructures.Task.new(location, new_state)
			
		datastructures.Behavior.PLANT_SAPLING, datastructures.Behavior.PLANT_ROCK:
			# Pick random spot
			var location = _tile_map.map_to_local(random_coordinates())
			while is_point_walkable(location, true) == false:
				# Keep randomizing until we find a valid spot
				location = _tile_map.map_to_local(random_coordinates())
			
			current_task = datastructures.Task.new(location, new_state)
			
		datastructures.Behavior.DEPOSIT_LOG, datastructures.Behavior.DEPOSIT_ROCK, datastructures.Behavior.DEPOSIT_CORPSE:
			# Pick a storage receptacle
			if Resources.storages.size() > 0:
			
				# Storages in order by distance
				var candidates = Resources.get_storage_by_distance(position)
				
				# Remove inaccessible from candidates
				for box in candidates:
					var path = find_path(position, box.position)
					if path.size() == 0:
						# Not accessible
						candidates.erase(box)
						
				if candidates.size() == 0:
					# No candidatges
					nomoney.play()
					new_state = datastructures.Behavior.IDLE
				else:
					current_task = datastructures.Task.new(candidates[0].position, new_state)
				
			else:
				nomoney.play()
				new_state = datastructures.Behavior.IDLE

	_state = new_state

# Returns random coordinates as a Vector2
func random_coordinates():
	var randomX = randi_range(BOUNDS.position.x, BOUNDS.position.x + BOUNDS.size.x - 1)
	var randomY = randi_range(BOUNDS.position.y, BOUNDS.position.y + BOUNDS.size.y - 1)
	return Vector2(randomX, randomY)

# Remove from game and create a dead worker in this position
func kill():
	print("Worker died at " + str(position))
	deathsound.play()
	if current_task != null:
		current_task.reset()
	if particles != null:
		particles.emitting = false
		particles.queue_free()
	Target.visible = false
	HungerBar.queue_free()
	TaskController.workers.erase(self)
	datastructures.DeadWorker.new(_tile_map, position, 3, TaskController.taskQueue)
	get_parent().remove_child(self)
	queue_free()
