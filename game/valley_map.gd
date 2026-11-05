extends Control
## Live navigation radar chart with curved route waypoints, progress bar, and runway indicators.
const Airfields = preload("res://airfields.gd")
const I18n = preload("res://i18n.gd")
var session: Node

func point(at: Vector3) -> Vector2:
	return Vector2(118,136)+Vector2(at.x,at.z)*.088

func _process(_delta: float) -> void:
	visible = session.seated
	if visible:queue_redraw()

func _draw() -> void:
	if not session:return
	var font := I18n.get_ui_font()
	draw_style_box(session.world.button_style(Color(.025,.048,.052,.9)),Rect2(Vector2.ZERO,size))
	draw_string(font,Vector2(14,23),I18n.t("항로 레이더 (VALLEY RADAR)","VALLEY RADAR"),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("e6c791"))
	for y in [52,94,136,178]:draw_line(Vector2(14,y),Vector2(226,y),Color(.45,.6,.5,.12))
	for x in [36,78,120,162,204]:draw_line(Vector2(x,38),Vector2(x,208),Color(.45,.6,.5,.12))
	draw_string(font,Vector2(216,43),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("a8b9b0"))
	var destination: String = session.company.active_trip.get("destination",Airfields.other(session.company.current_airfield))
	var origin: String = session.company.current_airfield
	var aircraft_point := point(session.aircraft.position)

	# Draw curved sky-ring route on the radar
	if is_instance_valid(session.nav_guide):
		var pts: Array = session.nav_guide.ROUTES.get(destination, [])
		var wp_idx: int = session.nav_guide.waypoint_index
		var prev_pt := aircraft_point
		for i in range(wp_idx, pts.size()):
			var wp_p := point(pts[i])
			draw_dashed_line(prev_pt, wp_p, Color(.95, .78, .38, .55), 1.5, 4.0)
			var is_active := (i == wp_idx)
			var ring_col := Color("ffd584") if is_active else Color(.55, .86, .78, .65)
			draw_arc(wp_p, 4.5 if is_active else 3.2, 0.0, TAU, 16, ring_col, 1.6)
			prev_pt = wp_p
		draw_dashed_line(prev_pt, point(Airfields.DATA[destination].centre), Color(.55, .92, .78, .65), 1.5, 4.0)
	else:
		draw_dashed_line(aircraft_point,point(Airfields.DATA[destination].centre),Color(.85,.7,.38,.6),1,4)

	for id in Airfields.DATA:
		var data: Dictionary = Airfields.DATA[id]
		var p := point(data.centre)
		var half: float = data.length*.041
		var colour := Color("ebc37a") if id==destination else Color("97b0a4")
		draw_line(p-Vector2(half,0),p+Vector2(half,0),colour,3)
		var label_name: String = session.airfield_display_name(id) if session.has_method("airfield_display_name") else str(data.name)
		draw_string(font,p+Vector2(-40,17),label_name,HORIZONTAL_ALIGNMENT_LEFT,-1,11,colour)

	var direction := Vector2(sin(session.aircraft.heading),cos(session.aircraft.heading))
	var side := Vector2(-direction.y,direction.x)
	draw_colored_polygon(PackedVector2Array([aircraft_point+direction*7,aircraft_point-direction*5+side*4,aircraft_point-direction*2,aircraft_point-direction*5-side*4]),Color("fff0c9"))

	# Route completion progress bar at the bottom of the radar card
	var total_dist := Vector2(Airfields.DATA[destination].centre.x - Airfields.DATA[origin].centre.x, Airfields.DATA[destination].centre.z - Airfields.DATA[origin].centre.z).length()
	var rem_dist := Vector2(Airfields.DATA[destination].centre.x - session.aircraft.position.x, Airfields.DATA[destination].centre.z - session.aircraft.position.z).length()
	var prog := clampf(1.0 - rem_dist / maxf(total_dist, 1.0), 0.0, 1.0)
	var bar_bg := Rect2(Vector2(14, 213), Vector2(145, 7))
	draw_rect(bar_bg, Color(.12, .20, .19, .85), true)
	draw_rect(Rect2(Vector2(14, 213), Vector2(145 * prog, 7)), Color("e6c275"), true)
	draw_string(font, Vector2(166, 220), "%d%%" % int(round(prog * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e6c275"))
