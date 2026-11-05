extends CharacterBody3D
## Assisted flight model, deliberately forgiving rather than an aerodynamic simulator.
## The Blender aircraft faces local +Z. Collision uses a small set of convex shapes.
signal crashed(reason: String)
signal fuel_burned(litres: float)
signal lifted_off
signal touched_down(sink_rate: float)
const Catalog = preload("res://aircraft_catalog.gd")
const I18n = preload("res://i18n.gd")
const TAKEOFF_SPEED := 20.0
const STALL_SPEED := 18.0
var aircraft_id := "heron"
var profile: Dictionary = Catalog.DATA["heron"]
var takeoff_speed := TAKEOFF_SPEED
var stall_speed := STALL_SPEED
var collision_boxes: Array[CollisionShape3D] = []
var occupied := false
var suspended := false
var wrecked := false
var engine_running := false
var fuel_available := true
var throttle := 0.0
var airspeed := 0.0
var heading := 0.0
var nose_pitch := 0.0
var bank := 0.0
var airborne := false
var flight_seconds := 0.0
var distance_flown := 0.0
var last_sink_rate := 0.0
var model: Node3D
var propeller: Node3D
var chase: Camera3D
var ground_height: Callable
var guide_target_provider: Callable
var assist_enabled := true
var control_override := false
var override_pitch := 0.0
var override_steer := 0.0
var override_brake := false
var camera_ready := false
var chase_zoom := 1.0
var mouse_steering := false
var mouse_steer := 0.0
var mouse_pitch := 0.0
var engine_sound: AudioStreamPlayer

func _ready() -> void:
	name = "Heron"
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = .25
	floor_max_angle = deg_to_rad(32)
	safe_margin = .005
	max_slides = 4
	configure_aircraft("heron")
	chase = Camera3D.new()
	chase.top_level = true
	chase.fov = 63
	chase.near = .15
	chase.far = 5000
	add_child(chase)
	engine_sound = AudioStreamPlayer.new()
	engine_sound.stream = load("res://audio/heron_engine.wav")
	if engine_sound.stream is AudioStreamWAV:
		engine_sound.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		engine_sound.stream.loop_end = 22050
	engine_sound.volume_db = -25
	add_child(engine_sound)

func configure_aircraft(id: String) -> bool:
	if not Catalog.DATA.has(id) or airborne or engine_running:return false
	var next_profile: Dictionary = Catalog.DATA[id]
	var packed := load("res://assets/%s.glb" % next_profile.asset) as PackedScene
	if packed==null:return false
	var next_model := packed.instantiate() as Node3D
	if is_instance_valid(model):
		remove_child(model)
		model.queue_free()
	for collider in collision_boxes:
		remove_child(collider)
		collider.queue_free()
	collision_boxes.clear()
	aircraft_id = id
	profile = next_profile
	if id == "skywhale":
		name = "Skywhale"
	elif id == "albatross":
		name = "Albatross"
	elif id == "osprey":
		name = "Osprey"
	else:
		name = "Heron"
	takeoff_speed = float(profile.takeoff_speed)
	stall_speed = float(profile.stall_speed)
	if id == "skywhale":
		add_box(Vector3(0, 2.10, -0.50), Vector3(2.30, 2.10, 11.8))
		add_box(Vector3(0, 3.42, 0.45), Vector3(18.5, 0.26, 2.40))
		for side in [-1, 1]: add_box(Vector3(side * 1.88, 0.44, -0.48), Vector3(0.45, 0.88, 0.88))
		add_box(Vector3(0, 0.31, 4.68), Vector3(0.26, 0.62, 0.62))
	elif id == "albatross":
		add_box(Vector3(0, 1.85, -0.40), Vector3(1.85, 1.80, 9.2))
		add_box(Vector3(0, 3.02, 0.40), Vector3(15.0, 0.22, 2.00))
		for side in [-1, 1]: add_box(Vector3(side * 1.54, 0.40, -0.42), Vector3(0.35, 0.80, 0.80))
		add_box(Vector3(0, 0.29, 3.72), Vector3(0.22, 0.58, 0.58))
	elif id == "osprey":
		add_box(Vector3(0,1.65,-.30),Vector3(1.48,1.55,6.9))
		add_box(Vector3(0,2.77,.35),Vector3(11.7,.18,1.65))
		for side in [-1,1]:add_box(Vector3(side*1.24,.38,-.32),Vector3(.3,.75,.75))
		add_box(Vector3(0,.27,2.65),Vector3(.18,.54,.54))
	else:
		add_box(Vector3(0,1.45,-.25),Vector3(1.2,1.45,5.3))
		add_box(Vector3(0,2.5,.23),Vector3(10.05,.16,1.45))
		for side in [-1,1]:add_box(Vector3(side*1.15,.42,.86),Vector3(.3,.82,.82))
		add_box(Vector3(0,.21,-3.16),Vector3(.18,.4,.4))
	model = next_model
	add_child(model)
	propeller = Node3D.new()
	if id == "skywhale":
		propeller.position = Vector3(0, 2.02, 6.18)
	elif id == "albatross":
		propeller.position = Vector3(0, 1.85, 4.96)
	elif id == "osprey":
		propeller.position = Vector3(0, 1.70, 3.62)
	else:
		propeller.position = Vector3(0, 1.47, 2.83)
	model.add_child(propeller)
	collect_propeller(model)
	camera_ready = false
	return true

func add_box(at: Vector3, size: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position = at
	add_child(collider)
	collision_boxes.append(collider)

func collect_propeller(node: Node) -> void:
	for child in node.get_children():
		if child==propeller:continue
		if child is MeshInstance3D and ("Propeller_blade" in child.name or "Propeller_safety" in child.name or "Propeller blade" in child.name or "Propeller safety" in child.name):
			child.reparent(propeller,true)
		else:collect_propeller(child)

func transition_from_camera(from_pos: Vector3) -> void:
	if chase:
		chase.global_position = from_pos
		camera_ready = true

func cycle_chase_zoom() -> void:
	chase_zoom = 1.0

func handle_pointer(event: InputEvent) -> void:
	if not occupied or suspended or control_override:
		if mouse_steering:
			mouse_steering = false
			mouse_steer = 0.0
			mouse_pitch = 0.0
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			mouse_steering = event.pressed
			if not mouse_steering:
				mouse_steer = 0.0
				mouse_pitch = 0.0
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and mouse_steering:
		mouse_steer = clampf(mouse_steer + event.relative.x * .0035, -1.0, 1.0)
		mouse_pitch = clampf(mouse_pitch - event.relative.y * .0032, -1.0, 1.0)

func reset_at(at: Vector3, yaw: float) -> void:
	position = at
	heading = yaw
	nose_pitch = 0
	bank = 0
	rotation = Vector3(0,heading,0)
	velocity = Vector3.ZERO
	airspeed = 0
	throttle = 0
	engine_running = false
	wrecked = false
	airborne = false
	mouse_steering = false
	mouse_steer = 0.0
	mouse_pitch = 0.0
	floor_snap_length = .25
	flight_seconds = 0
	distance_flown = 0
	camera_ready = false
	reset_physics_interpolation()

func toggle_engine() -> bool:
	if wrecked or (not engine_running and not fuel_available):return false
	engine_running = not engine_running
	if not engine_running:throttle = 0
	return true

func can_exit() -> bool:
	return not airborne and is_on_floor() and airspeed<.8 and not engine_running and not wrecked

func fail(reason: String) -> void:
	if wrecked:return
	wrecked = true
	engine_running = false
	throttle = 0
	airspeed = 0
	velocity = Vector3.ZERO
	crashed.emit(reason)

func _physics_process(delta: float) -> void:
	if suspended or wrecked:return
	var pitch_input := 0.0
	var steer := 0.0
	var brake := false
	var w_pressed := false
	var s_pressed := false
	if occupied:
		if control_override:
			pitch_input = override_pitch
			steer = override_steer
			brake = override_brake
		else:
			w_pressed = Input.is_physical_key_pressed(KEY_W)
			s_pressed = Input.is_physical_key_pressed(KEY_S)
			# Auto-start engine when pressing W so players never get stuck wondering why W doesn't move.
			if w_pressed and not engine_running and fuel_available:
				engine_running = true
			var key_pitch := float(Input.is_physical_key_pressed(KEY_UP))-float(Input.is_physical_key_pressed(KEY_DOWN))
			var key_steer := float(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A))
			if not mouse_steering:
				mouse_steer = move_toward(mouse_steer, 0.0, delta * 3.0)
				mouse_pitch = move_toward(mouse_pitch, 0.0, delta * 3.0)
			pitch_input = clampf(key_pitch + mouse_pitch, -1.0, 1.0)
			steer = clampf(key_steer + mouse_steer, -1.0, 1.0)
			var space_pressed := Input.is_physical_key_pressed(KEY_SPACE)
			if not airborne and w_pressed and airspeed >= takeoff_speed * .96:
				# Smart takeoff assist: holding W at flying speed gently rotates for liftoff; Space or Up climbs faster.
				pitch_input = maxf(pitch_input, .85 if space_pressed else .55)
				brake = false
			else:
				brake = space_pressed or (not airborne and s_pressed and throttle <= .04)
			var power := float(w_pressed)-float(s_pressed)
			var rate := .72 if power >= 0.0 else .88
			throttle = clampf(throttle+power*delta*rate,0,1) if engine_running else 0.0
	if not fuel_available:engine_running = false
	if engine_running:fuel_burned.emit(lerpf(float(profile.idle_burn),float(profile.full_burn),throttle)*delta/3600.0)
	if not airborne and occupied and not is_on_floor() and ground_height.is_valid():
		if position.y>float(ground_height.call(position.x,position.z))+.65:
			airborne = true
			floor_snap_length = 0
			lifted_off.emit()
	var on_ground := not airborne
	var drag := .2+airspeed*airspeed*.0024
	if on_ground:drag += .35+(14.0 if brake else 0.0)
	var thrust := throttle*float(profile.thrust) if engine_running else 0.0
	airspeed = clampf(airspeed+(thrust-drag-sin(nose_pitch)*9.81)*delta,0,62)
	if not occupied:airspeed = move_toward(airspeed,0,8*delta)
	if on_ground:
		var ground_turn := 1.15 if not control_override else .95
		if not control_override and assist_enabled and absf(steer) < .05 and airspeed > 2.5:
			# Gentle runway centerline heading hold when rolling straight
			var east_err := wrapf(PI * .5 - heading, -PI, PI)
			var west_err := wrapf(-PI * .5 - heading, -PI, PI)
			var rwy_err := east_err if absf(east_err) < absf(west_err) else west_err
			if absf(rwy_err) < .35:
				heading = lerp_angle(heading, heading + rwy_err, 1.0 - exp(-delta * 2.5))
		heading -= steer*ground_turn*clampf(airspeed/3.5,0,1)*delta
		bank = lerpf(bank,0,1-exp(-delta*6))
		nose_pitch = lerpf(nose_pitch,pitch_input*.18 if airspeed>takeoff_speed else 0.0,1-exp(-delta*3.5))
		if occupied and pitch_input>.2 and airspeed>=takeoff_speed:
			airborne = true
			floor_snap_length = 0
			velocity.y = 2.2
			lifted_off.emit()
	else:
		if control_override:
			bank = lerpf(bank,steer*.65,1-exp(-delta*2.5))
			heading -= sin(bank)*.68*clampf(airspeed/25,.35,1.3)*delta
			nose_pitch = lerpf(nose_pitch,pitch_input*.3,1-exp(-delta*2.2))
		else:
			# ACAH (Attitude Command / Attitude Hold) + Path-Oriented Assist (Borst & Mulder, 2006)
			var effective_steer := steer
			var target_alt_pitch := 0.0
			if assist_enabled and occupied and engine_running and airspeed >= stall_speed and guide_target_provider.is_valid():
				var guide_info: Dictionary = guide_target_provider.call()
				if not guide_info.is_empty():
					var tpos: Vector3 = guide_info.get("pos", position)
					var to_target := tpos - position
					var horiz_dist := Vector2(to_target.x, to_target.z).length()
					if absf(steer) < .05 and horiz_dist > 18.0:
						var desired_hdg := atan2(to_target.x, to_target.z)
						var hdg_err := wrapf(desired_hdg - heading, -PI, PI)
						effective_steer = clampf(-hdg_err * .85, -.42, .42)
					if absf(pitch_input) < .05 and horiz_dist > 12.0:
						var alt_err := tpos.y - position.y
						target_alt_pitch = clampf(alt_err / maxf(horiz_dist * .85, 85.0), -.14, .16)
			# Terrain clearance envelope protection when not intentionally descending
			if assist_enabled and absf(pitch_input) < .05 and engine_running and airspeed >= stall_speed and throttle > .45 and ground_height.is_valid():
				var agl_now := position.y - float(ground_height.call(position.x, position.z))
				if agl_now < 20.0 and not s_pressed:
					target_alt_pitch = maxf(target_alt_pitch, clampf((22.0 - agl_now) * .012, 0.0, .18))
			var bank_rate := 5.2 if absf(effective_steer) < .05 else 3.8
			bank = lerpf(bank, effective_steer * .58, 1.0 - exp(-delta * bank_rate))
			heading -= sin(bank) * .92 * clampf(airspeed / 24.0, .45, 1.35) * delta
			# Turn Lift Compensation: prevent nose-drop during banked turns
			var turn_lift_comp := absf(sin(bank)) * .055 if (engine_running and airspeed >= stall_speed) else 0.0
			var base_trim := (.014 + target_alt_pitch) if (absf(pitch_input) < .05 and engine_running and airspeed >= stall_speed) else 0.0
			nose_pitch = lerpf(nose_pitch, pitch_input * .30 + base_trim + turn_lift_comp, 1.0 - exp(-delta * 3.2))
	var forward := Vector3(sin(heading),0,cos(heading))
	velocity.x = forward.x*airspeed*cos(nose_pitch)
	velocity.z = forward.z*airspeed*cos(nose_pitch)
	if airborne:
		var stall_sink := maxf(0,stall_speed-airspeed)*.9
		var target_vy := sin(nose_pitch)*airspeed-stall_sink
		# Gentle ground-effect flare assist for manual landings near the ground.
		if not control_override and ground_height.is_valid() and target_vy < -1.2 and throttle < .75:
			var agl := position.y - float(ground_height.call(position.x, position.z))
			if agl < 14.0:
				var cushion := 1.0 - clampf(agl / 14.0, 0.0, 1.0)
				target_vy = lerpf(target_vy, maxf(target_vy, -2.4), cushion * .65)
		velocity.y = lerpf(velocity.y,target_vy,1-exp(-delta*2.4))
		flight_seconds += delta
		distance_flown += Vector2(velocity.x,velocity.z).length()*delta
	else:velocity.y = -3.0
	rotation = Vector3(-nose_pitch,heading,bank)
	var incoming := velocity
	move_and_slide()
	for i in range(get_slide_collision_count()):
		var hit := get_slide_collision(i)
		if hit.get_normal().y<.65 and -incoming.dot(hit.get_normal())>4.5:
			fail(I18n.t(
				"장애물과 충돌했습니다. [Home] 키를 누르면 출발 비행장으로 복귀합니다.",
				"Aircraft struck an obstacle. Home returns you to the last airfield."
			))
			return
	if airborne and is_on_floor() and incoming.y<0:
		last_sink_rate = -incoming.y
		var max_sink := 6.0 if control_override else 10.5
		var max_bank := .36 if control_override else .62
		var max_pitch := .34 if control_override else .52
		if last_sink_rate>max_sink or absf(bank)>max_bank or absf(nose_pitch)>max_pitch:
			fail(I18n.t(
				"착륙 충격이 너무 컸습니다. 활주로 위에서 [S]로 감속하며 수평으로 사뿐히 내려앉으세요. ([Home] 복귀)",
				"Hard landing. Level the wings and ease the descent before touchdown."
			))
			return
		airborne = false
		floor_snap_length = .25
		nose_pitch = 0
		bank = 0
		rotation = Vector3(0,heading,0)
		touched_down.emit(last_sink_rate)
	if absf(position.x)>1060 or absf(position.z)>1060 or position.y < -20:
		fail(I18n.t(
			"계곡 운항 구역을 벗어났습니다. [Home] 키를 눌러 비행장으로 복귀하세요.",
			"Beyond the prototype valley. Home returns you to the last airfield."
		))

func _process(delta: float) -> void:
	var size_scale := 1.0
	var base_pitch := 0.70
	if aircraft_id == "skywhale":
		size_scale = 1.45
		base_pitch = 0.50
	elif aircraft_id == "albatross":
		size_scale = 1.25
		base_pitch = 0.56
	elif aircraft_id == "osprey":
		size_scale = 1.08
		base_pitch = 0.63
	if engine_running and not suspended and not wrecked:
		propeller.rotation.z += delta*(32+throttle*120)
		if not engine_sound.playing:engine_sound.play()
		engine_sound.pitch_scale = base_pitch+throttle*.6
		engine_sound.volume_db = -27+throttle*7 if occupied else -40
	elif engine_sound.playing:engine_sound.stop()
	if not occupied:return
	var forward := Vector3(sin(heading),0,cos(heading))
	var target := global_position+Vector3(0,2.2*size_scale,0)+forward*3.2
	var dist := (14.5*size_scale+airspeed*.065)*chase_zoom
	var height := (4.8*size_scale+airspeed*.025)*lerpf(.85, 1.15, (chase_zoom-.72)/.73)
	var desired := global_position-forward*dist+Vector3(0,height,0)
	if ground_height.is_valid():desired.y = maxf(desired.y,ground_height.call(desired.x,desired.z)+2.2)
	# Keep the chase camera in front of scenery instead of pulling it through a wall.
	var ray := PhysicsRayQueryParameters3D.create(target,desired,1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():desired = hit.position+hit.normal*.6
	chase.global_position = chase.global_position.lerp(desired,1-exp(-delta*7.5)) if camera_ready else desired
	chase.look_at(target)
	camera_ready = true
