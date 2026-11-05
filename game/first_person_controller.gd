extends CharacterBody3D
## Locked third-person airfield pilot controller with smooth wall-aware follow camera.
const WALK_SPEED := 2.9
const RUN_SPEED := 5.5
const GRAVITY := 18.0
const EYE_HEIGHT := 1.64
const SPAWN := Vector3(5.8,.22,7.8)
const FOLLOW_DISTANCE := 2.95
const DEFAULT_PITCH := .22
var enabled := false
var controls_blocked := false
var head: Node3D
var camera: Camera3D
var yaw := .52
var pitch := DEFAULT_PITCH
var facing_yaw := .52
var follow_distance := FOLLOW_DISTANCE
var camera_ready := false
var rmb_looking := false
var jump_requested := false
var auto_walk_active := false
var auto_walk_target := Vector3.ZERO
var auto_walk_callback: Callable
var stride_distance := 0.0
var step_distance := 0.0
var steps_played := 0
var footstep: AudioStreamPlayer
var step_sounds: Array[AudioStream] = []
var step_rng := RandomNumberGenerator.new()
var body_visual: Node3D

func _ready() -> void:
	name = "AirfieldPilot"
	collision_layer = 2
	collision_mask = 5
	floor_snap_length = .32
	floor_constant_speed = true
	floor_max_angle = deg_to_rad(45)
	safe_margin = .005
	var capsule := CapsuleShape3D.new()
	capsule.radius = .27
	capsule.height = 1.76
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = .88
	add_child(collider)
	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	add_child(head)
	camera = Camera3D.new()
	camera.top_level = true
	camera.fov = 62
	camera.near = .08
	camera.far = 2500
	head.add_child(camera)
	body_visual = Node3D.new()
	body_visual.set_script(preload("res://first_person_body.gd"))
	body_visual.pilot = self
	body_visual.position = Vector3.ZERO
	add_child(body_visual)
	footstep = AudioStreamPlayer.new()
	footstep.volume_db = -16
	add_child(footstep)
	step_rng.seed = 47
	for i in range(4):step_sounds.append(load("res://audio/footstep_%d.wav" % i))
	var bindings := [
		["pilot_forward", [KEY_W, KEY_UP]],
		["pilot_back", [KEY_S, KEY_DOWN]],
		["pilot_left", [KEY_A, KEY_LEFT]],
		["pilot_right", [KEY_D, KEY_RIGHT]],
		["pilot_run", [KEY_SHIFT]]
	]
	for entry in bindings:
		if not InputMap.has_action(entry[0]):
			InputMap.add_action(entry[0])
		for keycode in entry[1]:
			var key := InputEventKey.new()
			key.physical_keycode = keycode
			InputMap.action_add_event(entry[0], key)
	respawn()

func respawn() -> void:
	global_position = SPAWN
	velocity = Vector3.ZERO
	jump_requested = false
	stride_distance = 0
	step_distance = 0
	yaw = .52
	pitch = DEFAULT_PITCH
	facing_yaw = .52
	follow_distance = FOLLOW_DISTANCE
	rmb_looking = false
	auto_walk_active = false
	camera_ready = false
	if head:
		head.position = Vector3(0,EYE_HEIGHT,0)
		update_look()
	reset_physics_interpolation()

func set_enabled(value: bool) -> void:
	enabled = value
	body_visual.visible = value
	camera.current = value
	jump_requested = false
	rmb_looking = false
	auto_walk_active = false
	velocity.x = 0
	velocity.z = 0
	if value:
		update_look()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func start_auto_walk(target_pos: Vector3, on_arrived: Callable = Callable()) -> void:
	auto_walk_target = target_pos
	auto_walk_callback = on_arrived
	auto_walk_active = true

func transition_from_camera(from_pos: Vector3, from_yaw: float) -> void:
	yaw = from_yaw
	facing_yaw = from_yaw
	pitch = DEFAULT_PITCH
	follow_distance = FOLLOW_DISTANCE
	if body_visual:
		body_visual.rotation.y = facing_yaw
	if camera:
		camera.global_position = from_pos
		camera_ready = true

func cycle_camera_distance() -> void:
	follow_distance = FOLLOW_DISTANCE
	update_look()

func handle_pointer(event: InputEvent) -> void:
	if not enabled or controls_blocked:
		if rmb_looking:
			rmb_looking = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		rmb_looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and rmb_looking:
		yaw -= event.relative.x*.0026
		pitch = clampf(pitch+event.relative.y*.0022,.05,.65)
	update_look()

func update_look(delta: float = 0.0) -> void:
	if not head:return
	head.rotation = Vector3(-pitch,yaw,0)
	head.position.x = 0.0
	head.position.z = 0.0
	if body_visual:
		body_visual.rotation.y = facing_yaw
		body_visual.position = Vector3.ZERO
	if not camera or not is_inside_tree():return
	var pivot := global_position + Vector3(0, 1.46, 0)
	var orbit_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
	var shoulder := Basis(Vector3.UP, yaw) * Vector3(.18, .12, 0)
	var desired := pivot + shoulder + orbit_basis * Vector3(0, 0, follow_distance)
	var world_3d := get_world_3d()
	if world_3d != null:
		var ray := PhysicsRayQueryParameters3D.create(pivot, desired, 5, [get_rid()])
		var hit := world_3d.direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			desired = hit.position + hit.normal * .22
	if camera_ready and delta > 0.0:
		camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-delta * 14.0))
	else:
		camera.global_position = desired
		camera_ready = true
	var look_target := pivot + Basis(Vector3.UP, yaw) * Vector3(.10, .06 - pitch * .25, -.95)
	if camera.global_position.distance_squared_to(look_target) > .01:
		camera.look_at(look_target, Vector3.UP)

func queue_jump() -> void:
	if enabled and not controls_blocked:jump_requested = true

func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if enabled and not controls_blocked:
		input = Input.get_vector("pilot_left","pilot_right","pilot_forward","pilot_back")
	if input.length() > .05 or controls_blocked or not enabled:
		auto_walk_active = false
	var direction := Vector3.ZERO
	var speed := RUN_SPEED if Input.is_action_pressed("pilot_run") else WALK_SPEED
	if auto_walk_active:
		var to_target := Vector3(auto_walk_target.x - global_position.x, 0.0, auto_walk_target.z - global_position.z)
		if to_target.length() <= 0.85:
			auto_walk_active = false
			if auto_walk_callback.is_valid():
				auto_walk_callback.call_deferred()
		else:
			direction = to_target.normalized()
			var desired_yaw := atan2(-direction.x, -direction.z)
			yaw = lerp_angle(yaw, desired_yaw, 1.0 - exp(-delta * 6.5))
			facing_yaw = lerp_angle(facing_yaw, desired_yaw, 1.0 - exp(-delta * 12.0))
			pitch = lerpf(pitch, DEFAULT_PITCH, 1.0 - exp(-delta * 5.0))
			speed = RUN_SPEED * .86
	else:
		if input.length() > .05 and not rmb_looking:
			yaw -= input.x * 1.65 * delta
			pitch = lerpf(pitch, DEFAULT_PITCH, 1.0 - exp(-delta * 4.0))
		direction = Basis(Vector3.UP,yaw)*Vector3(input.x,0,input.y)
		if direction.length() > .05:
			var target_yaw := atan2(-direction.x, -direction.z)
			facing_yaw = lerp_angle(facing_yaw, target_yaw, 1.0 - exp(-delta * 13.0))
	var target := direction*speed
	velocity.x = move_toward(velocity.x,target.x,18.0*delta)
	velocity.z = move_toward(velocity.z,target.z,18.0*delta)
	if not is_on_floor():velocity.y -= GRAVITY*delta
	elif velocity.y<0:velocity.y = 0
	if jump_requested and is_on_floor():velocity.y = 4.8
	jump_requested = false
	var previously_grounded := is_on_floor()
	move_and_slide()
	if position.y < -15 or absf(position.x)>1040 or absf(position.z)>1040:respawn()
	var actual_speed := Vector2(get_real_velocity().x,get_real_velocity().z).length()
	update_footsteps(delta,actual_speed,previously_grounded)
	var local_velocity := Basis(Vector3.UP,-facing_yaw)*Vector3(get_real_velocity().x,0,get_real_velocity().z)
	body_visual.animate(delta,actual_speed,stride_distance,is_on_floor(),local_velocity)
	update_look(delta)

func update_footsteps(delta: float, speed: float, previously_grounded: bool) -> void:
	var bob := 0.0
	if enabled and is_on_floor():
		if not previously_grounded:play_step(-3)
		if speed>.12:
			var travel := speed*delta
			var step_length := 1.18 if speed>3.5 else .82
			stride_distance += travel/step_length
			step_distance += travel
			if step_distance >= step_length:
				step_distance = fmod(step_distance,step_length)
				play_step(0)
			bob = sin(stride_distance*TAU)*(.012 if speed>3.5 else .006)
	head.position.y = lerpf(head.position.y,EYE_HEIGHT+bob,1-exp(-delta*16))

func play_step(volume_offset: float) -> void:
	if step_sounds.is_empty():return
	steps_played += 1
	footstep.stream = step_sounds[step_rng.randi_range(0,step_sounds.size()-1)]
	footstep.pitch_scale = step_rng.randf_range(.94,1.06)
	footstep.volume_db = -16+volume_offset
	footstep.play()
