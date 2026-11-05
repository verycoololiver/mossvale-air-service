extends Node
## Owns player/aircraft transitions, step-by-step guidance, 3D navigation and arrival payouts.
const Airfields = preload("res://airfields.gd")
const Company = preload("res://company_state.gd")
const Catalog = preload("res://aircraft_catalog.gd")
const I18n = preload("res://i18n.gd")
const NavGuide = preload("res://navigation_guide.gd")
var company := Company.new()
var world: Node3D
var aircraft: CharacterBody3D
var nav_guide: Node3D
var seated := false
var test_mode := false
var persistence_blocked := false
var startup_message := ""
var overlays: Array[Control] = []
var departed := false
var landed := false
var arrival_error_latched := false
var departure_field := ""
var parked_seconds := 0.0
var auto_stop_seconds := 0.0
var save_seconds := 0.0
var notice_seconds := 0.0
var fare_cents := 4500
var panel: PanelContainer
var desk_button: Button
var fleet_hud_button: Button
var reset_hud_button: Button
var lineup_hud_button: Button
var flight_overview: Control
var flight_chart: Control
var route_label: Label
var account_label: Label
var mission_guide_label: Label
var instruments: Label
var prompt: Button
var notice: Label
var desk_title: Label
var desk_summary: Label
var quote_label: Label
var destination_picker: OptionButton
var target_destination := ""
var fare_picker: OptionButton
var book_button: Button
var cancel_button: Button
var fuel_button: Button
var full_fuel_button: Button
var lineup_button: Button
var lineup_hint_label: Label
var desk_pause: Label
var fleet_panel: PanelContainer
var fleet_button: Button
var fleet_opened_from_desk := false
var close_desk_button: Button

func configure(game: Node3D, plane: CharacterBody3D) -> void:
	world = game
	aircraft = plane
	var arguments := OS.get_cmdline_args()+OS.get_cmdline_user_args()
	for arg in arguments:
		if arg in ["--no-save","--capture","--stress"] or "-check" in arg or "check_" in arg:test_mode = true
	if not test_mode:
		var loaded: Dictionary = company.load_save()
		if not loaded.ok:
			persistence_blocked = true
			startup_message = I18n.t(
				"저장 파일을 불러올 수 없어 임시 모드로 실행합니다. (기존 파일은 보존됨)",
				"Save could not be loaded. Playing without saves; the original files are preserved."
			)
			print("COMPANY_LOAD ",loaded.message)
		elif loaded.get("used_backup",false):
			startup_message = I18n.t("백업 저장 파일에서 회사 데이터를 복구했습니다.", "Company recovered from the backup save.")
		elif loaded.get("unfinished_trip_canceled",false):
			startup_message = I18n.t("마지막 도착 비행장으로 복귀했습니다. 미완료 예약은 취소되었습니다.", "Returned to the last airfield. The unfinished flight was cancelled.")
	if aircraft.aircraft_id!=company.active_aircraft_id:aircraft.configure_aircraft(company.active_aircraft_id)
	aircraft.fuel_available = company.fuel_litres>0
	aircraft.fuel_burned.connect(burn_fuel)
	aircraft.lifted_off.connect(on_liftoff)
	aircraft.touched_down.connect(on_touchdown)
	aircraft.crashed.connect(on_crash)
	if company.current_airfield!="mossvale":
		var field: Dictionary = Airfields.DATA[company.current_airfield]
		aircraft.reset_at(field.spawn,field.yaw)
		world.pilot.position = field.spawn+Vector3(3,.2,0)
	if world.has_method("update_parked_fleet"):
		world.call("update_parked_fleet", company.active_aircraft_id)
	var hud_root := world.hud.get_child(0) as Control
	create_ui(hud_root)
	nav_guide = Node3D.new()
	nav_guide.set_script(NavGuide)
	world.add_child(nav_guide)
	nav_guide.configure(self, hud_root)
	aircraft.guide_target_provider = nav_guide.get_active_target
	refresh_desk()
	if not startup_message.is_empty():say(startup_message)
	get_tree().auto_accept_quit = false

func airfield_display_name(id: String) -> String:
	if id == "mossvale":
		return I18n.t("모스베일 (Mossvale)", "Mossvale")
	if id == "birch_hollow":
		return I18n.t("버치 할로우 (Birch Hollow)", "Birch Hollow")
	if id == "pine_ridge":
		return I18n.t("파인 리지 고원 (Pine Ridge)", "Pine Ridge")
	if id == "mirror_lake":
		return I18n.t("미러 레이크 (Mirror Lake)", "Mirror Lake")
	var data: Dictionary = Airfields.DATA.get(id, {})
	return str(data.get("name", id.capitalize()))

func selected_destination(origin: String) -> String:
	if not company.active_trip.is_empty():
		return str(company.active_trip.get("destination", Airfields.other(origin)))
	if test_mode:
		return Airfields.other(origin)
	if target_destination != "" and target_destination != origin and Airfields.DATA.has(target_destination):
		return target_destination
	return Airfields.next_in_circuit(origin)

func dollars(cents: int) -> String:
	return "$%.2f" % (cents/100.0)

func create_ui(root: Control) -> void:
	var backing := PanelContainer.new()
	flight_overview = backing
	root.add_child(backing)
	overlays.append(backing)
	backing.position = Vector2(30,90)
	backing.add_theme_stylebox_override("panel",world.button_style(Color(.025,.048,.052,.91)))
	var card := VBoxContainer.new()
	backing.add_child(card)
	card.custom_minimum_size.x = 340
	card.add_theme_constant_override("separation",7)
	var top_actions := HBoxContainer.new()
	top_actions.add_theme_constant_override("separation", 5)
	card.add_child(top_actions)
	desk_button = world.ui_button("", 126)
	desk_button.pressed.connect(toggle_desk)
	top_actions.add_child(desk_button)
	fleet_hud_button = world.ui_button("", 120)
	fleet_hud_button.pressed.connect(open_fleet_direct)
	top_actions.add_child(fleet_hud_button)
	lineup_hud_button = world.ui_button("", 116)
	lineup_hud_button.pressed.connect(quick_start_or_lineup)
	top_actions.add_child(lineup_hud_button)
	reset_hud_button = world.ui_button("", 108)
	reset_hud_button.pressed.connect(recover)
	top_actions.add_child(reset_hud_button)
	route_label = world.ui_label("",14,Color("f0e5cc"))
	card.add_child(route_label)
	account_label = world.ui_label("",12,Color("c2d2c5"))
	card.add_child(account_label)
	mission_guide_label = world.ui_label("",13,Color("ffd88a"))
	mission_guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_guide_label.custom_minimum_size.x = 330
	mission_guide_label.add_theme_constant_override("line_spacing",4)
	card.add_child(mission_guide_label)
	instruments = world.ui_label("",15,Color("f4e8c9"))
	instruments.add_theme_constant_override("line_spacing",6)
	card.add_child(instruments)
	var chart := Control.new()
	flight_chart = chart
	chart.set_script(load("res://valley_map.gd"))
	chart.session = self
	root.add_child(chart)
	overlays.append(chart)
	chart.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	chart.offset_left = -268
	chart.offset_right = -28
	chart.offset_top = 94
	chart.offset_bottom = 328
	chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt = world.ui_button("",420)
	root.add_child(prompt)
	overlays.append(prompt)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left = -250
	prompt.offset_right = 250
	prompt.offset_top = -138
	prompt.offset_bottom = -96
	prompt.pressed.connect(_on_prompt_pressed)
	notice = world.ui_label("",15,Color("ffe1a3"))
	root.add_child(notice)
	overlays.append(notice)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	notice.offset_left = -480
	notice.offset_right = 480
	notice.offset_top = -246
	notice.offset_bottom = -204
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_color_override("font_outline_color", Color(0.015, 0.035, 0.04, 0.65))
	notice.add_theme_constant_override("outline_size", 2)
	notice.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	notice.add_theme_constant_override("shadow_offset_y", 1)
	panel = PanelContainer.new()
	root.add_child(panel)
	overlays.append(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -290
	panel.offset_right = 290
	panel.offset_top = -268
	panel.offset_bottom = 268
	panel.add_theme_stylebox_override("panel",world.button_style(Color(.025,.048,.052,.98)))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",9)
	panel.add_child(content)
	desk_title = world.ui_label("Flight desk",22,Color("f0e5cc"))
	content.add_child(desk_title)
	desk_summary = world.ui_label("",14,Color("c2d2c5"))
	content.add_child(desk_summary)
	destination_picker = OptionButton.new()
	destination_picker.custom_minimum_size.y = 36
	_populate_destinations()
	destination_picker.item_selected.connect(func(index: int):
		target_destination = str(destination_picker.get_item_metadata(index))
		if is_instance_valid(nav_guide) and company.active_trip.is_empty():
			nav_guide.reset_route(target_destination)
		refresh_desk())
	content.add_child(destination_picker)
	fare_picker = OptionButton.new()
	fare_picker.custom_minimum_size.y = 36
	_populate_fares()
	fare_picker.item_selected.connect(func(index: int):
		fare_cents = fare_picker.get_item_id(index)
		refresh_desk())
	content.add_child(fare_picker)
	quote_label = world.ui_label("",13,Color("c2d2c5"))
	content.add_child(quote_label)
	book_button = world.ui_button("",200)
	book_button.pressed.connect(book_trip)
	content.add_child(book_button)
	var services := HBoxContainer.new()
	services.add_theme_constant_override("separation",8)
	content.add_child(services)
	fuel_button = world.ui_button("",182)
	fuel_button.pressed.connect(refuel)
	services.add_child(fuel_button)
	full_fuel_button = world.ui_button("",182)
	full_fuel_button.pressed.connect(refuel_full)
	services.add_child(full_fuel_button)
	cancel_button = world.ui_button("",164)
	cancel_button.pressed.connect(func():
		company.cancel_trip()
		persist()
		refresh_desk()
		say(I18n.t("승객 예약이 취소되었습니다. (수수료 없음)", "Booking cancelled. No fare charged or earned.")))
	services.add_child(cancel_button)
	lineup_button = world.ui_button("",200)
	lineup_button.pressed.connect(line_up)
	content.add_child(lineup_button)
	lineup_hint_label = world.ui_label("",12,Color("91a99e"))
	lineup_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(lineup_hint_label)
	desk_pause = world.ui_label("",12,Color("e6c791"))
	desk_pause.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(desk_pause)
	fleet_button = world.ui_button("",200)
	fleet_button.pressed.connect(toggle_fleet)
	content.add_child(fleet_button)
	close_desk_button = world.ui_button("",200)
	close_desk_button.pressed.connect(toggle_desk)
	content.add_child(close_desk_button)
	panel.hide()
	fleet_panel = PanelContainer.new()
	fleet_panel.set_script(load("res://fleet_panel.gd"))
	root.add_child(fleet_panel)
	overlays.append(fleet_panel)
	fleet_panel.configure(world,self)
	fleet_panel.hide()

func _populate_destinations() -> void:
	if destination_picker == null:
		return
	var origin := company.current_airfield
	var desired := selected_destination(origin)
	destination_picker.clear()
	var idx := 0
	for id: String in Airfields.ORDER:
		if id == origin:
			continue
		var dist_km := Vector2(Airfields.DATA[id].centre.x - Airfields.DATA[origin].centre.x, Airfields.DATA[id].centre.z - Airfields.DATA[origin].centre.z).length() / 1000.0
		var label := I18n.t("목적지 공항: %s (%.1f km)" % [airfield_display_name(id), dist_km], "Destination: %s (%.1f km)" % [airfield_display_name(id), dist_km])
		destination_picker.add_item(label, idx)
		destination_picker.set_item_metadata(idx, id)
		if id == desired:
			destination_picker.select(idx)
			target_destination = id
		idx += 1

func _populate_fares() -> void:
	if fare_picker == null:return
	var selected_id := fare_cents
	fare_picker.clear()
	var items := [
		[4500, I18n.t("승객 1인당 $45.00 (만석 보장 · 추천)", "$45.00 per passenger")],
		[7500, I18n.t("승객 1인당 $75.00 (중간 수요)", "$75.00 per passenger")],
		[11000, I18n.t("승객 1인당 $110.00 (소수 프리미엄)", "$110.00 per passenger")]
	]
	for i in range(items.size()):
		fare_picker.add_item(items[i][1], items[i][0])
		if items[i][0] == selected_id:
			fare_picker.select(i)

func refresh_language() -> void:
	_populate_destinations()
	_populate_fares()
	refresh_desk()
	if is_instance_valid(fleet_panel):
		fleet_panel.refresh()

func aircraft_name() -> String:
	return Catalog.DATA[company.active_aircraft_id].name

func is_menu_open() -> bool:
	return panel.visible or (is_instance_valid(fleet_panel) and fleet_panel.visible)

func fleet_unavailable_reason() -> String:
	if persistence_blocked:return I18n.t("저장 파일 복구가 필요해 기체 변경을 할 수 없습니다.", "Fleet changes are unavailable while your save needs recovery.")
	if aircraft.airborne:return I18n.t("비행 중에는 기체를 변경할 수 없습니다. 먼저 착륙하세요.", "Land first before buying or changing aircraft.")
	if not company.active_trip.is_empty():return I18n.t("진행 중인 승객 예약을 먼저 완료하거나 취소하세요.", "Finish or cancel your passenger booking first.")
	if test_mode and (seated or service_field()!=company.current_airfield):
		return I18n.t("시동이 꺼진 비행기 바로 옆으로 걸어가세요.", "Walk beside your parked aircraft with its engine off.")
	return ""

func open_fleet_direct() -> void:
	if is_instance_valid(fleet_panel) and fleet_panel.visible:
		fleet_panel.hide()
		panel.hide()
		fleet_opened_from_desk = false
		update_blocks()
		return
	fleet_opened_from_desk = false
	panel.hide()
	fleet_panel.show()
	world.help_panel.hide()
	world.help_button.set_pressed_no_signal(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	fleet_panel.refresh()
	update_blocks()

func toggle_fleet() -> void:
	if not fleet_panel.visible:
		fleet_opened_from_desk = panel.visible
		fleet_panel.show()
		panel.hide()
		world.help_panel.hide()
		world.help_button.set_pressed_no_signal(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		fleet_panel.refresh()
	else:
		fleet_panel.hide()
		panel.visible = fleet_opened_from_desk
		fleet_opened_from_desk = false
		refresh_desk()
	update_blocks()

func buy_aircraft(id: String) -> void:
	var reason := fleet_unavailable_reason()
	if not reason.is_empty():
		say(reason)
		return
	var result: Dictionary = company.purchase_aircraft(id)
	if result.ok:
		persist()
		if not test_mode:
			select_aircraft(id)
			return
		say(I18n.t("%s 기체가 인도되었습니다! [이 기체로 전환]을 눌러 탑승하세요." % Catalog.DATA[id].name, "%s delivered. Choose Fly this aircraft when you are ready." % Catalog.DATA[id].name))
	else:say(result.message)
	fleet_panel.refresh()
	refresh_desk()

func select_aircraft(id: String) -> void:
	var reason := fleet_unavailable_reason()
	if not reason.is_empty():
		say(reason)
		return
	if seated:
		aircraft.occupied = false
		aircraft.engine_running = false
		aircraft.throttle = 0.0
		seated = false
		world.pilot.set_physics_process(true)
		world.pilot.collision_layer = 2
		world.pilot.collision_mask = 5
		world.pilot.camera.make_current()
		world.set_walk_mode(true)
	else:
		aircraft.engine_running = false
		aircraft.throttle = 0.0
	var previous: String = company.active_aircraft_id
	var result: Dictionary = company.select_aircraft(id)
	if not result.ok:
		say(result.message)
		fleet_panel.refresh()
		return
	if not aircraft.configure_aircraft(id):
		company.select_aircraft(previous)
		say(I18n.t("해당 기체를 불러올 수 없습니다.", "Could not load that aircraft. Your current plane is unchanged."))
		return
	var field: Dictionary = Airfields.DATA[company.current_airfield]
	if not test_mode and company.fuel_litres < 10.0 and company.money_cents < 2200:
		company.fuel_litres = 15.0
	aircraft.fuel_available = company.fuel_litres > 0
	aircraft.reset_at(field.spawn,field.yaw)
	aircraft.fuel_available = company.fuel_litres>0
	if world.has_method("update_parked_fleet"):
		world.call("update_parked_fleet", company.active_aircraft_id)
	world.pilot.position = field.spawn+Basis(Vector3.UP,field.yaw)*Vector3(3.3,.2,.5)
	world.pilot.velocity = Vector3.ZERO
	world.pilot.reset_physics_interpolation()
	departed = false
	landed = false
	parked_seconds = 0
	auto_stop_seconds = 0
	arrival_error_latched = false
	fleet_panel.hide()
	panel.hide()
	update_blocks()
	refresh_desk()
	world.refresh_ui()
	persist()
	say(I18n.t("%s (%d인승 · %.0fL 탱크) 기체가 주기장에 배치되었습니다!" % [aircraft_name(), company.get_passenger_capacity(), company.get_fuel_capacity()], "%s is ready on the apron. Its stored fuel has been retained." % aircraft_name()))

func say(message: String) -> void:
	notice.text = message
	notice_seconds = 8

func near_aircraft() -> bool:
	return seated or world.pilot.global_position.distance_to(aircraft.global_position)<5.8

func service_field() -> String:
	if not near_aircraft() or not aircraft.can_exit():return ""
	return Airfields.field_at(aircraft.global_position)

func pilot_rank_title() -> String:
	var trips := company.completed_trips
	if trips >= 6:
		return I18n.t("★ 모스베일 에이스 기장", "★ Mossvale Chief Ace")
	if trips >= 3:
		return I18n.t("★ 수석 마운틴 캡틴", "★ Senior Mountain Captain")
	if trips >= 1:
		return I18n.t("★ 밸리 커뮤터 파일럿", "★ Valley Commuter Pilot")
	return I18n.t("수습 파일럿", "Trainee Pilot")

func refresh_desk() -> void:
	var origin := company.current_airfield
	_populate_destinations()
	var destination := selected_destination(origin)
	var dest_name := airfield_display_name(destination)
	var origin_name := airfield_display_name(origin)
	var seats: int = company.quote_seats(fare_cents)
	var parked := service_field()==origin
	if destination_picker:
		destination_picker.disabled = not company.active_trip.is_empty()
	if desk_button:
		desk_button.text = I18n.t("운항 데스크 · B", "Flight desk · B")
	if fleet_hud_button:
		fleet_hud_button.text = I18n.t("◆ 격납고 (4기종)", "◆ Fleet (4)")
	if lineup_hud_button:
		lineup_hud_button.text = I18n.t("▶ 활주로 출발 · F", "▶ Line Up · F")
	if reset_hud_button:
		reset_hud_button.text = I18n.t("위치 리셋 · Backspace", "Reset · Backspace")
	desk_title.text = I18n.t("%s  /  운항 데스크" % origin_name, Airfields.DATA[origin].name+"  /  Flight desk")
	desk_summary.text = I18n.t(
		"%s  ·  %s  ·  보유 자금 %s\n연료 %.1f / %d L  ·  완료한 비행 %d회" % [aircraft_name(),pilot_rank_title(),dollars(company.money_cents),company.fuel_litres,company.get_fuel_capacity(),company.completed_trips],
		"%s  ·  %s  ·  %s available\n%.1f / %d L fuel  ·  %d completed trips" % [aircraft_name(),pilot_rank_title(),dollars(company.money_cents),company.fuel_litres,company.get_fuel_capacity(),company.completed_trips]
	)
	quote_label.text = I18n.t(
		"승객 좌석 %d / %d석 탑승 예정  ·  도착 시 운임 수익 %s" % [seats,company.get_passenger_capacity(),dollars(seats*fare_cents)],
		"%d of %d passenger seats filled  ·  %s trip revenue" % [seats,company.get_passenger_capacity(),dollars(seats*fare_cents)]
	)
	book_button.text = I18n.t("%s행 승객 좌석 판매하기" % dest_name, "Sell seats for "+Airfields.DATA[destination].name)
	book_button.disabled = not parked or not company.active_trip.is_empty()
	fare_picker.disabled = not company.active_trip.is_empty()
	if not company.active_trip.is_empty():
		var trip: Dictionary = company.active_trip
		var trip_dest_name := airfield_display_name(str(trip.destination))
		quote_label.text = I18n.t(
			"승객 %d명 예약 완료  ·  착륙 정차 시 %s 지급" % [trip.seats,dollars(trip.payout_cents)],
			"%d passengers booked  ·  %s on arrival" % [trip.seats,dollars(trip.payout_cents)]
		)
		book_button.text = I18n.t("%s행 예약 완료" % trip_dest_name, "Booked for "+Airfields.DATA[trip.destination].name)
	fuel_button.text = I18n.t("연료 +10 L ($22)", "Add 10 L ($22)")
	if full_fuel_button:
		var missing_l: float = maxf(0.0, company.get_fuel_capacity() - company.fuel_litres)
		var full_cost_cents: int = ceili(missing_l * float(Company.FUEL_PRICE_CENTS))
		if missing_l <= 0.05:
			full_fuel_button.text = I18n.t("연료 가득 참", "Tank Full")
			full_fuel_button.disabled = true
		else:
			full_fuel_button.text = I18n.t("연료 가득 (%.0fL·%s)" % [missing_l, dollars(full_cost_cents)], "Fill +%.0fL (%s)" % [missing_l, dollars(full_cost_cents)])
			full_fuel_button.disabled = not parked or company.money_cents < 220
	cancel_button.text = I18n.t("예약 취소", "Cancel booking")
	cancel_button.disabled = company.active_trip.is_empty() or aircraft.airborne
	fuel_button.disabled = not parked or company.fuel_litres>company.get_fuel_capacity()-10.0+.000001 or company.money_cents<2200
	lineup_button.text = I18n.t("탑승 및 활주로 출발선 즉시 정렬 (추천 · F)", "Practice shortcut  ·  line up on runway")
	lineup_button.disabled = test_mode and not parked
	if lineup_hint_label:
		lineup_hint_label.text = I18n.t(
			"어디에 있든 활주로 출발선으로 비행기를 바로 옮겨 이륙 준비를 마칩니다.\n언제든 [F] 키를 누르거나 [Backspace] 리셋 버튼을 눌러 복귀할 수 있습니다.",
			"Moves your plane to the runway from anywhere.\nPress F for runway lineup or Backspace / Home to reset at the apron."
		)
	if fleet_button:
		fleet_button.text = I18n.t("항공기 격납고  ·  4종 기체 구매 / 교체 (3석~15석)", "Your fleet  ·  Buy / change aircraft (3–15 seats)")
	if close_desk_button:
		close_desk_button.text = I18n.t("데스크 닫기  ·  B / Esc", "Back to the airfield  ·  B / Esc")
	desk_pause.text = I18n.t("데스크가 열려 있는 동안 비행이 일시정지됩니다.", "Flight paused while this desk is open.") if seated else I18n.t("비행기 바로 옆(5m 이내)으로 걸어가면 좌석 예약과 주유가 활성화됩니다.", "Walk beside the aircraft to book seats or buy fuel.")
	if not parked and seated:
		desk_pause.text = I18n.t("비행 일시정지 중. 주유나 예약을 하려면 착륙 후 정차하세요.", "Flight paused. Land, stop and switch the engine off for service.")

func toggle_desk() -> void:
	if is_instance_valid(fleet_panel) and fleet_panel.visible:
		fleet_panel.hide()
		panel.hide()
		update_blocks()
		return
	panel.visible = not panel.visible
	if panel.visible:
		world.help_panel.hide()
		world.help_button.set_pressed_no_signal(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		refresh_desk()
	update_blocks()

func update_blocks() -> void:
	world.pilot.controls_blocked = is_menu_open() or world.help_panel.visible
	aircraft.suspended = seated and (is_menu_open() or world.help_panel.visible)

func book_trip() -> void:
	var field := service_field()
	if field=="" or field!=company.current_airfield:return
	var dest := selected_destination(field)
	var result: Dictionary = company.book_trip(field,dest,fare_cents)
	if result.ok:
		departed = false
		landed = false
		arrival_error_latched = false
		if is_instance_valid(nav_guide):
			nav_guide.reset_route(dest)
		persist()
		say(I18n.t(
			"승객 예약 완료! [E]로 탑승하거나 [탑승 및 활주로 출발선 즉시 정렬]을 누르세요.",
			"Seats sold. Board with E, then hold W to start and take off."
		))
	else:say(result.message)
	refresh_desk()

func refuel() -> void:
	if service_field()!=company.current_airfield:return
	var result: Dictionary = company.refuel(10.0)
	if result.ok:
		aircraft.fuel_available = true
		persist()
		say(I18n.t("연료 10 L를 $22에 주유했습니다.", "Added 10 litres of fuel for $22."))
	else:say(result.message)
	refresh_desk()

func refuel_full() -> void:
	if service_field()!=company.current_airfield:return
	var missing: float = maxf(0.0, company.get_fuel_capacity() - company.fuel_litres)
	if missing <= 0.05:
		return
	var max_affordable: float = floorf(float(company.money_cents) / float(Company.FUEL_PRICE_CENTS))
	var fill_amount: float = minf(missing, max_affordable)
	if fill_amount <= 0.05:
		say(I18n.t("주유할 자금이 부족합니다.", "Insufficient funds for fuel."))
		return
	var result: Dictionary = company.refuel(fill_amount)
	if result.ok:
		aircraft.fuel_available = true
		persist()
		say(I18n.t("연료 %.1f L를 주유해 탱크를 채웠습니다!" % fill_amount, "Added %.1f litres of fuel." % fill_amount))
	else:
		say(result.message)
	refresh_desk()

func quick_start_or_lineup() -> void:
	world.pilot.auto_walk_active = false
	var field_now: String = company.current_airfield
	var fdata: Dictionary = Airfields.DATA[field_now]
	if not test_mode:
		aircraft.reset_at(fdata.spawn, fdata.yaw)
		if not seated:
			world.pilot.global_position = nav_guide.get_boarding_spot() if is_instance_valid(nav_guide) else (aircraft.global_position + Vector3(2.4, 0.0, 0.2))
		if company.fuel_litres < 15.0:
			if company.money_cents >= 2200:
				company.refuel(minf(10.0, company.get_fuel_capacity() - company.fuel_litres))
			elif company.fuel_litres < 10.0:
				company.fuel_litres = 15.0
			aircraft.fuel_available = company.fuel_litres > 0
		if company.active_trip.is_empty():
			company.book_trip(field_now, selected_destination(field_now), fare_cents)
	elif not seated:
		aircraft.reset_at(fdata.spawn, fdata.yaw)
		world.pilot.global_position = nav_guide.get_boarding_spot() if is_instance_valid(nav_guide) else (aircraft.global_position + Vector3(2.4, 0.0, 0.2))
		if company.active_trip.is_empty():
			book_trip()
	line_up()

func line_up() -> void:
	var field := service_field()
	if field == "":
		if test_mode:
			return
		var phys_field := Airfields.field_at(aircraft.global_position)
		field = phys_field if phys_field != "" else company.current_airfield
	if not seated:
		_enter_aircraft()
	var data: Dictionary = Airfields.DATA[field]
	aircraft.reset_at(data.lineup,PI/2)
	if is_instance_valid(nav_guide):
		nav_guide.reset_route(company.active_trip.get("destination", selected_destination(field)))
	departed = false
	landed = false
	panel.hide()
	if is_instance_valid(fleet_panel):
		fleet_panel.hide()
	update_blocks()
	refresh_desk()
	world.refresh_ui()
	say(I18n.t(
		"활주로 정렬 완료! [W] 키를 길게 누르면 시동이 걸리고 이륙합니다. ([A/D] 좌우 조향 · [↑/↓] 기수 상하)",
		"Lined up eastbound. Hold W to start engine and accelerate; press ↑ or Space above %d km/h." % ceili(aircraft.takeoff_speed*3.6)
	))

func _enter_aircraft() -> void:
	var from_cam_pos: Vector3 = world.pilot.camera.global_position
	seated = true
	aircraft.occupied = true
	world.set_walk_mode(false)
	aircraft.transition_from_camera(from_cam_pos)
	world.pilot.set_physics_process(false)
	world.pilot.collision_layer = 0
	world.pilot.collision_mask = 0
	aircraft.chase.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.refresh_ui()

func _on_prompt_pressed() -> void:
	if aircraft.wrecked or (seated and not aircraft.can_exit()):
		recover()
		return
	interact()

func interact() -> void:
	if is_menu_open() or world.help_panel.visible:return
	if aircraft.wrecked:
		recover()
		return
	if seated:
		if not aircraft.can_exit() and not aircraft.airborne and aircraft.is_on_floor() and aircraft.airspeed < .8:
			# Allow convenient E exit when stopped on the ground by shutting off the engine automatically.
			aircraft.engine_running = false
			aircraft.throttle = 0.0
		if not aircraft.can_exit():
			say(I18n.t(
				"착륙 후 완전히 정차해야 내릴 수 있습니다. ([S] 감속 · [Space] 브레이크)",
				"Stop completely and press X to shut down before leaving the aircraft."
			))
			return
		var point := exit_position()
		if not point.is_finite():
			say(I18n.t(
				"비행기 문 주변이 막혀 있습니다. 조금 이동한 뒤 내려주세요.",
				"The cabin exit is obstructed. Taxi into a clear space first."
			))
			return
		var from_cam_pos: Vector3 = aircraft.chase.global_position
		seated = false
		aircraft.occupied = false
		aircraft.chase.current = false
		world.pilot.set_physics_process(true)
		world.pilot.collision_layer = 2
		world.pilot.collision_mask = 5
		world.pilot.global_position = point
		world.pilot.velocity = Vector3.ZERO
		world.pilot.transition_from_camera(from_cam_pos, PI - aircraft.heading)
		world.pilot.reset_physics_interpolation()
		world.set_walk_mode(true)
		persist()
	elif near_aircraft() and aircraft.can_exit():
		_enter_aircraft()
		say(I18n.t(
			"탑승 완료! [F] 활주로 즉시 정렬  ·  [W/S] 가속/감속 (자동 시동)  ·  [A/D] 좌우 선회  ·  [G] 스마트 보조 전환",
			"Hold W to start & fly  ·  F runway lineup  ·  A/D or Arrows steer  ·  G Flight Assist"
		))
	else:
		var spot: Vector3 = nav_guide.get_boarding_spot() if is_instance_valid(nav_guide) else (aircraft.global_position + Vector3(2.4, 0.0, 0.2))
		world.pilot.start_auto_walk(spot, func():
			say(I18n.t("비행기 앞에 도착했습니다! [B] 승객 예약 또는 [E] 탑승, [F] 활주로 즉시 출발을 누르세요.", "Arrived at the aircraft! Press [B] to book seats, [E] to board, or [F] for runway lineup."))
		)
		say(I18n.t("비행기 탑승구로 자동 이동합니다... (직접 이동하려면 [WASD]를 누르세요)", "Auto-walking to the aircraft... (Press [WASD] anytime for manual control)"))
	world.refresh_ui()

func exit_position() -> Vector3:
	var side_offset := 3.25 if aircraft.aircraft_id == "skywhale" else (2.95 if aircraft.aircraft_id == "albatross" else 2.7)
	for side in [1,-1]:
		var point: Vector3 = aircraft.global_position+Basis(Vector3.UP,aircraft.heading)*Vector3(side*side_offset,0,.1)
		var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*4,point-Vector3.UP*5,1)
		var hit: Dictionary = aircraft.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y<.7:continue
		point = hit.position+Vector3.UP*.08
		var capsule := CapsuleShape3D.new()
		capsule.radius = .28
		capsule.height = 1.76
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*.88)
		query.collision_mask = 5
		query.exclude = [aircraft.get_rid()]
		if aircraft.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return point
	return Vector3(INF,INF,INF)

func on_liftoff() -> void:
	arrival_error_latched = false
	if not departed:
		departure_field = Airfields.field_at(aircraft.position)
		departed = true
		aircraft.flight_seconds = 0
		aircraft.distance_flown = 0
	landed = false
	parked_seconds = 0
	auto_stop_seconds = 0
	say(I18n.t(
		"이륙 성공! 하늘의 노란 가이드 링(◎)을 따라 [A/D]로 선회하며 비행하세요.",
		"Airborne. Follow the sky guide rings; use A/D or Left/Right to steer."
	))

func on_touchdown(_sink_rate: float) -> void:
	landed = true
	parked_seconds = 0
	auto_stop_seconds = 0
	say(I18n.t(
		"착륙했습니다! [S]와 [Space]를 길게 눌러 활주로에 완전히 멈추면 운임이 정산됩니다.",
		"Touchdown. Hold S to idle, Space to brake, then stop on the runway."
	))

func on_crash(reason: String) -> void:
	company.cancel_trip()
	departed = false
	landed = false
	persist()
	say(reason)

func recover() -> void:
	if is_instance_valid(fleet_panel):
		fleet_panel.hide()
	arrival_error_latched = false
	company.cancel_trip()
	var field: Dictionary = Airfields.DATA[company.current_airfield]
	if not test_mode and company.fuel_litres < 10.0 and company.money_cents < 2200:
		company.fuel_litres = 15.0
	aircraft.fuel_available = company.fuel_litres > 0
	aircraft.reset_at(field.spawn,field.yaw)
	if is_instance_valid(nav_guide):
		nav_guide.reset_route(selected_destination(company.current_airfield))
	departed = false
	landed = false
	parked_seconds = 0
	auto_stop_seconds = 0
	world.pilot.auto_walk_active = false
	if not seated:
		world.pilot.respawn()
		var spawn_pos: Vector3 = field.spawn + Vector3(3.0, .2, 2.0)
		world.pilot.global_position = spawn_pos
		var to_plane := aircraft.global_position - spawn_pos
		var look_yaw := atan2(-to_plane.x, -to_plane.z)
		world.pilot.yaw = look_yaw
		world.pilot.facing_yaw = look_yaw
		world.pilot.update_look()
		world.set_walk_mode(true)
	else:
		aircraft.chase.make_current()
	panel.hide()
	update_blocks()
	refresh_desk()
	world.refresh_ui()
	persist()
	say(I18n.t(
		"★ %s 비행장 주기장으로 안전하게 리셋되었습니다! ([F] 활주로 즉시 출발 · [B] 운항 데스크)" % airfield_display_name(company.current_airfield),
		"Returned to "+field.name+". Booking cancelled; remaining fuel retained."
	))

func burn_fuel(litres: float) -> void:
	company.consume_fuel(litres)
	aircraft.fuel_available = company.fuel_litres>0

func persist() -> void:
	if test_mode or persistence_blocked:return
	var result: Dictionary = company.save()
	if not result.ok:say(I18n.t("저장 실패: ", "Could not save company: ")+result.message)

func hide_for_capture() -> void:
	for overlay in overlays:
		overlay.hide()
		overlay.set_process(false)
	if is_instance_valid(nav_guide):
		nav_guide.hide()
		nav_guide.set_process(false)
	set_process(false)

func handle_key(event: InputEventKey) -> bool:
	if event.keycode in [KEY_ESCAPE, KEY_BACKSPACE] and is_menu_open():
		toggle_desk()
		return true
	if event.keycode in [KEY_HOME, KEY_BACKSPACE]:
		recover()
		return true
	if event.keycode==KEY_F and (world.walking_mode or seated) and (not aircraft.airborne or not test_mode):
		quick_start_or_lineup()
		return true
	if event.keycode==KEY_B:
		if world.walking_mode or seated:
			toggle_desk()
			return true
	if event.keycode==KEY_ESCAPE and is_menu_open():
		toggle_desk()
		return true
	if is_menu_open() and event.keycode in [KEY_C,KEY_V,KEY_SPACE,KEY_E]:return true
	if event.keycode==KEY_E and (world.walking_mode or seated):
		interact()
		return true
	if seated:
		if event.keycode==KEY_G:
			aircraft.assist_enabled = not aircraft.assist_enabled
			var status_str := I18n.t("켜짐 (자동 수평·경로 유도 활성화)", "ON (Auto-level & route guidance)") if aircraft.assist_enabled else I18n.t("꺼짐 (수동 조종 모드)", "OFF (Manual control)")
			say(I18n.t("스마트 비행 보조 [G]: %s" % status_str, "Smart Flight Assist [G]: %s" % status_str))
			return true
		if event.keycode==KEY_X:
			if is_menu_open() or world.help_panel.visible:return true
			if not aircraft.toggle_engine():
				say(I18n.t("연료가 부족합니다! [B] 운항 데스크를 열어 연료를 주유하세요.", "No fuel available. Open the flight desk after landing to refuel."))
			return true
		if event.keycode in [KEY_C,KEY_V]:
			aircraft.cycle_chase_zoom()
			return true
		if event.keycode==KEY_SPACE:return true
	return false

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		persist()
		get_tree().quit()
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and not test_mode and seated and is_instance_valid(panel):
		if not is_menu_open():toggle_desk()

func _build_mission_guide_text() -> String:
	var has_booking := not company.active_trip.is_empty()
	var dest_id: String = company.active_trip.get("destination", selected_destination(company.current_airfield))
	var dest_name := airfield_display_name(dest_id)
	if aircraft.wrecked:
		return I18n.t(
			"⚠ [Home] 키를 눌러 비행장으로 안전하게 복귀하세요.",
			"⚠ Press [Home] to recover at the airfield."
		)
	if not has_booking and not seated:
		if near_aircraft():
			return I18n.t(
				"▶ [B] 승객 좌석 예약 · [E] 즉시 탑승 · [F] 원클릭 출발",
				"▶ [B] Book seats · [E] Board · [F] Quick Start"
			)
		return I18n.t(
			"▶ [WASD]로 비행기까지 이동 후 [B] 예약 또는 [F] 즉시 출발",
			"▶ Walk to the plane ([WASD]) and press [B] to book or [F] to start"
		)
	if has_booking and not seated:
		return I18n.t(
			"✓ %s행 예약 완료  ·  ▶ [E] 탑승 또는 [F] 활주로 출발" % dest_name,
			"✓ Booked for %s  ·  ▶ Press [E] to board or [F] for lineup" % dest_name
		)
	if seated and not aircraft.airborne:
		if departed and landed and Airfields.field_at(aircraft.position) != "" and Airfields.field_at(aircraft.position) != departure_field:
			return I18n.t(
				"▶ [S] + [Space]를 길게 눌러 완전히 정차하면 운임이 정산됩니다!",
				"▶ Hold [S] + [Space] to come to a full stop for payout!"
			)
		var on_runway_lineup := absf(aircraft.position.z - Airfields.DATA[company.current_airfield].lineup.z) < 9.0
		if not on_runway_lineup:
			return I18n.t(
				"▶ [F] 활주로 출발선 정렬 후 [W]를 길게 눌러 이륙하세요!",
				"▶ Press [F] to line up, then hold [W] to take off!"
			)
		return I18n.t(
			"▶ [W] 길게 눌러 이륙! ([↑] 고도 상승(위로) · [↓] 고도 하강(내려가기))",
			"▶ Hold [W] to take off! ([↑] Climb Up · [↓] Descend Down)"
		)
	return I18n.t(
		"▶ 황금 링(◎) 통과 → %s 착륙 ([↑] 고도 상승 · [↓] 고도 하강 · [S+Space] 착륙 브레이크)" % dest_name,
		"▶ Fly through rings (◎) → Land at %s ([↑] Climb · [↓] Descend · [S+Space] Brake)" % dest_name
	)

func _process(delta: float) -> void:
	if not is_instance_valid(panel):return
	update_blocks()
	var photo_mode: bool = not world.walking_mode and not seated
	var modal_open: bool = is_menu_open()
	flight_overview.visible = not photo_mode and not modal_open
	flight_chart.visible = seated and not modal_open
	notice.visible = not photo_mode and not modal_open and not world.help_panel.visible
	if notice_seconds>0:
		notice_seconds -= delta
		if notice_seconds<=0:notice.text = ""
	var origin := company.current_airfield
	var destination: String = company.active_trip.get("destination",selected_destination(origin))
	var dest_name := airfield_display_name(destination)
	var offset: Vector3 = Airfields.DATA[destination].centre-aircraft.position
	var bearing := fposmod(rad_to_deg(atan2(offset.x,-offset.z)),360)
	if desk_button:
		desk_button.text = I18n.t("운항 데스크 · B", "Flight desk · B")
	if fleet_hud_button:
		fleet_hud_button.text = I18n.t("◆ 격납고 (4기종)", "◆ Fleet (4)")
	if lineup_hud_button:
		lineup_hud_button.text = I18n.t("▶ 활주로 출발 · F", "▶ Line Up · F")
	if reset_hud_button:
		reset_hud_button.text = I18n.t("위치 리셋 · Backspace", "Reset · Backspace")
	route_label.text = "%s  ·  %.1f km  ·  %03d°" % [dest_name,Vector2(offset.x,offset.z).length()/1000,bearing]
	if not seated:
		route_label.text = I18n.t("다음 노선  ·  " + dest_name, "Next route  ·  " + Airfields.DATA[destination].name)
	var booking_text := I18n.t("예약 없음", "No booking") if company.active_trip.is_empty() else I18n.t("승객 %d명 탑승" % company.active_trip.seats, "%d passengers" % company.active_trip.seats)
	account_label.text = "%s   ·   %.1f L   ·   %s" % [dollars(company.money_cents),company.fuel_litres,booking_text]
	if persistence_blocked:
		account_label.text += I18n.t("\n저장 비활성화 · 원본 파일 보존됨", "\nSAVE UNAVAILABLE · original files preserved")
	if mission_guide_label:
		mission_guide_label.text = _build_mission_guide_text()
	instruments.visible = seated
	if seated:
		var agl := maxf(0,aircraft.position.y-world.height_at(aircraft.position.x,aircraft.position.z))
		var state := I18n.t("시동 꺼짐 ([W] 시동)", "ENGINE OFF (Hold W)") if not aircraft.engine_running else (I18n.t("비행 중", "IN FLIGHT") if aircraft.airborne else I18n.t("지상 활주", "ON GROUND"))
		if aircraft.suspended:state = I18n.t("일시정지", "PAUSED")
		elif aircraft.wrecked:state = I18n.t("사고 복구 · [Home]", "RECOVERY · HOME")
		elif aircraft.airborne and aircraft.airspeed<aircraft.stall_speed:state = I18n.t("속도 낮음! [W] 가속 + [↓] 고도 하강", "LOW SPEED · [↓] DESCEND")
		elif absf(aircraft.position.x)>900 or absf(aircraft.position.z)>900:state = I18n.t("계곡 경계 접근 · 선회", "VALLEY EDGE · TURN BACK")
		var compass := fposmod(180-rad_to_deg(aircraft.heading),360)
		var assist_badge := I18n.t("켜짐", "ON") if aircraft.assist_enabled else I18n.t("꺼짐", "OFF")
		var vspeed_hint := ""
		if Input.is_physical_key_pressed(KEY_UP):
			vspeed_hint = I18n.t(" (▲ 상승 중)", " (▲ Climbing)")
		elif Input.is_physical_key_pressed(KEY_DOWN):
			vspeed_hint = I18n.t(" (▼ 하강 중)", " (▼ Descending)")
		instruments.text = I18n.t(
			"속도 %03d km/h   ·   고도 %03d m%s   ·   방위 %03d°\n출력 %d%%   ·   %s   ·   보조[G]: %s" % [aircraft.airspeed*3.6,agl,vspeed_hint,compass,aircraft.throttle*100,state,assist_badge],
			"%03d km/h   ·   %03d m AGL%s   ·   HDG %03d°\nPower %d%%   ·   %s   ·   Assist [G]: %s" % [aircraft.airspeed*3.6,agl,vspeed_hint,compass,aircraft.throttle*100,state,assist_badge]
		)
		if aircraft.can_exit():
			prompt.text = I18n.t("[E] 비행기 하차   ·   [F] 활주로 출발선 정렬   ·   [Backspace] 리셋", "E Leave aircraft   ·   F Runway lineup   ·   Backspace Reset")
			prompt.disabled = false
		else:
			prompt.text = I18n.t("▶ [Backspace / Home] 비행장 리셋   ·   [F] 활주로 재출발", "▶ [Backspace / Home] Reset to Airfield   ·   [F] Runway Restart")
			prompt.disabled = false
	else:
		if near_aircraft():
			prompt.text = I18n.t("[E] %s 탑승하기   ·   [B] 승객 예약   ·   [F] 활주로 즉시 출발" % aircraft_name(), "E  ·  Board %s   (B Book  ·  F Quick Start)" % aircraft_name())
		else:
			prompt.text = I18n.t("[E] %s까지 자동 이동 (%d m)   ·   [F] 원클릭 예약+활주로 출발   ·   [Backspace] 리셋" % [aircraft_name(),world.pilot.position.distance_to(aircraft.position)], "[E] Auto-walk to %s (%d m)   ·   [F] Quick Start   ·   [Backspace] Reset" % [aircraft_name(),world.pilot.position.distance_to(aircraft.position)])
		prompt.disabled = false
	if aircraft.wrecked:
		prompt.text = I18n.t("▶ 여기를 클릭하거나 [Backspace / Home]을 눌러 비행장으로 복귀하기", "▶ Click here or press [Backspace / Home] to Recover Aircraft")
		prompt.disabled = false
	prompt.visible = not is_menu_open() and not world.help_panel.visible and (world.walking_mode or (seated and (not aircraft.airborne or aircraft.wrecked)))
	if not aircraft.suspended:
		check_arrival(delta)
		if aircraft.engine_running:
			save_seconds += delta
			if save_seconds>10:
				save_seconds = 0
				persist()

func check_arrival(delta: float) -> void:
	if arrival_error_latched:return
	var dest_here := Airfields.field_at(aircraft.position)
	# In manual play, once landed and stopped on the destination runway, automatically cut the engine so arrival triggers smoothly.
	if not aircraft.control_override and departed and landed and not aircraft.airborne and aircraft.is_on_floor() and aircraft.airspeed < .75 and dest_here != "" and dest_here != departure_field and not Input.is_physical_key_pressed(KEY_W):
		auto_stop_seconds += delta
		if auto_stop_seconds >= .6 and aircraft.engine_running:
			aircraft.engine_running = false
			aircraft.throttle = 0.0
	else:
		auto_stop_seconds = 0.0
	if not departed or not landed or not aircraft.can_exit() or aircraft.flight_seconds<8 or aircraft.distance_flown<150:
		parked_seconds = 0
		return
	var destination := dest_here
	if destination=="" or destination==departure_field:return
	parked_seconds += delta
	if parked_seconds<2:return
	var result: Dictionary
	if company.active_trip.is_empty():result = company.arrive_at(destination)
	else:
		if departure_field!=company.active_trip.origin or destination!=company.active_trip.destination:return
		result = company.complete_trip(destination)
	if not result.ok:
		arrival_error_latched = true
		say(result.message)
		return
	departed = false
	landed = false
	target_destination = Airfields.next_in_circuit(destination)
	if is_instance_valid(nav_guide):
		nav_guide.reset_route(selected_destination(destination))
	if world.has_method("update_parked_fleet"):
		world.call("update_parked_fleet", company.active_aircraft_id)
	var dest_display := airfield_display_name(destination)
	if result.has("payout_cents"):
		var base_payout := int(result.payout_cents)
		var bonus_cents := 0
		var grade_str := "B"
		if aircraft.last_sink_rate < 1.25:
			grade_str = "S (버터 랜딩!)" if I18n.is_ko() else "S (Butter Landing!)"
			bonus_cents = 4500
		elif aircraft.last_sink_rate < 2.6:
			grade_str = "A (소프트 랜딩!)" if I18n.is_ko() else "A (Smooth Landing!)"
			bonus_cents = 2500
		else:
			grade_str = "B (안전 착륙)" if I18n.is_ko() else "B (Safe Landing)"
		if not test_mode and bonus_cents > 0:
			company.money_cents += bonus_cents
			company.total_revenue_cents += bonus_cents
		persist()
		var total_earned := base_payout + (bonus_cents if not test_mode else 0)
		say(I18n.t(
			"★ %s 도착! 착륙 등급 [%s] · 총 수익 %s 입금! ([F] 왕복 노선 즉시 출발 · [B] 데스크)" % [dest_display, grade_str, dollars(total_earned)],
			"Welcome to %s! Landing Grade [%s] · Earned %s! ([F] Quick Return · [B] Desk)" % [Airfields.DATA[destination].name, grade_str, dollars(total_earned)]
		))
	else:
		persist()
		say(I18n.t(
			"%s 도착 완료! 현재 비행장 위치가 저장되었습니다. ([F] 왕복 즉시 출발)" % dest_display,
			"Welcome to "+Airfields.DATA[destination].name+". Company location saved."
		))
	refresh_desk()
