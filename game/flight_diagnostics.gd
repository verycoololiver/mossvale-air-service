extends Node
## Drives the real aircraft through a complete route; no in-flight position changes.
var world: Node3D
var failures: Array[String] = []
var metrics := {}
var frame_samples: Array[float] = []
var sampling := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	world.get_viewport().push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	world.get_viewport().push_input(event,true)

func capture(label: String) -> void:
	if DisplayServer.get_name()!="headless":
		await settle(.15)
		await world.save_capture(label)

func _process(delta: float) -> void:
	if sampling:frame_samples.append(delta)

func run(game: Node3D) -> void:
	world = game
	var session = world.session
	var plane = world.aircraft
	check(session.test_mode,"Diagnostics cannot load or change the player's saved company")
	if DisplayServer.get_name()=="headless":Engine.time_scale = 5
	await settle(1.0)
	check(plane.is_on_floor() and plane.can_exit(),"Aircraft rests on its landing gear")
	check(plane.propeller.get_child_count()>=4,"Both propeller blades and tips share the spinning pivot")
	world.pilot.position = Vector3(3,.2,3)
	world.pilot.velocity = Vector3.ZERO
	await settle(.5)
	key(KEY_B)
	check(session.panel.visible,"B opens the flight desk")
	session.book_trip()
	check(session.company.active_trip.get("seats",0)==3,"Three passenger seats sell at the starter fare")
	check(session.company.money_cents==120000,"Booking does not pay before a flight")
	await capture("flight_desk")
	key(KEY_B)
	key(KEY_E)
	check(session.seated and plane.chase.current,"E boards and selects the chase camera")
	check(not world.pilot.is_physics_processing() and world.pilot.collision_layer==0,"Boarding removes walking-body physics and collision")
	session.line_up()
	await settle(.5)
	key(KEY_X)
	check(plane.engine_running,"X starts the engine")
	plane.throttle = .5
	key(KEY_B)
	var paused_at: Vector3 = plane.position
	var paused_fuel: float = session.company.fuel_litres
	await settle(.7)
	check(plane.position.distance_to(paused_at)<.001 and session.company.fuel_litres==paused_fuel,"The flight desk pauses motion and fuel consumption")
	key(KEY_B)
	plane.control_override = true
	plane.throttle = 1
	plane.override_pitch = .85
	var sim_time := 0.0
	while sim_time<18 and not plane.airborne and not plane.wrecked:
		await get_tree().physics_frame
		sim_time += Engine.time_scale/Engine.physics_ticks_per_second
	metrics["takeoff_position"] = str(plane.position)
	metrics["takeoff_speed_kmh"] = plane.airspeed*3.6
	check(plane.airborne,"The aircraft takes off under its own power")
	check(plane.airspeed>=19.5,"Takeoff requires flying speed")
	key(KEY_E)
	check(session.seated,"Exit is rejected while airborne")
	check(not world.pilot.body_visual.visible,"The on-foot body stays hidden during flight")
	await capture("flight_takeoff")
	var stage := 0
	var captures := {}
	sampling = DisplayServer.get_name()!="headless"
	sim_time = 0
	var max_altitude := 0.0
	while sim_time<210 and not plane.wrecked:
		await get_tree().physics_frame
		var delta := Engine.time_scale/Engine.physics_ticks_per_second
		sim_time += delta
		max_altitude = maxf(max_altitude,plane.position.y)
		if not plane.airborne and plane.flight_seconds>8:
			plane.override_pitch = 0
			plane.override_steer = 0
			plane.override_brake = true
			plane.throttle = 0
			if plane.engine_running:key(KEY_X)
			if plane.airspeed<.1:break
			continue
		var target := Vector3(400,105,-340) if stage==0 else Vector3(255,80,-640)
		if stage<2 and Vector2(plane.position.x-target.x,plane.position.z-target.z).length()<65:
			stage += 1
			print("FLIGHT_STAGE ",stage," at ",plane.position)
		if stage==2:target = Vector3(-400,24+maxf(0,(plane.position.x+50)*.12),-640)
		var offset: Vector3 = target-plane.position
		var desired_heading := atan2(offset.x,offset.z)
		var heading_error := wrapf(desired_heading-plane.heading,-PI,PI)
		plane.override_steer = clampf(-heading_error*2.4,-1,1)
		var target_speed := 27.0 if stage==2 else 33.0
		plane.throttle = clampf(.45+(target_speed-plane.airspeed)*.12,0,1)
		var vertical_target := clampf((target.y-plane.position.y)*.55,-3.3,7.0)
		plane.override_pitch = clampf(asin(clampf(vertical_target/maxf(plane.airspeed,20),-.29,.29))/.3,-1,1)
		if sim_time>17 and not captures.has("cruise"):
			captures["cruise"] = true
			await capture("flight_valley")
		if stage==2 and not captures.has("approach"):
			captures["approach"] = true
			await capture("flight_approach")
	sampling = false
	metrics["route_seconds"] = sim_time
	metrics["max_altitude_m"] = max_altitude
	metrics["flight_distance_m"] = plane.distance_flown
	metrics["landing_position"] = str(plane.position)
	metrics["landing_sink_mps"] = plane.last_sink_rate
	metrics["fuel_used_litres"] = 40.0-session.company.fuel_litres
	metrics["wrecked"] = plane.wrecked
	check(not plane.wrecked,"A controlled route does not trigger recovery")
	check(not plane.airborne and plane.can_exit(),"The aircraft lands, stops and shuts down")
	await settle(3)
	check(session.company.current_airfield=="birch_hollow","Validated arrival updates the company's airfield")
	check(session.company.money_cents==133500,"Delivering three passengers credits exactly $135")
	check(session.company.completed_trips==1,"One completed flight is recorded")
	check(session.company.fuel_litres<39.9 and session.company.fuel_litres>35,"Actual engine running consumes fuel")
	await settle(3)
	check(session.company.money_cents==133500,"Remaining parked cannot pay twice")
	await capture("flight_arrival")
	key(KEY_E)
	check(not session.seated and world.pilot.camera.current,"E exits to first person at the destination")
	check(world.pilot.body_visual.visible,"Exiting the aircraft restores the visible first-person body")
	await settle(.5)
	check(world.pilot.is_on_floor(),"The exit places the walking capsule safely on the destination surface")
	key(KEY_B)
	await capture("flight_return_booking")
	session.book_trip()
	check(session.company.active_trip.get("destination","")=="mossvale","A return trip can be booked after arrival")
	key(KEY_B)
	key(KEY_E)
	key(KEY_HOME)
	check(session.company.active_trip.is_empty(),"Recovery cancels the unfinished booking")
	check(session.company.current_airfield=="birch_hollow" and plane.position.z< -500,"Recovery uses the last arrived airfield")
	check(session.company.money_cents==133500,"Recovery cannot grant fares")
	# Separate failure fixtures after the uninterrupted passenger route.
	# Empty fuel must stop the engine and turn low airspeed into a descent.
	session.company.fuel_litres = 0
	plane.fuel_available = false
	plane.reset_at(Vector3(-220,120,-640),PI/2)
	plane.airborne = true
	plane.airspeed = 15
	plane.override_brake = false
	plane.override_pitch = 0
	plane.override_steer = 0
	check(not plane.toggle_engine(),"An empty tank cannot start the engine")
	await settle(2)
	check(plane.position.y<118 and not plane.engine_running,"A slow unpowered aircraft loses height")
	session.recover()
	check(session.company.fuel_litres==0,"Recovery does not conjure replacement fuel")
	await settle(.3)
	session.refuel()
	check(session.company.fuel_litres==10 and session.company.money_cents==131300,"A recovered aircraft can buy fuel at the destination")
	# A steep arrival and a ground obstacle must both require recovery.
	plane.reset_at(Vector3(-220,29,-640),PI/2)
	plane.airborne = true
	plane.airspeed = 30
	plane.velocity.y = -12
	plane.override_pitch = -1
	await settle(1)
	check(plane.wrecked,"A hard touchdown is rejected instead of paying fares")
	session.recover()
	plane.reset_at(Vector3(-8,.09,-10),-PI/2)
	plane.override_pitch = 0
	plane.airspeed = 12
	await settle(1)
	check(plane.wrecked,"Taxiing into a hangar wall triggers recovery")
	check(session.company.money_cents==131300,"Failed flights cannot generate revenue")
	if not frame_samples.is_empty():
		var total := 0.0
		for frame in frame_samples:total += frame
		frame_samples.sort()
		metrics["mean_fps"] = frame_samples.size()/total
		metrics["p95_frame_ms"] = frame_samples[int(frame_samples.size()*.95)]*1000
		metrics["sample_count"] = frame_samples.size()
	metrics["passed"] = failures.is_empty()
	metrics["failures"] = failures
	var file := FileAccess.open(world.preview_directory().path_join("flight_check.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics,"\t"))
	print("FLIGHT_CHECK ",JSON.stringify(metrics))
	Engine.time_scale = 1
	get_tree().quit(0 if failures.is_empty() else 1)
