extends PanelContainer
## Compact fleet overview. Company mutations remain owned by FlightSession.

const AircraftCatalog = preload("res://aircraft_catalog.gd")
const Airfields = preload("res://airfields.gd")
const I18n = preload("res://i18n.gd")

const AIRCRAFT_ORDER: PackedStringArray = ["heron", "osprey", "albatross", "skywhale"]
const PANEL_SIZE := Vector2(1220.0, 580.0)

var world: Node3D
var session: Node
var title_label: Label
var subtitle_label: Label
var close_button: Button
var balance_label: Label
var progress_label: Label
var progress_bar: ProgressBar
var unavailable_label: Label
var role_labels: Dictionary = {}
var specs_labels: Dictionary = {}
var offer_labels: Dictionary = {}
var status_labels: Dictionary = {}
var action_buttons: Dictionary = {}


func configure(game: Node3D, flight_session: Node) -> void:
	world = game
	session = flight_session
	_build_ui()
	refresh()


func refresh() -> void:
	if session == null or balance_label == null:
		return
	var company_value: Variant = session.get("company")
	if company_value == null:
		return
	var company: Object = company_value as Object
	if company == null:
		return
	var money_cents: int = int(company.get("money_cents"))
	var current_airfield: String = str(company.get("current_airfield"))
	var active_aircraft_id: String = str(company.get("active_aircraft_id"))
	var owned_value: Variant = company.get("owned_aircraft")
	var owned_aircraft: Dictionary = owned_value if owned_value is Dictionary else {}
	var reason: String = _unavailable_reason()
	if title_label:
		title_label.text = I18n.t("항공기 격납고 (4종 항공단)", "Fleet hangar (4 Aircraft)")
	if subtitle_label:
		subtitle_label.text = I18n.t("더 큰 비행기를 구매해 승객 좌석(3석 → 5석 → 9석 → 15석)과 연료 탱크를 확장하세요.", "Upgrade to larger aircraft to sell more passenger seats (3 → 5 → 9 → 15) and carry more fuel.")
	if close_button:
		close_button.text = I18n.t("닫기  ·  B / Esc", "Close  ·  B / Esc")
	balance_label.text = I18n.t("보유 자금   %s" % _dollars(money_cents), "Company balance   %s" % _dollars(money_cents))
	_update_progress(money_cents, owned_aircraft)
	unavailable_label.text = reason
	unavailable_label.visible = not reason.is_empty()

	for aircraft_id in AIRCRAFT_ORDER:
		var data_value: Variant = AircraftCatalog.DATA.get(aircraft_id, {})
		var data: Dictionary = data_value if data_value is Dictionary else {}
		var owned: bool = owned_aircraft.has(aircraft_id)
		var record_value: Variant = owned_aircraft.get(aircraft_id, {})
		var record: Dictionary = record_value if record_value is Dictionary else {}
		var location: String = str(record.get("airfield", current_airfield))
		var fuel_litres: float = float(record.get("fuel_litres", 0.0))
		var is_active: bool = aircraft_id == active_aircraft_id
		var role_lbl: Label = role_labels.get(aircraft_id) as Label
		var specs_lbl: Label = specs_labels.get(aircraft_id) as Label
		var offer_lbl: Label = offer_labels.get(aircraft_id) as Label
		var status: Label = status_labels.get(aircraft_id) as Label
		var action: Button = action_buttons.get(aircraft_id) as Button
		if role_lbl:
			if aircraft_id == "heron":
				role_lbl.text = I18n.t("소형 경비행기 · 3인승 단거리 운항", "Light utility · 3-seat starter")
			elif aircraft_id == "osprey":
				role_lbl.text = I18n.t("중형 커뮤터 · 5인승 고수익 수송기", "Commuter · 5-seat cabin")
			elif aircraft_id == "albatross":
				role_lbl.text = I18n.t("중대형 쌍발기 · 9인승 대용량 수송기", "Twin commuter · 9-seat cabin")
			else:
				role_lbl.text = I18n.t("대형 리저널 여객기 · 15인승 플래그십", "Regional airliner · 15-seat flagship")
		if specs_lbl:
			var passenger_seats: int = int(data.get("passenger_seats", 0))
			var fuel_capacity: float = float(data.get("fuel_capacity", 0.0))
			var idle_burn: float = float(data.get("idle_burn", 0.0))
			var full_burn: float = float(data.get("full_burn", 0.0))
			var takeoff_kmh: int = roundi(float(data.get("takeoff_speed", 0.0)) * 3.6)
			var stall_kmh: int = roundi(float(data.get("stall_speed", 0.0)) * 3.6)
			specs_lbl.text = I18n.t(
				"승객 좌석 %d석   ·   연료 탱크 %.0f L\n연료 소모 %.0f–%.0f L/시간\n이륙 %d km/h   ·   실속 %d km/h" % [passenger_seats, fuel_capacity, idle_burn, full_burn, takeoff_kmh, stall_kmh],
				"%d passenger seats   ·   %.0f L tank\nFuel use %.0f–%.0f L/hr\nTakeoff %d km/h   ·   Stall %d km/h" % [passenger_seats, fuel_capacity, idle_burn, full_burn, takeoff_kmh, stall_kmh]
			)
		if offer_lbl:
			var price_cents: int = int(data.get("price_cents", 0))
			var purchase_fuel: float = float(data.get("purchase_fuel", 0.0))
			if price_cents <= 0:
				offer_lbl.text = I18n.t("기본 제공 기체", "Included with your company")
			else:
				offer_lbl.text = I18n.t("구매가 %s   ·   연료 %.0f L 제공" % [_dollars(price_cents), purchase_fuel], "%s purchase   ·   %.0f L delivered" % [_dollars(price_cents), purchase_fuel])
		if status == null or action == null:
			continue
		_update_aircraft_status(status, aircraft_id, data, owned, is_active, location, fuel_litres)
		_update_aircraft_action(action, aircraft_id, data, owned, is_active, location, current_airfield, money_cents, reason)


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_SIZE.x * 0.5
	offset_right = PANEL_SIZE.x * 0.5
	offset_top = -PANEL_SIZE.y * 0.5
	offset_bottom = PANEL_SIZE.y * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _style(Color(0.025, 0.048, 0.052, 0.985)))

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	add_child(content)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	content.add_child(heading)
	var title_group := VBoxContainer.new()
	title_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_group.add_theme_constant_override("separation", 1)
	heading.add_child(title_group)
	title_label = _label(I18n.t("항공기 격납고 (4종 항공단)", "Fleet hangar (4 Aircraft)"), 23, Color("f0dfbb"))
	title_group.add_child(title_label)
	subtitle_label = _label(I18n.t("더 큰 비행기를 구매해 승객 좌석(3석 → 5석 → 9석 → 15석)과 연료 탱크를 확장하세요.", "Upgrade to larger aircraft to sell more passenger seats (3 → 5 → 9 → 15) and carry more fuel."), 12, Color("a8b9b0"))
	title_group.add_child(subtitle_label)
	close_button = _button(I18n.t("닫기  ·  B / Esc", "Close  ·  B / Esc"), 158.0)
	close_button.pressed.connect(_close)
	heading.add_child(close_button)

	var account_row := HBoxContainer.new()
	account_row.add_theme_constant_override("separation", 16)
	content.add_child(account_row)
	balance_label = _label("", 15, Color("f0e5cc"))
	balance_label.custom_minimum_size.x = 245.0
	account_row.add_child(balance_label)
	progress_label = _label("", 12, Color("c2d2c5"))
	progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	account_row.add_child(progress_label)

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 10.0
	progress_bar.show_percentage = false
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.add_theme_stylebox_override("background", _style(Color(0.035, 0.064, 0.067, 0.95)))
	progress_bar.add_theme_stylebox_override("fill", _style(Color(0.72, 0.54, 0.29, 0.95)))
	content.add_child(progress_bar)

	unavailable_label = _label("", 12, Color("e6c791"))
	unavailable_label.custom_minimum_size.y = 20.0
	unavailable_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(unavailable_label)

	var cards := HBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 10)
	content.add_child(cards)
	for aircraft_id in AIRCRAFT_ORDER:
		var data_value: Variant = AircraftCatalog.DATA.get(aircraft_id, {})
		var data: Dictionary = data_value if data_value is Dictionary else {}
		cards.add_child(_build_aircraft_card(aircraft_id, data))


func _build_aircraft_card(aircraft_id: String, data: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.0
	card.add_theme_stylebox_override("panel", _style(Color(0.048, 0.079, 0.078, 0.96)))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	card.add_child(body)

	var name: String = str(data.get("name", aircraft_id.capitalize()))
	body.add_child(_label(name, 19, Color("f0e5cc")))
	var role_lbl := _label("", 11, Color("91a99e"))
	body.add_child(role_lbl)
	role_labels[aircraft_id] = role_lbl

	var specs: Label = _label("", 12, Color("cbd6cf"))
	specs.add_theme_constant_override("line_spacing", 4)
	body.add_child(specs)
	specs_labels[aircraft_id] = specs

	var offer_lbl := _label("", 12, Color("e6c791"))
	body.add_child(offer_lbl)
	offer_labels[aircraft_id] = offer_lbl

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)
	var status := _label("", 12, Color("f0e5cc"))
	status.custom_minimum_size.y = 42.0
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	status_labels[aircraft_id] = status
	var action: Button = _button("", 0.0)
	action.pressed.connect(_aircraft_action.bind(aircraft_id))
	body.add_child(action)
	action_buttons[aircraft_id] = action
	return card


func _update_progress(money_cents: int, owned_aircraft: Dictionary) -> void:
	var target_id: String = ""
	for candidate_id in AIRCRAFT_ORDER:
		if not owned_aircraft.has(candidate_id):
			target_id = candidate_id
			break
	if target_id.is_empty():
		progress_bar.min_value = 0.0
		progress_bar.max_value = 1.0
		progress_bar.value = 1.0
		progress_label.text = I18n.t("전 기종(4대) 모두 보유 완료!", "All 4 fleet aircraft owned!")
		return
	var target_value: Variant = AircraftCatalog.DATA.get(target_id, {})
	var target_data: Dictionary = target_value if target_value is Dictionary else {}
	var target_name: String = str(target_data.get("name", target_id.capitalize()))
	var price_cents: int = int(target_data.get("price_cents", 0))
	progress_bar.min_value = 0.0
	progress_bar.max_value = maxf(1.0, float(price_cents))
	progress_bar.value = float(clampi(money_cents, 0, price_cents))
	var remaining: int = maxi(0, price_cents - money_cents)
	if remaining > 0:
		progress_label.text = I18n.t(
			"%s 목표: %s / %s   ·   구매까지 %s 남음" % [target_name, _dollars(mini(money_cents, price_cents)), _dollars(price_cents), _dollars(remaining)],
			"Next (%s): %s of %s   ·   %s to go" % [target_name, _dollars(mini(money_cents, price_cents)), _dollars(price_cents), _dollars(remaining)]
		)
	else:
		progress_label.text = I18n.t(
			"%s (%s) 지금 바로 구매 가능!" % [target_name, _dollars(price_cents)],
			"%s (%s) ready to purchase!" % [target_name, _dollars(price_cents)]
		)


func _update_aircraft_status(status: Label, aircraft_id: String, data: Dictionary, owned: bool, is_active: bool, location: String, fuel_litres: float) -> void:
	if not owned:
		status.text = I18n.t("구매 가능\n구매 시 즉시 계류장에 배치됩니다.", "AVAILABLE\nDelivered straight to the apron.")
		status.add_theme_color_override("font_color", Color("c2d2c5"))
		return
	var capacity: float = float(data.get("fuel_capacity", 0.0))
	var location_name: String = _airfield_name(location)
	var label: String = I18n.t("현재 탑승 기체", "ACTIVE AIRCRAFT") if is_active else I18n.t("보유 중", "OWNED")
	if aircraft_id == "heron" and not is_active:
		label = I18n.t("보유 중 · 기본 기체", "OWNED · ORIGINAL AIRCRAFT")
	status.text = I18n.t("%s\n%s   ·   연료 %.1f / %.0f L" % [label, location_name, fuel_litres, capacity], "%s\n%s   ·   %.1f / %.0f L fuel" % [label, location_name, fuel_litres, capacity])
	status.add_theme_color_override("font_color", Color("e6c791") if is_active else Color("f0e5cc"))


func _update_aircraft_action(action: Button, _aircraft_id: String, data: Dictionary, owned: bool, is_active: bool, _location: String, _current_airfield: String, money_cents: int, reason: String) -> void:
	action.tooltip_text = ""
	if is_active:
		action.text = I18n.t("현재 선택된 기체", "Flying this aircraft")
		action.disabled = true
		return
	if owned:
		action.text = I18n.t("이 기체로 전환", "Fly this aircraft")
		action.disabled = not reason.is_empty()
		if action.disabled:
			action.tooltip_text = reason
		return
	var price_cents: int = int(data.get("price_cents", 0))
	var shortfall: int = maxi(0, price_cents - money_cents)
	if shortfall > 0:
		action.text = I18n.t("%s 더 필요" % _dollars(shortfall), "Need %s more" % _dollars(shortfall))
		action.disabled = true
		action.tooltip_text = I18n.t("승객 운송 비행을 완료해 자금을 모으세요.", "Complete more passenger flights to build your balance.")
	else:
		action.text = I18n.t("%s에 구매하기" % _dollars(price_cents), "Buy for %s" % _dollars(price_cents))
		action.disabled = not reason.is_empty()
		if action.disabled:
			action.tooltip_text = reason


func _aircraft_action(aircraft_id: String) -> void:
	var company_value: Variant = session.get("company")
	if company_value == null:
		return
	var company: Object = company_value as Object
	if company == null:
		return
	var owned_value: Variant = company.get("owned_aircraft")
	var owned_aircraft: Dictionary = owned_value if owned_value is Dictionary else {}
	if owned_aircraft.has(aircraft_id):
		session.call("select_aircraft", aircraft_id)
	else:
		session.call("buy_aircraft", aircraft_id)
	refresh()


func _close() -> void:
	session.call("toggle_fleet")


func _unavailable_reason() -> String:
	if not session.has_method("fleet_unavailable_reason"):
		return ""
	var reason_value: Variant = session.call("fleet_unavailable_reason")
	return str(reason_value)


func _airfield_name(airfield_id: String) -> String:
	if session and session.has_method("airfield_display_name"):
		return str(session.call("airfield_display_name", airfield_id))
	var field_value: Variant = Airfields.DATA.get(airfield_id, {})
	var field: Dictionary = field_value if field_value is Dictionary else {}
	return str(field.get("name", airfield_id.replace("_", " ").capitalize()))


func _dollars(cents: int) -> String:
	var absolute_cents: int = absi(cents)
	var whole_dollars: int = floori(float(absolute_cents) / 100.0)
	var digits: String = str(whole_dollars)
	var grouped: String = ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	grouped = digits + grouped
	var sign: String = "-" if cents < 0 else ""
	return "%s$%s.%02d" % [sign, grouped, absolute_cents % 100]


func _label(text: String, size: int, color: Color) -> Label:
	var created: Variant = world.call("ui_label", text, size, color)
	return created as Label


func _button(text: String, width: float) -> Button:
	var created: Variant = world.call("ui_button", text, width)
	return created as Button


func _style(color: Color) -> StyleBoxFlat:
	var created: Variant = world.call("button_style", color)
	return created as StyleBoxFlat
