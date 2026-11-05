extends Node3D
## 3D sky route rings, runway touchdown beacon, animated ground wayfinding trail (Dillman et al., CHI 2018),
## Flight-Path Vector HUD predictor (Mulder, 1999), and split-attention-free Center Action Coach.

const Airfields = preload("res://airfields.gd")
const I18n = preload("res://i18n.gd")

const ROUTES := {
	"birch_hollow": [
		Vector3(165, 68, -220),
		Vector3(195, 82, -475),
		Vector3(60, 56, -640),
		Vector3(-75, 35, -640)
	],
	"mossvale": [
		Vector3(110, 74, -490),
		Vector3(165, 76, -240),
		Vector3(210, 44, -52),
		Vector3(95, 19, -52)
	],
	"pine_ridge": [
		Vector3(50, 72, -595),
		Vector3(210, 80, -560),
		Vector3(280, 56, -520),
		Vector3(340, 45, -520)
	],
	"mirror_lake": [
		Vector3(180, 76, -220),
		Vector3(20, 68, 120),
		Vector3(-380, 42, 380),
		Vector3(-340, 22, 380)
	]
}

var session: Node
var ring_nodes: Array[MeshInstance3D] = []
var beacon_mesh: MeshInstance3D
var boarding_ring: MeshInstance3D
var ground_trail_nodes: Array[MeshInstance3D] = []
var ring_mat_active: StandardMaterial3D
var ring_mat_next: StandardMaterial3D
var beacon_mat: StandardMaterial3D
var trail_mat: StandardMaterial3D
var hud_marker: Control
var active_dest := ""
var waypoint_index := 0
var pulse := 0.0


func configure(flight_session: Node, hud_root: Control) -> void:
	session = flight_session
	_build_materials()
	_build_meshes()
	hud_marker = Control.new()
	hud_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_marker.draw.connect(_draw_hud_marker)
	hud_root.add_child(hud_marker)
	session.overlays.append(hud_marker)


func _build_materials() -> void:
	ring_mat_active = StandardMaterial3D.new()
	ring_mat_active.albedo_color = Color(1.0, 0.84, 0.38, 0.88)
	ring_mat_active.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat_active.emission_enabled = true
	ring_mat_active.emission = Color(0.98, 0.76, 0.28)
	ring_mat_active.emission_energy_multiplier = 2.4
	ring_mat_active.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat_active.cull_mode = BaseMaterial3D.CULL_DISABLED

	ring_mat_next = StandardMaterial3D.new()
	ring_mat_next.albedo_color = Color(0.55, 0.86, 0.78, 0.42)
	ring_mat_next.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat_next.emission_enabled = true
	ring_mat_next.emission = Color(0.42, 0.78, 0.70)
	ring_mat_next.emission_energy_multiplier = 1.2
	ring_mat_next.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat_next.cull_mode = BaseMaterial3D.CULL_DISABLED

	beacon_mat = StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(0.98, 0.78, 0.34, 0.36)
	beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(0.98, 0.74, 0.28)
	beacon_mat.emission_energy_multiplier = 1.8
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	trail_mat = StandardMaterial3D.new()
	trail_mat.albedo_color = Color(1.0, 0.86, 0.42, 0.78)
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.emission_enabled = true
	trail_mat.emission = Color(1.0, 0.80, 0.32)
	trail_mat.emission_energy_multiplier = 2.1
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _build_meshes() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 16.5
	torus.outer_radius = 18.8
	torus.rings = 32
	torus.ring_segments = 12
	for i in range(4):
		var node := MeshInstance3D.new()
		node.name = "ApproachRing_%d" % i
		node.mesh = torus
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.material_override = ring_mat_next
		add_child(node)
		ring_nodes.append(node)

	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.2
	cyl.bottom_radius = 5.5
	cyl.height = 42.0
	cyl.radial_segments = 20
	beacon_mesh = MeshInstance3D.new()
	beacon_mesh.name = "RunwayBeacon"
	beacon_mesh.mesh = cyl
	beacon_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon_mesh.material_override = beacon_mat
	add_child(beacon_mesh)

	# Diegetic ground boarding zone ring beside aircraft door (Dillman et al., CHI 2018)
	var board_torus := TorusMesh.new()
	board_torus.inner_radius = 1.15
	board_torus.outer_radius = 1.35
	board_torus.rings = 28
	board_torus.ring_segments = 10
	boarding_ring = MeshInstance3D.new()
	boarding_ring.name = "BoardingZoneRing"
	boarding_ring.mesh = board_torus
	boarding_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	boarding_ring.material_override = trail_mat
	add_child(boarding_ring)

	# Animated ground trail markers leading from pilot feet to boarding ring
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 0.20
	pad_mesh.bottom_radius = 0.24
	pad_mesh.height = 0.025
	pad_mesh.radial_segments = 14
	for i in range(7):
		var dot := MeshInstance3D.new()
		dot.name = "GroundTrail_%d" % i
		dot.mesh = pad_mesh
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.material_override = trail_mat
		add_child(dot)
		ground_trail_nodes.append(dot)


func get_boarding_spot() -> Vector3:
	if session == null or not is_instance_valid(session.aircraft):
		return Vector3(2.4, 0.06, 3.0)
	var plane: Node3D = session.aircraft
	var plane_id: String = str(plane.get("aircraft_id"))
	var lateral := 3.15 if plane_id == "skywhale" else (2.85 if plane_id == "albatross" else 2.45)
	var spot: Vector3 = plane.global_position + Basis(Vector3.UP, plane.heading) * Vector3(lateral, 0.0, 0.2)
	if is_instance_valid(session.world) and session.world.has_method("height_at"):
		spot.y = maxf(plane.global_position.y, session.world.height_at(spot.x, spot.z) + 0.05)
	return spot


func reset_route(dest: String) -> void:
	active_dest = dest
	waypoint_index = 0
	var pts: Array = ROUTES.get(dest, [])
	var runway_centre: Vector3 = Airfields.DATA[dest].centre
	for i in range(ring_nodes.size()):
		if i < pts.size():
			var pos: Vector3 = pts[i]
			var next_pos: Vector3 = pts[i + 1] if i + 1 < pts.size() else (runway_centre + Vector3(0, 3.0, 0))
			ring_nodes[i].position = pos
			var dir := (next_pos - pos).normalized()
			var yaw := atan2(dir.x, dir.z)
			ring_nodes[i].rotation = Vector3(PI * 0.5, yaw, 0.0)
			ring_nodes[i].visible = true
		else:
			ring_nodes[i].visible = false
	beacon_mesh.position = runway_centre + Vector3(0, 21.0, 0)


func get_active_target() -> Dictionary:
	var origin: String = session.company.current_airfield
	var dest: String = session.company.active_trip.get("destination", Airfields.other(origin))
	var dest_name: String = session.airfield_display_name(dest)
	if dest != active_dest:
		reset_route(dest)
	var pts: Array = ROUTES.get(dest, [])
	var runway_target: Vector3 = Airfields.DATA[dest].centre + Vector3(0, 2.2, 0)
	if not session.aircraft.airborne and not session.departed:
		return {
			"pos": runway_target,
			"label": I18n.t("목적지: %s" % dest_name, "Destination: %s" % dest_name),
			"is_runway": true
		}
	if waypoint_index < pts.size():
		var wp: Vector3 = pts[waypoint_index]
		return {
			"pos": wp,
			"label": I18n.t("비행 경로 링 %d/%d  →  %s" % [waypoint_index + 1, pts.size(), dest_name], "Route Gate %d/%d  →  %s" % [waypoint_index + 1, pts.size(), dest_name]),
			"is_runway": false
		}
	return {
		"pos": runway_target,
		"label": I18n.t("착륙 활주로: %s ([S] 감속 · [Space] 브레이크)" % dest_name, "Land on Runway: %s ([S] slow · [Space] brake)" % dest_name),
		"is_runway": true
	}


func _process(delta: float) -> void:
	if session == null or not is_instance_valid(session.world):
		return
	pulse += delta * 3.2
	var in_capture: bool = session.world.capture_mode or session.world.stress_mode
	var on_foot: bool = not session.seated and session.world.walking_mode and not in_capture
	var show_flight_3d: bool = session.seated and not in_capture
	visible = on_foot or show_flight_3d
	if hud_marker:
		hud_marker.visible = not in_capture and not session.is_menu_open() and not session.world.help_panel.visible and (session.seated or session.world.walking_mode)
		if hud_marker.visible:
			hud_marker.queue_redraw()

	# Update ground wayfinding trail when walking on foot
	if on_foot:
		for node in ring_nodes:
			node.visible = false
		beacon_mesh.visible = false
		var board_pos := get_boarding_spot()
		boarding_ring.visible = true
		boarding_ring.position = board_pos + Vector3(0, 0.04, 0)
		boarding_ring.scale = Vector3.ONE * (1.0 + sin(pulse * 1.6) * 0.06)
		var pilot_pos: Vector3 = session.world.pilot.global_position
		var dist_to_board := Vector2(board_pos.x - pilot_pos.x, board_pos.z - pilot_pos.z).length()
		for i in range(ground_trail_nodes.size()):
			var dot := ground_trail_nodes[i]
			if dist_to_board < 1.8:
				dot.visible = false
			else:
				dot.visible = true
				var t := fmod(float(i) / float(ground_trail_nodes.size()) + pulse * 0.14, 1.0)
				var p := pilot_pos.lerp(board_pos, clampf(t, 0.08, 0.92))
				p.y = maxf(board_pos.y, session.world.height_at(p.x, p.z) + 0.045)
				dot.position = p
				var wave := 0.75 + 0.45 * sin(t * PI)
				dot.scale = Vector3(wave, 1.0, wave)
		waypoint_index = 0
		return

	boarding_ring.visible = false
	for dot in ground_trail_nodes:
		dot.visible = false

	if not session.seated:
		waypoint_index = 0
		return

	var origin: String = session.company.current_airfield
	var dest: String = session.company.active_trip.get("destination", Airfields.other(origin))
	if dest != active_dest:
		reset_route(dest)
	var pts: Array = ROUTES.get(dest, [])
	var plane_pos: Vector3 = session.aircraft.global_position
	var prev_idx := waypoint_index
	while waypoint_index < pts.size():
		var wp: Vector3 = pts[waypoint_index]
		if plane_pos.distance_to(wp) <= 22.0:
			waypoint_index += 1
		else:
			break
	if waypoint_index > prev_idx and session.aircraft.airborne:
		if waypoint_index < pts.size():
			session.say(I18n.t(
				"✓ 비행 경로 링 %d/%d 통과! 다음 황금 링(◎)을 향해 비행하세요." % [waypoint_index, pts.size()],
				"✓ Route Ring %d/%d cleared! Proceed to the next golden ring." % [waypoint_index, pts.size()]
			))
		else:
			session.say(I18n.t(
				"✓ 모든 경로 링 통과! 전방 활주로 빛기둥을 보고 [S] 감속 + [Space] 브레이크로 착륙하세요!",
				"✓ All route rings cleared! Align with the runway beacon and hold [S] + [Space] to land!"
			))

	var scale_pulse := 1.0 + sin(pulse) * 0.045
	for i in range(ring_nodes.size()):
		if i < waypoint_index or not show_flight_3d:
			ring_nodes[i].visible = false
		elif i == waypoint_index:
			ring_nodes[i].visible = true
			ring_nodes[i].material_override = ring_mat_active
			ring_nodes[i].scale = Vector3.ONE * scale_pulse
		else:
			ring_nodes[i].visible = true
			ring_nodes[i].material_override = ring_mat_next
			ring_nodes[i].scale = Vector3.ONE
	beacon_mesh.visible = show_flight_3d


func _get_coach_step() -> Dictionary:
	var has_booking: bool = not session.company.active_trip.is_empty()
	var dest_id: String = session.company.active_trip.get("destination", Airfields.other(session.company.current_airfield))
	var dest_name: String = session.airfield_display_name(dest_id)
	if session.aircraft.wrecked:
		return {
			"key": "Home",
			"title": I18n.t("비행장으로 즉시 복귀하기", "Recover at Airfield"),
			"sub": I18n.t("키보드의 [Home] 키 또는 아래 버튼을 누르세요", "Press [Home] or click the button below")
		}
	if not session.seated:
		if not session.near_aircraft():
			var auto_walking: bool = session.world.pilot.auto_walk_active
			if auto_walking:
				return {
					"key": "자동 이동 중",
					"title": I18n.t("비행기 탑승구로 자동으로 걸어가는 중입니다...", "Auto-walking to the aircraft door..."),
					"sub": I18n.t("도착하면 [B] 승객 예약 또는 [E] 즉시 탑승이 가능합니다", "Press [B] to book seats or [E] to board when you arrive")
				}
			return {
				"key": "E  /  F",
				"title": I18n.t("[E] 비행기로 자동 걸어가기   ·   [F] 원클릭 예약+활주로 출발!", "[E] Auto-walk to Plane   ·   [F] Quick Book & Line Up!"),
				"sub": I18n.t("바닥의 황금빛 유도선을 따라 [WASD]로 직접 걸어가도 됩니다", "Or walk manually with [WASD] along the golden ground trail")
			}
		if not has_booking:
			return {
				"key": "B  /  F",
				"title": I18n.t("지금 [B] 키로 승객 예약  또는  [F] 원클릭 활주로 출발!", "Press [B] to Book Passengers  or  [F] Quick Line Up!"),
				"sub": I18n.t("예약 없이 바로 자유 비행하려면 [E] 키를 누르세요", "Or press [E] to board immediately for free flight")
			}
		return {
			"key": "E  /  F",
			"title": I18n.t("승객 탑승 완료! [E] 조종석 탑승  또는  [F] 활주로 즉시 정렬", "Passengers Ready! Press [E] to Board  or  [F] Runway Lineup"),
			"sub": I18n.t("%s행 승객이 기다리고 있습니다" % dest_name, "Passengers booked for %s" % dest_name)
		}
	if not session.aircraft.airborne:
		if session.departed and session.landed and Airfields.field_at(session.aircraft.position) != "" and Airfields.field_at(session.aircraft.position) != session.departure_field:
			return {
				"key": "S + Space",
				"title": I18n.t("착륙 성공! [S] + [Space]를 눌러 완전히 멈추세요", "Touchdown! Hold [S] + [Space] to Stop Completely"),
				"sub": I18n.t("정차하면 자동으로 시동이 꺼지며 운임 수익이 입금됩니다!", "Engine shuts down and fares pay out automatically once stopped")
			}
		var on_runway_lineup := absf(session.aircraft.position.z - Airfields.DATA[session.company.current_airfield].lineup.z) < 9.0
		if not on_runway_lineup:
			return {
				"key": "F",
				"title": I18n.t("지금 [F] 키를 눌러 활주로 출발선에 즉시 정렬하세요!", "Press [F] Now to Line Up on the Runway!"),
				"sub": I18n.t("복잡한 지상 이동 없이 바로 이륙 위치로 옮겨줍니다", "Skips manual taxiing and aligns you straight down the runway")
			}
		return {
			"key": "W 길게 누르기",
			"title": I18n.t("[W] 키를 계속 누르고 있으면 자동 시동 후 하늘로 이륙합니다!", "Hold [W] to Auto-Start Engine and Take Off!"),
			"sub": I18n.t("스마트 비행 보조(ON)가 켜져 있어 [W]만 눌러도 안전하게 상승합니다", "Smart Co-Pilot Assist automatically lifts off and climbs safely")
		}
	var assist_str := I18n.t("ON ([G] 전환)", "ON ([G] toggle)") if session.aircraft.assist_enabled else I18n.t("OFF ([G] 전환)", "OFF ([G] toggle)")
	return {
		"key": "W / A·D / S",
		"title": I18n.t("하늘의 황금 링(◎)을 통과해 %s 활주로에 착륙하세요!" % dest_name, "Fly Through the Golden Rings (◎) to %s!" % dest_name),
		"sub": I18n.t("스마트 자동 조향 보조: %s  ·  착륙 시 [S] 감속 + [Space] 브레이크" % assist_str, "Smart Flight Assist: %s  ·  Hold [S] + [Space] to land & brake" % assist_str)
	}


func _draw_hud_marker() -> void:
	if session == null or hud_marker == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var font := I18n.get_ui_font()
	var viewport_size := get_viewport().get_visible_rect().size
	var target_world: Vector3
	var label_text: String
	var accent: Color

	if not session.seated:
		target_world = get_boarding_spot() + Vector3(0, 1.5, 0)
		var d_plane: int = int(session.world.pilot.global_position.distance_to(session.aircraft.global_position))
		if session.near_aircraft():
			label_text = I18n.t("◆ 탑승 위치 도착! [B] 승객 예약 · [E] 탑승 · [F] 활주로 즉시 출발", "◆ Ready! [B] Book · [E] Board · [F] Quick Line Up")
		else:
			label_text = I18n.t("◆ 비행기 탑승구 (%dm) · [E] 자동 걸어가기 / [F] 즉시 출발" % d_plane, "◆ Boarding Door (%dm) · [E] Auto-Walk / [F] Quick Start" % d_plane)
		accent = Color("ffd584")
	else:
		var info := get_active_target()
		target_world = info.pos
		var dist_m: float = session.aircraft.global_position.distance_to(target_world)
		var dist_str: String = ("%.1f km" % (dist_m / 1000.0)) if dist_m >= 1000.0 else ("%d m" % int(dist_m))
		label_text = "%s  ·  %s" % [info.label, dist_str]
		accent = Color("ffd584") if not info.is_runway else Color("8bf0c8")

	var behind := cam.is_position_behind(target_world)
	var screen_pos := cam.unproject_position(target_world)
	if behind:
		var local := cam.global_transform.affine_inverse() * target_world
		screen_pos.x = viewport_size.x * 0.5 + (1.0 if local.x >= 0.0 else -1.0) * viewport_size.x * 0.45
		screen_pos.y = viewport_size.y * 0.45

	var margin_x := 180.0
	var margin_top := 135.0
	var margin_bottom := 260.0
	var clamped := Vector2(
		clampf(screen_pos.x, margin_x, viewport_size.x - margin_x),
		clampf(screen_pos.y, margin_top, viewport_size.y - margin_bottom)
	)
	var offscreen := behind or not screen_pos.is_equal_approx(clamped)
	var prefix := ""
	if offscreen:
		if screen_pos.x <= margin_x + 2.0 or (behind and screen_pos.x < viewport_size.x * 0.5):
			prefix = I18n.t("◀ [A/← 좌회전] ", "◀ [Turn Left A/←] ")
		elif screen_pos.x >= viewport_size.x - margin_x - 2.0 or (behind and screen_pos.x >= viewport_size.x * 0.5):
			prefix = I18n.t("[D/→ 우회전] ▶ ", "[Turn Right D/→] ▶ ")
		else:
			prefix = "▲ "

	var full_text := prefix + label_text
	var text_size := font.get_string_size(full_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
	var pill_size := Vector2(text_size.x + 24.0, 28.0)

	# Keep waypoint indicator & pill outside the actual top-left HUD card (flight_overview) and top-right radar (flight_chart)
	var ov_ctrl: Control = session.get("flight_overview") as Control
	var ch_ctrl: Control = session.get("flight_chart") as Control
	var ov_rect: Rect2 = ov_ctrl.get_rect() if is_instance_valid(ov_ctrl) else Rect2(30, 90, 620, 360)
	var ch_rect: Rect2 = ch_ctrl.get_rect() if is_instance_valid(ch_ctrl) else Rect2(viewport_size.x - 270, 90, 250, 240)
	var left_hud_right: float = ov_rect.end.x + 18.0
	var left_hud_bottom: float = ov_rect.end.y + 18.0
	var right_hud_left: float = ch_rect.position.x - 18.0
	var right_hud_bottom: float = ch_rect.end.y + 18.0

	if clamped.y - 48.0 < left_hud_bottom:
		var safe_min_x: float = left_hud_right + pill_size.x * 0.5
		var safe_max_x: float = (right_hud_left - pill_size.x * 0.5) if (session.seated and clamped.y - 48.0 < right_hud_bottom) else (viewport_size.x - 24.0 - pill_size.x * 0.5)
		if safe_max_x >= safe_min_x:
			clamped.x = clampf(clamped.x, safe_min_x, safe_max_x)
		else:
			clamped.y = maxf(clamped.y, left_hud_bottom + 48.0)

	# Flight-Path Vector (FPV) predictor reticle & guidance tether (Mulder, TU Delft 1999)
	if session.seated and session.aircraft.airborne and session.aircraft.airspeed > 8.0:
		var fpv_world: Vector3 = session.aircraft.global_position + session.aircraft.velocity * 2.4 + Vector3(0, 1.5, 0)
		if not cam.is_position_behind(fpv_world):
			var fpv_screen := cam.unproject_position(fpv_world)
			fpv_screen.x = clampf(fpv_screen.x, left_hud_right + 16.0, right_hud_left - 16.0)
			fpv_screen.y = clampf(fpv_screen.y, 120.0, viewport_size.y - 260.0)
			var fpv_col := Color(0.52, 0.96, 0.78, 0.85)
			# Soft guiding tether from velocity vector to active waypoint
			hud_marker.draw_dashed_line(fpv_screen, clamped, Color(accent.r, accent.g, accent.b, 0.42), 1.8, 7.0)
			hud_marker.draw_arc(fpv_screen, 10.0, 0.0, TAU, 24, fpv_col, 2.0)
			hud_marker.draw_line(fpv_screen + Vector2(-18, 0), fpv_screen + Vector2(-10, 0), fpv_col, 2.0)
			hud_marker.draw_line(fpv_screen + Vector2(10, 0), fpv_screen + Vector2(18, 0), fpv_col, 2.0)
			hud_marker.draw_line(fpv_screen + Vector2(0, -10), fpv_screen + Vector2(0, -17), fpv_col, 2.0)

	var r := 9.0 + sin(pulse * 1.4) * 1.5
	var diamond := PackedVector2Array([
		clamped + Vector2(0, -r),
		clamped + Vector2(r, 0),
		clamped + Vector2(0, r),
		clamped + Vector2(-r, 0),
		clamped + Vector2(0, -r)
	])
	hud_marker.draw_polyline(diamond, accent, 2.2)
	hud_marker.draw_circle(clamped, 3.0, accent)

	var pill_pos := clamped + Vector2(-pill_size.x * 0.5, -r - 34.0)
	pill_pos.y = clampf(pill_pos.y, 92.0, viewport_size.y - pill_size.y - 255.0)
	var min_pill_x: float = left_hud_right if (pill_pos.y + pill_size.y > ov_rect.position.y - 8.0 and pill_pos.y < left_hud_bottom) else 16.0
	var max_pill_x: float = (right_hud_left - pill_size.x) if (session.seated and pill_pos.y < right_hud_bottom) else (viewport_size.x - pill_size.x - 16.0)
	if max_pill_x >= min_pill_x:
		pill_pos.x = clampf(pill_pos.x, min_pill_x, max_pill_x)
	else:
		pill_pos.y = maxf(pill_pos.y, left_hud_bottom + 8.0)
		pill_pos.x = clampf(pill_pos.x, 16.0, viewport_size.x - pill_size.x - 16.0)
	var pill_rect := Rect2(pill_pos, pill_size)
	hud_marker.draw_rect(pill_rect, Color(0.02, 0.045, 0.05, 0.88), true)
	hud_marker.draw_rect(pill_rect, Color(accent.r, accent.g, accent.b, 0.65), false, 1.5)
	hud_marker.draw_string(
		font,
		pill_pos + Vector2(12.0, 19.0),
		full_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		accent
	)

