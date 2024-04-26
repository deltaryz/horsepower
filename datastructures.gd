# Behavior states
# IDLE: check for available tasks
# WALK: travel to task position, interact with destination object, then return to idle
enum Behavior { 
	IDLE,
	WALK,
	EAT,
	PLANT_SAPLING,
	PLANT_ROCK,
	PLANT_FARM,
	DEPOSIT_LOG,
	DEPOSIT_ROCK,
	DEPOSIT_CORPSE,
}

# Texture names mapped to atlas coordinates
const Textures = {
	"OBSTACLE": Vector2i(0,0),
	"Logger1": Vector2i(1, 0),
	"Logger2": Vector2i(2, 0),
	"RockFarm1": Vector2i(3, 0),
	"RockFarm2": Vector2i(4, 0),
	"Tree1": Vector2i(0, 1),
	"Tree2": Vector2i(1, 1),
	"Tree3": Vector2i(2, 1),
	"Rock1": Vector2i(0,2),
	"Rock2": Vector2i(1,2),
	"Rock3": Vector2i(2,2),
	"DeadWorker": Vector2i(5,0),
	"House": Vector2i(3,1),
	"Storage": Vector2i(4,1),
	"Farm1": Vector2i(0,3),
	"Farm2": Vector2i(1,3),
	"Farm3": Vector2i(2,3),
	"Farm3Alt": Vector2i(3,3),
	"Obelisk": Vector2i(4,3),
	"Hoe": Vector2i(5,1),
}

# Building names as ordered in the GUI
enum Buildings {
	LOGGER,
	ROCK_FARM,
	HOUSING,
	WORKER,
	STORAGE,
	OBELISK,
	OBSTACLE,
	DELETE
}

# Task status
enum Status {
	AVAILABLE,
	WORKING
}

# Represents a completeable task, including a location, an AI behavior state, and current task status.
class Task:
	var position
	var interactable
	var behavior
	var status
	var timer
	var worker
	
	func _init(taskPosition: Vector2, taskBehavior: Behavior, taskStatus: Status = Status.AVAILABLE):
		position = taskPosition
		behavior = taskBehavior
		status = taskStatus
		
		# TODO: start timer
	
	# TODO: start working function, reset timer when we start working
		
	func set_interactable(inter: Interactable):
		interactable = inter
		position = inter.position
		
	# Set back to "AVAILABLE" and disconnect worker
	func reset():
		# TODO: Reset timer
		status = Status.AVAILABLE
		worker = null

# Represents any interactable object (building, resource, etc)
class Interactable:
	var position: Vector2
	var tileMap: TileMap
	var nonTiledSprite: Sprite2D
	var resources
	var taskController
	var growth: int
	var timer: Timer
	var otherTimer: Timer # dirty hack
	var task: Task
	var progressbar: ProgressBar # Displays progress or capacity
	var isSolid: bool # Is this considered solid?
	var destroying: bool = false
	var styleBox: StyleBoxFlat
	var ticker: AudioStreamPlayer
	var woosher: AudioStreamPlayer
	var wooder: AudioStreamPlayer
	var tapper: AudioStreamPlayer
	var setter: AudioStreamPlayer
	var obelisksound: AudioStreamPlayer
	var particles: GPUParticles2D
	
	func _init(map: TileMap, pos: Vector2, tickrate: int, queue, solid: bool = true):
		tileMap = map
		position = pos
		resources = map.get_node("../Resources")
		taskController = map.get_node("../TaskController")
		growth = 1
		isSolid = solid
		ticker = map.get_node("../ticker")
		woosher = map.get_node("../woosher")
		wooder = map.get_node("../wooder")
		tapper = map.get_node("../tapper")
		setter = map.get_node("../setter")
		obelisksound = map.get_node("../obelisksound")
		
		if resources.occupied_tiles.has(get_tilemap_position()) == true:
			print("Oops! Placing something where there is already something else.")
			destroy(false)
		else:
			# Reference to self in dict
			resources.occupied_tiles.erase(get_tilemap_position())
			resources.occupied_tiles[get_tilemap_position()] = self
			
			resources.active_interactables.append(self)
			
			# setup timer
			timer = Timer.new()
			timer.wait_time = tickrate
			timer.autostart = true
			timer.timeout.connect(_timer_callback)
			tileMap.add_child(timer)
			
			# dirty dirty bad hack
			otherTimer = Timer.new()
			otherTimer.wait_time = 0.0166666667
			otherTimer.autostart = true
			otherTimer.timeout.connect(progress_bar_update)
			tileMap.add_child(otherTimer)
			
			# setup progressbar
			progressbar = ProgressBar.new()
			styleBox = StyleBoxFlat.new()
			progressbar.add_theme_stylebox_override("fill", styleBox)
			styleBox.bg_color = Color.RED
			styleBox.set_corner_radius_all(10)
			progressbar.get_theme_stylebox("background").bg_color = Color(0,0,0,0.7)
			progressbar.show_percentage = false
			progressbar.size = Vector2(48, 6)
			progressbar.max_value = 100
			progressbar.position = get_tilemap_position() * 64
			progressbar.position.x += 8
			progressbar.position.y += 32
			progressbar.visible = false
			tileMap.add_child(progressbar)
		
	# Runs every frame to update progressbar
	func progress_bar_update():
		if progressbar != null:
			progressbar.value = ((timer.time_left / timer.wait_time * 100) - 100) * -1
		
	# Returns tilemap coordinates as a Vector2
	func get_tilemap_position():
		return tileMap.local_to_map(position)
		
	# Sets texture using Vector2i atlas coordinates
	func set_tile_texture(img: Vector2i):
		if destroying == false:
			tileMap.set_cell(0, get_tilemap_position(), 0, img)
		
	# Creates a task for this object
	func set_task(behave: Behavior) -> Task:
		if destroying == false:
			task = Task.new(position, behave)
			task.set_interactable(self)
			return task
		return null
	
	func _timer_callback():
		var _unused = null
	
	# Called when a worker reaches this object as part of their task, returns a behavior
	func interact(worker) -> Behavior:
		return Behavior.IDLE
		
	# Remove this object from the tilemap & clean up from game
	func destroy(deleteCell: bool = true):
		destroying = true
		resources.active_interactables.erase(self)
		taskController.taskQueue.erase(task)
		if particles != null:
			particles.emitting = false
			particles.queue_free()
		if timer != null:
			timer.stop()
			timer.queue_free()
		if otherTimer != null:
			otherTimer.queue_free()
		if progressbar != null:
			progressbar.queue_free()
		if nonTiledSprite != null:
			nonTiledSprite.queue_free()
		if deleteCell == true:
			resources.occupied_tiles.erase(get_tilemap_position())
			tileMap.erase_cell(0, get_tilemap_position())
			
# Dead worker object
class DeadWorker extends Interactable:
	func _init(map: TileMap, pos: Vector2, tickrate: int, queue):
		tileMap = map
		position = pos
		resources = map.get_node("../Resources")
		taskController = map.get_node("../TaskController")
		growth = 1
		setter = map.get_node("../setter")
		
		resources.active_interactables.append(self)
		
		# Create sprite for this object
		# TODO: split this into func on Interactable
		nonTiledSprite = Sprite2D.new()
		nonTiledSprite.texture = load("res://tileset/tilesheet.png")
		nonTiledSprite.region_enabled = true
		nonTiledSprite.region_rect.size = Vector2(64,64)
		nonTiledSprite.region_rect.position = Textures.DeadWorker * 64
		tileMap.add_child(nonTiledSprite)
		nonTiledSprite.position = pos
		
		set_task(Behavior.WALK)
		taskController.taskQueue.append(task)
		
	func interact(worker) -> Behavior:
		destroy(false)
		setter.play()
		return Behavior.DEPOSIT_CORPSE 

class Plant extends Interactable:
	func _init(map: TileMap, pos: Vector2, tickrate: int, queue):
		super(map, pos, tickrate, queue)
		set_tile_texture(Textures.Tree1)
		set_task(Behavior.WALK)
		
	func interact(worker) -> Behavior:
		destroy()
		woosher.play()
		return Behavior.DEPOSIT_LOG
		
	# Tree growth
	func _timer_callback():
		match growth:
			1:
				set_tile_texture(Textures.Tree2)
				growth = 2
			2:
				set_tile_texture(Textures.Tree3)
				growth = 3
				# Ready to be harvested
				taskController.taskQueue.append(task)
				
class Rock extends Interactable:
	func _init(map: TileMap, pos: Vector2, tickrate: int, queue):
		super(map, pos, tickrate, queue)
		set_tile_texture(Textures.Rock1)
		set_task(Behavior.WALK)
		
	func interact(worker) -> Behavior:
		destroy()
		woosher.play()
		return Behavior.DEPOSIT_ROCK
		
	# Rock growth
	func _timer_callback():
		match growth:
			1:
				set_tile_texture(Textures.Rock2)
				growth = 2
			2:
				set_tile_texture(Textures.Rock3)
				growth = 3
				# Ready to be harvested
				taskController.taskQueue.append(task)
				
class Farm extends Interactable:
	func _init(map: TileMap, pos: Vector2, tickrate: int, queue):
		super(map, pos, tickrate, queue)
		set_tile_texture(Textures.Farm1)
		set_task(Behavior.WALK)
		woosher.play()
		resources.occupied_tiles[get_tilemap_position()] = self
		task.position = get_tilemap_position() * 64 + Vector2i(32,32)
		
	func interact(worker) -> Behavior:
		setter.play() # TODO: make unique sfx for eating
		worker.hungerLevel = 3
		worker.HungerTimer.start()
		resources.food_sources.erase(self)
		destroy()
		return Behavior.IDLE
	
	# Farm growth
	func _timer_callback():
		match growth:
			1:
				set_tile_texture(Textures.Farm2)
			2:
				
				# pick random texture
				if randi_range(0, 1) == 1:
					set_tile_texture(Textures.Farm3)
				else:
					set_tile_texture(Textures.Farm3Alt)
				resources.food_sources.append(self)
			3:
				# remove food if not eaten
				print("food spoiled")
				resources.food_sources.erase(self)
				destroy()
				
		growth = growth + 1

class Logger extends Interactable:
	func _init(map: TileMap, pos: Vector2, tickrate: int, queue):
		super(map, pos, tickrate, queue)
		progressbar.visible = true
		set_tile_texture(Textures.Logger1)
		set_task(Behavior.WALK)
		task.position = get_tilemap_position() * 64 + Vector2i(32,32)
		tapper.play()
		
	# Worker has arrived to get sapling
	func interact(worker) -> Behavior:
		taskController.taskQueue.erase(task)
		progressbar.visible = true
		set_tile_texture(Textures.Logger1)
		timer.start() # reset timer
		setter.play()
		return Behavior.PLANT_SAPLING
	
	# Add task to queue on tick
	func _timer_callback():
		if taskController.taskQueue.has(task) == false:
			progressbar.visible = false
			# Logger is ready to provide sapling
			set_tile_texture(Textures.Logger2)
			task.reset()
			taskController.taskQueue.append(task)
			
class RockFarm extends Interactable:
	func _init(map: TileMap, pos: Vector2, tickrate: int, queue):
		super(map, pos, tickrate, queue)
		progressbar.visible = true
		set_tile_texture(Textures.RockFarm1)
		set_task(Behavior.WALK)
		task.position = get_tilemap_position() * 64 + Vector2i(32,32)
		styleBox.bg_color = Color.SKY_BLUE
		tapper.play()
		
	# Worker has arrived to get rock
	func interact(worker) -> Behavior:
		taskController.taskQueue.erase(task)
		progressbar.visible = true
		set_tile_texture(Textures.RockFarm1)
		timer.start() # reset timer
		setter.play()
		return Behavior.PLANT_ROCK
		
	# Add task to queue on tick
	func _timer_callback():
		if taskController.taskQueue.has(task) == false:
			progressbar.visible = false
			# Rock farm is ready to provide rock
			set_tile_texture(Textures.RockFarm2)
			task.reset()
			taskController.taskQueue.append(task)
			
class Obelisk extends Interactable:
	func _init(map: TileMap, pos: Vector2, tickrate: int, queue):
		super(map, pos, tickrate, queue)
		progressbar.visible = true 
		set_tile_texture(Textures.Obelisk)
		set_task(Behavior.WALK) # TODO: behavior to retrieve corpse first, then walk here
		progressbar.position.y += 24
		task.position = get_tilemap_position() * 64 + Vector2i(32,32)
		# TODO: special obelisk sound
		particles = map.get_node("../ObeliskParticles").duplicate()
		map.add_child(particles)
		particles.position = get_tilemap_position() * 64 + Vector2i(32,32)
		# TODO: setup particles
		
	func interact(worker) -> Behavior:
		
		if resources.add_resource(0,0,-1) == true:
			obelisksound.play()
			# Buff the worker
			worker.speed += 50
			# give the worker fun particles
			if worker.particles == null:
				var newParticles = particles.duplicate()
				newParticles.emitting = true
				tileMap.add_child(newParticles)
				worker.particles = newParticles
		
		worker.HeldItemSprite.visible = false
		particles.emitting = false
		taskController.taskQueue.erase(task)
		progressbar.visible = true
		timer.start() # reset timer
		return Behavior.IDLE
		
	func _timer_callback():
		if taskController.taskQueue.has(task) == false:
			progressbar.visible = false
			particles.emitting = true
			# TODO:  Start sparkling
			task.reset()
			taskController.taskQueue.append(task)

# Housing that produces workers and raises the unit cap
class Housing extends Interactable:
	func _init(map: TileMap, pos: Vector2, tickrate: int, queue):
		super(map, pos, tickrate, queue)
		progressbar.visible = true
		styleBox.bg_color = Color.GREEN
		set_tile_texture(Textures.House)
		set_task(Behavior.WALK) # we don't use this but it doesn't work if it's not here...???
		ticker.play()
		
		# Raise worker limit
		resources.worker_cap += 5
#
	# Generate a worker if we have slots & resources
	func _timer_callback():
		if taskController.workers.size() < resources.worker_cap and resources.logs >= 20 and resources.rocks >= 20:
			# TODO: sound effect
			resources.logs -= 20
			resources.rocks -= 20
			var newWorker = taskController.create_worker(position)
			timer.start()
			
	func progress_bar_update():
		if taskController.workers.size() < resources.worker_cap:
			progressbar.visible = true
			progressbar.value = ((timer.time_left / timer.wait_time * 100) - 100) * -1
		else:
			progressbar.visible = false

# Storage building that allows more resources to be held
class Storage extends Interactable:
	func _init(map: TileMap, pos: Vector2, tickrate: int, queue):
		super(map, pos, tickrate, queue)
		progressbar.visible = true
		set_tile_texture(Textures.Storage)
		position = get_tilemap_position() * 64 + Vector2i(32,32)
		set_task(Behavior.WALK)
		
		wooder.play()
		
		# Raise storage limit
		resources.resource_cap += 50
		
		# This way we can keep track of where they are
		resources.storages.append(self)
		
	func progress_bar_update():
		progressbar.max_value = resources.resource_cap
		progressbar.value = resources.sum()
