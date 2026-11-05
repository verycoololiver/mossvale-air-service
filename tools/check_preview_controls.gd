extends SceneTree
## Run with Godot --headless --path game --script ../tools/check_preview_controls.gd
## Exercises real viewport mouse/key events, including keyboard focus after clicking and Korean/English UI.

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func verify(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func click(button: Button) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = true
	root.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)

func key(code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.shift_pressed = shift
	root.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)

func run() -> void:
	var game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var bounds := root.get_visible_rect()
	for button in [game.lang_button,game.time_button,game.rain_button,game.help_button]:
		verify(bounds.encloses(button.get_global_rect()),"Control must remain inside viewport: "+button.text)
	verify(not game.time_button.get_global_rect().intersects(game.rain_button.get_global_rect()),"Time and rain controls must not overlap")
	verify(game.time_index==2 and not game.rain_enabled,"Start at dry golden hour")
	verify(game.walking_mode and (game.mode_label.text=="도보 이동 · 3인칭 고정" or game.mode_label.text=="On foot · Third person"),"Normal play identifies locked third-person walking mode")
	verify(not game.walk_button.visible,"Normal play locks third-person and hides Photo mode toggle")
	for button in game.view_buttons:
		verify(not button.visible,"Fixed camera choices stay hidden while walking")
	verify(not game.status_label.visible,"Development FPS stays hidden in normal play")
	# Test language toggle (Korean <-> English)
	var initial_lang: String = game.I18n.get_lang()
	key(KEY_L)
	verify(game.I18n.get_lang() != initial_lang,"L toggles between Korean and English")
	key(KEY_L)
	verify(game.I18n.get_lang() == initial_lang,"Second L restores initial language")
	click(game.rain_button)
	verify(game.rain_enabled and game.rain.emitting,"Mouse click enables rain")
	verify(game.time_index==2,"Rain must preserve the chosen time")
	for expected in [3,4,0,1,2]:
		click(game.time_button)
		verify(game.time_index==expected,"Time button cycles through every preset and wraps")
		verify(game.rain_enabled and game.rain.emitting,"Changing time preserves rain")
		verify(game.time_button.text.contains(game.TIME_PRESETS[expected].name),"Displayed time follows actual atmosphere")
	key(KEY_T,true)
	verify(game.time_index==1,"Shift + T goes backwards with a button focused")
	key(KEY_R)
	verify(not game.rain_enabled and not game.rain.emitting and game.time_index==1,"R disables rain without changing midday")
	key(KEY_T)
	verify(game.time_index==2,"T advances time with a button focused")
	game.select_view(3)
	await process_frame
	verify(not game.walking_mode and (game.walk_button.text=="3인칭 도보 복귀" or game.walk_button.text=="Return to walking"),"Selecting a diagnostic view enters Photo mode with a return action")
	verify(not game.session.flight_overview.visible and not game.session.flight_chart.visible and not game.session.prompt.visible,"Photo mode hides the flight chart and boarding UI")
	for button in game.view_buttons:
		verify(button.visible,"Fixed camera choices appear in Photo mode")
	click(game.view_buttons[3])
	verify(game.view_index==3 and game.view_buttons[3].button_pressed,"Hangar button selects and highlights its camera")
	key(KEY_SPACE)
	verify(game.touring,"Space starts the tour even after a camera-button click")
	key(KEY_V)
	verify(game.view_index==0 and not game.touring,"V wraps cameras and stops the tour")
	click(game.help_button)
	await process_frame
	verify(game.help_panel.visible and game.help_button.button_pressed,"Controls button opens help")
	verify(game.help_title.text.begins_with("Photo mode"),"Help content follows the active Photo mode")
	verify(bounds.encloses(game.help_panel.get_global_rect()),"Help panel remains inside viewport")
	key(KEY_F1)
	verify(not game.help_panel.visible,"F1 closes help")
	key(KEY_H)
	verify(not game.hud.visible,"H hides HUD")
	key(KEY_F1)
	verify(game.hud.visible and game.help_panel.visible,"F1 restores hidden HUD and opens help")
	key(KEY_F1)
	click(game.walk_button)
	verify(game.walking_mode and game.pilot.camera.current,"Walk button restores third-person walking mode")
	verify(not game.walk_button.visible and not game.view_buttons[0].visible,"Returning to walking locks 3rd-person and hides Photo mode buttons")
	var retained_position: Vector3 = game.pilot.global_position
	key(KEY_ESCAPE)
	verify(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"Escape keeps cursor visible for the UI")
	key(KEY_C)
	verify(game.walking_mode and game.pilot.camera.current,"C stays locked in third-person walking mode")
	verify(game.walking_mode and game.pilot.global_position.is_equal_approx(retained_position),"Pilot position is retained")
	var walking_view: int = game.view_index
	key(KEY_V)
	verify(game.walking_mode and game.view_index==walking_view,"V stays locked in third-person mode")
	key(KEY_B)
	await process_frame
	await process_frame
	verify(game.session.panel.visible,"B opens the flight desk")
	verify(bounds.encloses(game.session.panel.get_global_rect()),"Flight desk remains inside viewport")
	verify(not game.session.prompt.visible,"Boarding prompt hides while the desk is open")
	verify(game.session.book_button.disabled,"Bookings require walking beside the stopped aircraft")
	key(KEY_ESCAPE)
	verify(not game.session.panel.visible,"Escape closes the flight desk")
	verify(not game.pilot.controls_blocked,"Closing the flight desk restores walking input")
	game.session.hide_for_capture()
	for overlay in game.session.overlays:
		verify(not overlay.visible,"Capture setup keeps flight overlays out of diagnostic images")
	verify(not game.session.is_processing(),"Capture setup stops flight overlays from being restored")
	if "--show-help" in OS.get_cmdline_user_args():
		key(KEY_F1)
		await create_timer(3.0).timeout
		await game.save_capture("controls_help")
	print("PREVIEW_CONTROLS ",JSON.stringify({"passed":failures.is_empty(),"failures":failures,"viewport":str(bounds.size)}))
	game.pilot.footstep.stop()
	await create_timer(.25).timeout
	quit(0 if failures.is_empty() else 1)
