extends Node
## End-to-end checks against the actual generated airfield and third-person pilot controller.
var failures: Array[String] = []
var measurements := {}
var world: Node3D

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func place(at: Vector3, yaw: float = 0.0) -> void:
	var pilot = world.pilot
	pilot.position = at
	pilot.velocity = Vector3.ZERO
	pilot.yaw = yaw
	pilot.facing_yaw = yaw
	pilot.pitch = .22
	pilot.camera_ready = false
	pilot.update_look()
	pilot.reset_physics_interpolation()
	await settle(.4)

func travel(seconds: float, run: bool = false, diagonal: bool = false) -> float:
	var start: Vector3 = world.pilot.position
	Input.action_press("pilot_forward")
	if run:Input.action_press("pilot_run")
	if diagonal:Input.action_press("pilot_right")
	await settle(seconds)
	Input.action_release("pilot_forward")
	Input.action_release("pilot_run")
	Input.action_release("pilot_right")
	var distance := Vector2(world.pilot.position.x-start.x,world.pilot.position.z-start.z).length()
	await settle(.25)
	return distance

func capture(label: String) -> void:
	if DisplayServer.get_name()!="headless":await world.save_capture(label)

func run(game: Node3D) -> void:
	world = game
	var pilot = world.pilot
	world.set_walk_mode(true)
	await settle(3.0)
	check(pilot.is_on_floor(),"Pilot spawns grounded on the apron")
	check(absf(pilot.position.y-.035)<.04,"Feet meet the visible apron surface")
	var cam_dist: float = pilot.camera.global_position.distance_to(pilot.global_position + Vector3(0, 1.46, 0))
	check(cam_dist > 1.8 and cam_dist < 4.6,"Third-person follow camera stays framed behind the pilot")
	await capture("walking_apron")
	check(pilot.body_visual.visible,"Walking renders the third-person pilot body")
	pilot.pitch = .45
	pilot.update_look()
	await settle(.2)
	await capture("walking_body")
	pilot.pitch = .22
	pilot.update_look()
	await place(Vector3(8,.2,12))
	var walked := await travel(1.0)
	measurements["walk_metres_in_one_second"] = walked
	check(walked>2.2 and walked<3.2,"Walking moves at a responsive pace")
	check(pilot.steps_played>=2,"Grounded walking produces footsteps")
	await place(Vector3(8,.2,12))
	var ran := await travel(1.0,true)
	measurements["run_metres_in_one_second"] = ran
	check(ran>walked*1.55 and ran<6.0,"Running is faster without teleporting")
	await place(Vector3(8,.2,12))
	var diagonal := await travel(1.0,false,true)
	check(absf(diagonal-walked)<.28,"Diagonal movement does not add extra speed")
	await place(Vector3(8,.2,12))
	var standing_y: float = pilot.position.y
	pilot.queue_jump()
	await settle(.23)
	check(pilot.position.y>standing_y+.3,"Jump lifts the grounded pilot")
	await settle(.9)
	check(pilot.is_on_floor() and absf(pilot.position.y-standing_y)<.035,"Jump returns to the ground")
	await place(Vector3(3.5,.2,3),PI/2)
	await travel(1.0,true)
	measurements["plane_stop_position"] = str(pilot.position)
	check(pilot.position.x>.4 and pilot.position.x<2.0,"Plane fuselage blocks crossing its centreline")
	await place(Vector3(-10,.2,-10),PI/2)
	await travel(1.0,true)
	measurements["wall_stop_position"] = str(pilot.position)
	check(pilot.position.x > -12 and pilot.position.x < -10.6,"Hangar wall blocks the walking capsule")
	await place(Vector3(-19,.2,-1.8))
	await travel(2.1)
	measurements["hangar_entry_position"] = str(pilot.position)
	check(pilot.position.z < -5 and absf(pilot.position.y-.16)<.04,"Pilot walks over the threshold into the hangar")
	await capture("walking_hangar")
	await place(Vector3(-19,.2,-14.2),PI)
	await settle(.25)
	check(pilot.camera.global_position.z > -15.35,"Third-person camera raycast stays in front of the hangar back wall")
	await place(Vector3(120,world.height_at(120,-180)+1.0,-180),-.6)
	await settle(.6)
	await travel(1.0)
	check(pilot.is_on_floor(),"Pilot stays grounded while walking on the hillside")
	await capture("walking_trail")
	world.set_walk_mode(false)
	check(world.camera.current and not pilot.camera.current,"Inspection uses the inspection camera")
	check(not pilot.body_visual.visible,"Photo mode hides the pilot body")
	world.set_walk_mode(true)
	check(pilot.camera.current and not world.camera.current,"Walking restores the third-person follow camera")
	pilot.respawn()
	await settle(.5)
	Input.action_press("pilot_forward")
	await settle(.36)
	check(absf(pilot.head.position.y-1.64)<.02,"Walking head pivot motion stays restrained")
	await capture("walking_motion")
	Input.action_press("pilot_run")
	await settle(.4)
	check(absf(pilot.head.position.y-1.64)<.025,"Running head pivot motion stays restrained")
	Input.action_release("pilot_forward")
	Input.action_release("pilot_run")
	await settle(.5)
	var stopped_steps: int = pilot.steps_played
	await settle(.6)
	check(pilot.steps_played==stopped_steps,"Footsteps stop when movement stops")
	measurements["passed"] = failures.is_empty()
	measurements["failures"] = failures
	var file := FileAccess.open(world.preview_directory().path_join("walking_check.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(measurements,"\t"))
	print("WALKING_CHECK ",JSON.stringify(measurements))
	get_tree().quit(0 if failures.is_empty() else 1)
