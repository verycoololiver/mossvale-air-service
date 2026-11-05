extends SceneTree
## Alternating matched camera sweeps isolate the cached sky's render cost.

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	game.set_walk_mode(false)
	game.set_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.session.hide_for_capture()
	game.hud.hide()
	var cached: Material = game.environment.sky.sky_material
	var plain := ProceduralSkyMaterial.new()
	plain.sky_top_color = Color("5787ad")
	plain.sky_horizon_color = Color("d8cbb5")
	plain.ground_horizon_color = Color("d8cbb5")
	plain.ground_bottom_color = Color("394c38").lerp(Color("5787ad"),.6)
	plain.sky_curve = .12
	plain.sun_angle_max = 12
	var results: Array = []
	for use_clouds in [true,false,true,false]:
		game.environment.sky.sky_material = cached if use_clouds else plain
		await create_timer(3.0).timeout
		var elapsed := 0.0
		var samples: Array[float] = []
		var previous_us := Time.get_ticks_usec()
		while elapsed<12.0:
			await process_frame
			var now_us := Time.get_ticks_usec()
			var delta := float(now_us-previous_us)/1000000.0
			previous_us = now_us
			elapsed += delta
			var t := elapsed
			game.camera.position = Vector3(5+sin(t*.5)*24,3.5+sin(t*.7)*2,8+cos(t*.5)*18)
			game.camera.rotation = Vector3(-.12+sin(t*.9)*.25,t*TAU/4.5,0)
			samples.append(delta)
		samples.sort()
		var result := {"sky":"clouds" if use_clouds else "plain", "mean_fps":samples.size()/elapsed,"p95_ms":samples[int(samples.size()*.95)]*1000}
		results.append(result)
		print("SKY_COMPARISON ",JSON.stringify(result))
	var output := FileAccess.open(game.preview_directory().path_join("sky_performance.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(results,"\t"))
	quit()
