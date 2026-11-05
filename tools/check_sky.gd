extends SceneTree
## Visual QA: clear and rainy skies at every time, without player-save access.

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_walk_mode(false)
	game.set_process(false)
	game.capture_mode = true # Ignore human input during deterministic captures.
	game.session.hide_for_capture()
	game.hud.hide()
	game.camera.position = Vector3(8.5, 3.0, 13.5)
	game.camera.look_at(Vector3(-25.0, 11.0, -44.0))
	for wet in [false, true]:
		game.set_weather(wet)
		for time in [2, 0, 1, 3, 4]:
			game.set_time(time)
			await create_timer(3.0).timeout
			await game.save_capture("sky_%d_%s" % [time, "rain" if wet else "clear"])
	print("SKY_CAPTURES_COMPLETE")
	quit()
