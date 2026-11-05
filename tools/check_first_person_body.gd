extends SceneTree
## Render and exercise the visible third-person pilot body using the walking controller.
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func verify(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func capture(game: Node, label: String) -> void:
	if DisplayServer.get_name()!="headless":await game.save_capture(label)

func run() -> void:
	var game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	await create_timer(3.0).timeout
	var pilot = game.pilot
	var body = pilot.body_visual
	verify(body.visible and body.skeleton.get_bone_count()==14,"Third-person pilot body and full limb skeleton load")
	await capture(game,"body_walking_ui")
	# Orbit camera to a 3/4 front-side angle to inspect head, cap, jacket and boots.
	pilot.yaw = pilot.facing_yaw + PI * .78
	pilot.pitch = .16
	pilot.camera_ready = false
	pilot.update_look()
	await create_timer(.5).timeout
	await capture(game,"body_look_down")
	pilot.yaw = .52
	pilot.facing_yaw = .52
	pilot.pitch = .22
	pilot.camera_ready = false
	pilot.update_look()
	var stance: Transform3D = body.skeleton.get_bone_global_pose(body.indices["foot_L"])
	Input.action_press("pilot_forward")
	await create_timer(.31).timeout
	verify(not body.skeleton.get_bone_global_pose(body.indices["foot_L"]).is_equal_approx(stance),"Walking animates the visible feet")
	await capture(game,"body_walking")
	Input.action_press("pilot_run")
	await create_timer(.32).timeout
	await capture(game,"body_running")
	Input.action_release("pilot_forward")
	Input.action_release("pilot_run")
	await create_timer(.8).timeout
	verify(body.motion<.001,"Visible stride settles when movement stops")
	var before: Vector3 = pilot.global_position
	game.set_walk_mode(false)
	verify(not body.visible,"Photo camera hides the pilot body")
	await create_timer(.3).timeout
	await capture(game,"photo_mode_ui")
	game.set_walk_mode(true)
	verify(body.visible and pilot.global_position.distance_to(before)<.03,"Returning from Photo mode restores body at retained position")
	pilot.pitch = .22
	pilot.update_look()
	game.toggle_help()
	await create_timer(.3).timeout
	await capture(game,"walking_controls_ui")
	game.pilot.footstep.stop()
	await create_timer(.25).timeout
	print("FIRST_PERSON_BODY_CHECK ",JSON.stringify({"passed":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
