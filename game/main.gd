extends Node3D
## Mossvale's compact first-route prototype and original procedural airfield.

const ROOT_OUT = "res://../art/previews/"
const CollisionBuilder = preload("res://airfield_collision.gd")
const PilotController = preload("res://first_person_controller.gd")
const Airfields = preload("res://airfields.gd")
const AircraftController = preload("res://aircraft_controller.gd")
const FlightSession = preload("res://flight_session.gd")
const I18n = preload("res://i18n.gd")
var aircraft: CharacterBody3D
var session: Node
var parked_fleet: Dictionary = {}
var parked_fleet_labels: Dictionary = {}
var camera: Camera3D
var pilot: CharacterBody3D
var walking_mode := false
var walk_button: Button
var lang_button: Button
var subtitle_label: Label
var caption_label: Label
var environment: Environment
var sun: DirectionalLight3D
var sky_material: ShaderMaterial
var ground_material: ShaderMaterial
var pavement_material: ShaderMaterial
var lamps: Array[OmniLight3D] = []
var grass_chunks: Array[MultiMeshInstance3D] = []
var rain: GPUParticles3D
var hud: CanvasLayer
var status_label: Label
var mode_label: Label
var time_button: Button
var rain_button: Button
var help_button: Button
var help_panel: PanelContainer
var help_title: Label
var help_shortcuts: GridContainer
var view_buttons: Array[Button] = []
const TIME_PRESETS: Array[Dictionary] = [
	{"name":"Morning", "clock":"07:00", "sky":Color("548aad"), "horizon":Color("c9d4cc"), "sun":Color("fff0ce"), "energy":1.35, "rotation":Vector3(-21,40,0), "ambient":.42, "fog":Color("b6c4c4"), "density":.00048, "lamps":.12},
	{"name":"Midday", "clock":"12:00", "sky":Color("4389ba"), "horizon":Color("b6d0d4"), "sun":Color("fff4df"), "energy":1.7, "rotation":Vector3(-63,-18,0), "ambient":.46, "fog":Color("9ebbc5"), "density":.0003, "lamps":0.0},
	{"name":"Golden hour", "clock":"18:00", "sky":Color("5787ad"), "horizon":Color("d8cbb5"), "sun":Color("ffd09a"), "energy":1.55, "rotation":Vector3(-18,-48,0), "ambient":.34, "fog":Color("b9bfb1"), "density":.00032, "lamps":.35},
	{"name":"Blue hour", "clock":"19:30", "sky":Color("263d61"), "horizon":Color("939caf"), "sun":Color("b5c9ec"), "energy":.23, "rotation":Vector3(-8,-68,0), "ambient":.55, "fog":Color("647d96"), "density":.0006, "lamps":3.5},
	{"name":"Night", "clock":"22:00", "sky":Color("102239"), "horizon":Color("475a73"), "sun":Color("abc6ed"), "energy":.12, "rotation":Vector3(-34,36,0), "ambient":.65, "fog":Color("344c65"), "density":.0005, "lamps":4.0}
]
var views: Array[Dictionary] = [
	{"name":"01  /  APRON", "pos":Vector3(8.5,3.0,13.5), "target":Vector3(-2.3,1.65,1.0)},
	{"name":"02  /  AIRCRAFT", "pos":Vector3(7.8,2.9,11), "target":Vector3(0,1.45,3)},
	{"name":"03  /  AIRFIELD", "pos":Vector3(36,22,44), "target":Vector3(-5,0,-18)},
	{"name":"04  /  HANGAR", "pos":Vector3(-5,4,7), "target":Vector3(-17,2.5,-8)}
]
var view_index := 0
var time_index := 2
var rain_enabled := false
var touring := false
var free_camera := false
var elapsed := 0.0
var capture_mode := false
var capture_stage := 0
var capture_clock := 0.0
var capture_busy := false
const CAPTURE_PLAN: Array[Dictionary] = [
	{"label":"golden_hour", "view":0, "time":2, "rain":false},
	{"label":"aircraft_detail", "view":1, "time":2, "rain":false},
	{"label":"rainy_evening", "view":0, "time":3, "rain":true},
	{"label":"airfield_overview", "view":2, "time":1, "rain":false},
	{"label":"hangar_detail", "view":3, "time":2, "rain":false},
	{"label":"morning", "view":0, "time":0, "rain":false},
	{"label":"blue_hour", "view":0, "time":3, "rain":false},
	{"label":"night", "view":0, "time":4, "rain":false}
]
var frame_times: Array[float] = []
var view_times: Array[float] = []
var view_metrics := {}
var last_metrics := 0.0
var cinematic := false
var reflection: ReflectionProbe
var reflection_refresh_pending := false
var atmosphere_revision := 0
var applied_time := -1
var applied_rain := false
var stress_mode := false
var stress_phase := 0
var stress_samples: Array[float] = []
var stress_results := {}
var terrain_noise := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	I18n.install_default_theme_font()
	DisplayServer.window_set_title("Mossvale Air Service")
	rng.seed = 91832
	cinematic = "--cinematic" in OS.get_cmdline_user_args() and RenderingServer.get_current_rendering_method()=="forward_plus"
	get_viewport().scaling_3d_scale = 1.0 if cinematic else .8
	terrain_noise.seed = 713
	terrain_noise.frequency = .0037
	terrain_noise.fractal_octaves = 4
	setup_environment()
	build_terrain()
	build_airfield()
	build_vegetation()
	setup_camera()
	pilot = CharacterBody3D.new()
	pilot.set_script(PilotController)
	add_child(pilot)
	setup_ui()
	setup_rain()
	set_weather(false)
	capture_mode = "--capture" in OS.get_cmdline_user_args()
	stress_mode = "--stress" in OS.get_cmdline_user_args()
	if capture_mode:configure_capture()
	set_walk_mode(not capture_mode and not stress_mode)
	session = Node.new()
	session.set_script(FlightSession)
	add_child(session)
	session.configure(self,aircraft)
	if capture_mode or stress_mode:session.hide_for_capture()
	print("BENCHMARK_READY renderer=",RenderingServer.get_current_rendering_method()," gpu=",RenderingServer.get_video_adapter_name())
	if "--walk-check" in OS.get_cmdline_user_args():
		var diagnostic := Node.new()
		diagnostic.set_script(load("res://walk_diagnostics.gd"))
		add_child(diagnostic)
		diagnostic.run.call_deferred(self)
	if "--flight-check" in OS.get_cmdline_user_args():
		var diagnostic := Node.new()
		diagnostic.set_script(load("res://flight_diagnostics.gd"))
		add_child(diagnostic)
		diagnostic.run.call_deferred(self)

func standard(color: Color, roughness: float = .7, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func box(label: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var shape := BoxMesh.new()
	shape.size = size
	node.mesh = shape
	node.material_override = material
	node.position = at
	if label in ["Runway centre dash","Runway edge","Taxi centreline","Parking T","Parking guide","Runway lamp base","Runway lamp lens","Runway threshold bar","Hangar festoon bulb","Birch centre dash","Birch runway edge","Birch threshold"]:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = 420.0
	add_child(node)
	if label in ["Runway","Apron","Taxi connection","Fence post","Fence rail","Light mast"]:
		CollisionBuilder.box_at(node,Vector3.ZERO,size)
	return node

func place_asset(path: String, at: Vector3, angle: float = 0.0) -> Node3D:
	var packed := load("res://assets/"+path+".glb") as PackedScene
	var item := packed.instantiate() as Node3D
	add_child(item)
	item.position = at
	item.rotation.y = angle
	if path=="mossvale_hangar":detail_hangar(item)
	if path in ["mossvale_hangar","airfield_props","fuel_pump"]:
		CollisionBuilder.asset_at(item)
	return item

func detail_hangar(node: Node) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		for i in range(instance.mesh.get_surface_count()):
			var original := instance.get_active_material(i) as StandardMaterial3D
			if original==null:continue
			var name_lower := original.resource_name.to_lower()
			if "cedar" in name_lower or "zinc" in name_lower:
				var material := ShaderMaterial.new()
				material.shader = load("res://shaders/material_detail.gdshader")
				material.set_shader_parameter("base_color",original.albedo_color)
				material.set_shader_parameter("wood",1.0 if "cedar" in name_lower else 0.0)
				material.set_shader_parameter("base_roughness",original.roughness)
				material.set_shader_parameter("metalness",original.metallic)
				instance.set_surface_override_material(i,material)
	for child in node.get_children():detail_hangar(child)

func setup_environment() -> void:
	var is_web := OS.has_feature("web")
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/valley_sky.gdshader")
	sky_material.set_shader_parameter("direct_sky", is_web)
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128 if is_web else Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC if is_web else Sky.PROCESS_MODE_INCREMENTAL
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = .42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.ssao_enabled = cinematic
	environment.ssao_radius = 2.0
	environment.ssao_intensity = 1.4
	environment.ssil_enabled = cinematic
	environment.ssil_intensity = .7
	environment.ssr_enabled = cinematic
	environment.glow_enabled = not is_web
	environment.glow_intensity = .56
	environment.glow_bloom = .055
	environment.fog_enabled = true
	environment.fog_density = .0005
	environment.fog_light_color = Color("b1bcac")
	environment.fog_sky_affect = .12
	environment.volumetric_fog_enabled = cinematic
	environment.volumetric_fog_density = .001
	environment.volumetric_fog_length = 200
	environment.volumetric_fog_albedo = Color("d3d7ca")
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24,-48,0)
	sun.light_color = Color("ffe1a4")
	sun.light_energy = 1.35
	sun.light_angular_distance = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 62 if is_web else 85
	sun.shadow_bias = .035
	sun.shadow_normal_bias = 1.2
	add_child(sun)

func height_at(x: float, z: float) -> float:
	var d := Vector2(x*.6,z).length()
	var blend := smoothstep(75.0,225.0,d)
	var hills := 16.0 + terrain_noise.get_noise_2d(x,z)*68.0
	var ridge := 63.0*exp(-pow((z+420.0)/240.0,2.0))*(.6+.4*sin(x*.008+1.0))
	return Airfields.flatten_height(x,z,maxf(-2.0,hills+ridge)*blend-.03)

func build_terrain() -> void:
	ground_material = ShaderMaterial.new()
	ground_material.shader = load("res://shaders/ground.gdshader")
	pavement_material = ShaderMaterial.new()
	pavement_material.shader = ground_material.shader
	pavement_material.set_shader_parameter("pavement",true)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 12.0
	for zi in range(-90,91):
		for xi in range(-90,91):
			var x := xi*step
			var z := zi*step
			var a := Vector3(x,height_at(x,z),z)
			var b := Vector3(x+step,height_at(x+step,z),z)
			var c := Vector3(x,height_at(x,z+step),z+step)
			var d := Vector3(x+step,height_at(x+step,z+step),z+step)
			for p in [a,b,c,b,d,c]: surface.add_vertex(p)
	surface.generate_normals()
	var terrain := MeshInstance3D.new()
	terrain.name = "Sculpted valley terrain"
	terrain.mesh = surface.commit()
	terrain.material_override = ground_material
	add_child(terrain)
	CollisionBuilder.mesh_at(terrain,terrain.mesh)
	# A coarse distant landscape closes the horizon seen from the aircraft.
	var distant := SurfaceTool.new()
	distant.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in range(-40,40):
		for xi in range(-40,40):
			if xi>=-10 and xi<10 and zi>=-10 and zi<10:continue
			var x := xi*100.0
			var z := zi*100.0
			for p in [Vector2(x,z),Vector2(x+100,z),Vector2(x,z+100),Vector2(x+100,z),Vector2(x+100,z+100),Vector2(x,z+100)]:
				distant.add_vertex(Vector3(p.x,height_at(p.x,p.y)-1.0,p.y))
	distant.generate_normals()
	var hills := MeshInstance3D.new()
	hills.name = "Distant valley"
	hills.mesh = distant.commit()
	hills.material_override = ground_material
	hills.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hills)
	box("Runway",Vector3(0,.012,-52),Vector3(580,.04,16),pavement_material)
	box("Apron",Vector3(-6,.015,-4),Vector3(54,.04,42),pavement_material)
	box("Taxi connection",Vector3(-4,.016,-31),Vector3(9,.042,27),pavement_material)
	var stripe := standard(Color("c6bfa0"),.85)
	for x in range(-270,271,24): box("Runway centre dash",Vector3(x,.04,-52),Vector3(9,.012,.3),stripe)
	for z in [-59.0,-45.0]: box("Runway edge",Vector3(0,.04,z),Vector3(560,.012,.12),stripe)
	var yellow := standard(Color("c4a84f"),.7)
	box("Taxi centreline",Vector3(-4,.044,-25),Vector3(.12,.012,37),yellow)
	for x in [-4.0,4.0]:
		box("Parking T",Vector3(x,.046,4.5),Vector3(2,.013,.09),yellow)
		box("Parking guide",Vector3(x,.046,3.5),Vector3(.09,.013,2),yellow)

func build_airfield() -> void:
	aircraft = CharacterBody3D.new()
	aircraft.set_script(AircraftController)
	add_child(aircraft)
	aircraft.ground_height = height_at
	aircraft.reset_at(Vector3(0,.065,3),-.23)
	place_asset("mossvale_hangar",Vector3(-19,0,-10))
	place_asset("airfield_props",Vector3(-19,0,-10))
	place_asset("fuel_pump",Vector3(-8,.04,-5),.1)
	place_asset("passenger_pavilion",Vector3(11.5,.015,-6.5),-PI*.5)
	build_parked_fleet()
	# A visible shallow threshold ramp makes the concrete hangar sill walkable.
	var ramp_surface := SurfaceTool.new()
	ramp_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-23,.036,-3.35)
	var b := Vector3(-15,.036,-3.35)
	var c := Vector3(-23,.164,-4.3)
	var d := Vector3(-15,.164,-4.3)
	for vertex in [a,c,b,b,c,d]:ramp_surface.add_vertex(vertex)
	ramp_surface.generate_normals()
	var ramp := MeshInstance3D.new()
	ramp.name = "Hangar threshold ramp"
	ramp.mesh = ramp_surface.commit()
	ramp.material_override = standard(Color("969c91"),.95)
	add_child(ramp)
	CollisionBuilder.mesh_at(ramp,ramp.mesh)
	var timber := standard(Color("6e6147"),.88)
	var dark := standard(Color("344440"),.5,.4)
	# Timber boundary fence; this is supporting layout, not a hero model.
	for x in range(-65,-30,4):
		box("Fence post",Vector3(x,.6,14),Vector3(.13,1.2,.13),timber)
		for y in [.48,.92]: box("Fence rail",Vector3(x+2,y,14),Vector3(4,.085,.065),timber)
	for x in [-24.0,-14.0]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x,4.4,-3.7)
		lamp.light_color = Color("ffbe6c")
		lamp.omni_range = 12
		lamp.light_energy = .2
		lamp.shadow_enabled = false
		add_child(lamp)
		lamps.append(lamp)
	# Apron lamp mast and inset runway lamps.
	box("Light mast",Vector3(17,3.7,-17),Vector3(.12,7.4,.12),dark)
	box("Light arm",Vector3(16.5,7.3,-17),Vector3(1.1,.08,.1),dark)
	var apron_light := OmniLight3D.new()
	apron_light.position = Vector3(16,7,-17)
	apron_light.light_color = Color("ffcf91")
	apron_light.omni_range = 30
	apron_light.shadow_enabled = false
	add_child(apron_light)
	lamps.append(apron_light)
	var lit := standard(Color("fae6b9"),.35)
	lit.emission_enabled = true
	lit.emission = Color("f2c36d")
	lit.emission_energy_multiplier = 2.2
	for x in range(-260,261,20):
		for z in [-61.0,-43.0]:
			box("Runway lamp base",Vector3(x,.13,z),Vector3(.22,.26,.22),dark)
			box("Runway lamp lens",Vector3(x,.29,z),Vector3(.15,.1,.15),lit)
	var approach_green := standard(Color("98f5c4"),.3)
	approach_green.emission_enabled = true
	approach_green.emission = Color("52e096")
	approach_green.emission_energy_multiplier = 2.6
	for x_end in [-278.0, 278.0]:
		for z_bar in [-58.0, -55.0, -52.0, -49.0, -46.0]:
			box("Runway threshold bar",Vector3(x_end,.16,z_bar),Vector3(.24,.18,.24),approach_green)
	# Warm festoon string bulbs along the hangar front eave for cosy evening ambience.
	for i in range(9):
		var bx := -23.5 + i * 1.125
		var sag := sin(float(i) / 8.0 * PI) * .18
		box("Hangar festoon bulb",Vector3(bx, 4.35 - sag, -3.55),Vector3(.09,.11,.09),lit)
	# Orange segmented windsock on a real mast, animated as one lightweight mesh.
	var mast := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = .035
	cylinder.bottom_radius = .065
	cylinder.height = 5
	mast.mesh = cylinder
	mast.material_override = dark
	mast.position = Vector3(23,2.5,-28)
	add_child(mast)
	var orange := standard(Color("dc733a"),.85)
	var white := standard(Color("e6dabc"),.85)
	for i in range(5):
		var sock := MeshInstance3D.new()
		var segment := CylinderMesh.new()
		segment.top_radius = .3-i*.042
		segment.bottom_radius = .3-(i+1)*.042
		segment.height = .34
		sock.mesh = segment
		sock.material_override = orange if i%2==0 else white
		sock.position = Vector3(23.15+i*.33,4.95-i*.08,-28)
		sock.rotation.z = PI/2-.2
		add_child(sock)
	build_birch_hollow()

func build_birch_hollow() -> void:
	var centre := Vector3(-220,24,-640)
	box("Runway",centre+Vector3(0,.012,0),Vector3(500,.04,18),pavement_material)
	box("Apron",Vector3(-210,24.015,-604),Vector3(44,.04,35),pavement_material)
	box("Taxi connection",Vector3(-210,24.016,-623),Vector3(10,.042,38),pavement_material)
	var stripe := standard(Color("d0c9ae"),.85)
	for x in range(-450,21,24):box("Birch centre dash",Vector3(x,24.045,-640),Vector3(9,.012,.3),stripe)
	for z in [-648.0,-632.0]:box("Birch runway edge",Vector3(-220,24.045,z),Vector3(480,.012,.12),stripe)
	for x in [-453.0,13.0]:
		for z in [-646.0,-643.0,-640.0,-637.0,-634.0]:box("Birch threshold",Vector3(x,24.047,z),Vector3(12,.015,.7),stripe)
	# Reuse the existing Blender assets; the nameboard is a separate airfield sign.
	place_asset("fuel_pump",Vector3(-223,24.04,-600),PI/2)
	place_asset("airfield_props",Vector3(-226,24,-611),PI/2)
	place_asset("passenger_pavilion",Vector3(-196,24.015,-604),-PI*.5)
	var bh_plane_a := place_asset("osprey_mv6",Vector3(-196,24.065,-591),-.45)
	_disable_showcase_shadows(bh_plane_a)
	var bh_plane_b := place_asset("albatross_mv10",Vector3(-224,24.065,-591),.42)
	_disable_showcase_shadows(bh_plane_b)
	var timber := standard(Color("5b5a40"),.9)
	for x in [-218.0,-210.0]:box("Fence post",Vector3(x,25.4,-588),Vector3(.15,2.8,.15),timber)
	box("Birch nameboard",Vector3(-214,26.05,-588),Vector3(9,1.2,.15),standard(Color("263d38")))
	var sign := Label3D.new()
	sign.text = "B I R C H   H O L L O W"
	sign.font_size = 72
	sign.pixel_size = .008
	sign.position = Vector3(-214,26.05,-588.1)
	sign.rotation.y = PI
	sign.modulate = Color("ebdfbf")
	add_child(sign)
	var marker := standard(Color("eed49b"),.4)
	marker.emission_enabled = true
	marker.emission = Color("dcb66e")
	for x in range(-450,20,35):
		for z in [-650,-630]:box("Runway lamp base",Vector3(x,24.15,z),Vector3(.2,.3,.2),marker)
	build_outlying_airfields(stripe, timber, marker)

func build_outlying_airfields(stripe: StandardMaterial3D, timber: StandardMaterial3D, marker: StandardMaterial3D) -> void:
	# 3. Pine Ridge Strip (East Highland Plateau at y = 36)
	var pr := Vector3(420,36,-520)
	box("PR Runway",pr+Vector3(0,.012,0),Vector3(460,.04,16),pavement_material)
	box("PR Apron",Vector3(430,36.015,-486),Vector3(44,.04,34),pavement_material)
	box("PR Taxi",Vector3(430,36.016,-504),Vector3(10,.042,36),pavement_material)
	for x in range(210,631,24):box("PR dash",Vector3(x,36.045,-520),Vector3(9,.012,.3),stripe)
	for z in [-527.5,-512.5]:box("PR edge",Vector3(420,36.045,z),Vector3(440,.012,.12),stripe)
	place_asset("fuel_pump",Vector3(417,36.04,-482),PI/2)
	place_asset("passenger_pavilion",Vector3(444,36.015,-486),-PI*.5)
	for x in [422.0,430.0]:box("PR post",Vector3(x,37.4,-472),Vector3(.15,2.8,.15),timber)
	box("PR nameboard",Vector3(426,38.05,-472),Vector3(9,1.2,.15),standard(Color("263d38")))
	var pr_sign := Label3D.new()
	pr_sign.text = "P I N E   R I D G E"
	pr_sign.font_size = 72
	pr_sign.pixel_size = .008
	pr_sign.position = Vector3(426,38.05,-472.1)
	pr_sign.rotation.y = PI
	pr_sign.modulate = Color("ebdfbf")
	add_child(pr_sign)
	for x in range(210,631,35):
		for z in [-529,-511]:box("PR lamp",Vector3(x,36.15,z),Vector3(.2,.3,.2),marker)

	# 4. Mirror Lake Landing (Southwest Lakeside Meadow at y = 12)
	var ml := Vector3(-280,12,380)
	box("ML Runway",ml+Vector3(0,.012,0),Vector3(440,.04,16),pavement_material)
	box("ML Apron",Vector3(-270,12.015,414),Vector3(44,.04,34),pavement_material)
	box("ML Taxi",Vector3(-270,12.016,396),Vector3(10,.042,36),pavement_material)
	for x in range(-480,-79,24):box("ML dash",Vector3(x,12.045,380),Vector3(9,.012,.3),stripe)
	for z in [372.5,387.5]:box("ML edge",Vector3(-280,12.045,z),Vector3(420,.012,.12),stripe)
	place_asset("fuel_pump",Vector3(-283,12.04,418),PI/2)
	place_asset("passenger_pavilion",Vector3(-256,12.015,414),-PI*.5)
	for x in [-278.0,-270.0]:box("ML post",Vector3(x,13.4,428),Vector3(.15,2.8,.15),timber)
	box("ML nameboard",Vector3(-274,14.05,428),Vector3(9,1.2,.15),standard(Color("263d38")))
	var ml_sign := Label3D.new()
	ml_sign.text = "M I R R O R   L A K E"
	ml_sign.font_size = 72
	ml_sign.pixel_size = .008
	ml_sign.position = Vector3(-274,14.05,427.9)
	ml_sign.rotation.y = PI
	ml_sign.modulate = Color("ebdfbf")
	add_child(ml_sign)
	for x in range(-480,-79,35):
		for z in [371,389]:box("ML lamp",Vector3(x,12.15,z),Vector3(.2,.3,.2),marker)

func _disable_showcase_shadows(node: Node) -> void:
	if node is MeshInstance3D:
		var m := node as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visibility_range_end = 520.0
	for child in node.get_children():
		_disable_showcase_shadows(child)

func build_parked_fleet() -> void:
	var catalog_assets := {
		"heron": "heron_mv4",
		"osprey": "osprey_mv6",
		"albatross": "albatross_mv10",
		"skywhale": "skywhale_mv16"
	}
	var label_heights := {
		"heron": 3.4,
		"osprey": 3.8,
		"albatross": 4.3,
		"skywhale": 5.0
	}
	for id: String in ["heron", "osprey", "albatross", "skywhale"]:
		var node := place_asset(catalog_assets[id], Vector3(0, -50, 0), 0.0)
		node.name = "ParkedFleet_" + id
		_disable_showcase_shadows(node)
		var lbl := Label3D.new()
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = false
		lbl.fixed_size = true
		lbl.pixel_size = 0.00085
		lbl.font_size = 22
		lbl.outline_size = 7
		lbl.visibility_range_end = 10.5
		lbl.visibility_range_end_margin = 2.0
		lbl.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		lbl.modulate = Color(1.0, 0.93, 0.72, 0.96)
		lbl.outline_modulate = Color(0.02, 0.05, 0.06, 0.95)
		lbl.font = I18n.get_ui_font()
		lbl.position = Vector3(0.0, float(label_heights[id]), 0.0)
		node.add_child(lbl)
		parked_fleet[id] = node
		parked_fleet_labels[id] = lbl
	update_parked_fleet("heron")

func update_parked_fleet(active_id: String) -> void:
	var current_field := "mossvale"
	var owned_map: Dictionary = {}
	if session and session.get("company") != null:
		var comp: Object = session.get("company") as Object
		if comp != null:
			current_field = str(comp.get("current_airfield"))
			if comp.get("owned_aircraft") is Dictionary:
				owned_map = comp.get("owned_aircraft")
	var bays: Array[Dictionary] = [
		{"pos": Vector3(-12.5, 0.065, 8.5), "yaw": 0.38},
		{"pos": Vector3(6.5, 0.065, -17.5), "yaw": -0.42},
		{"pos": Vector3(-16.5, 0.065, -21.5), "yaw": 0.28}
	]
	if current_field == "birch_hollow":
		bays = [
			{"pos": Vector3(-193.5, 24.065, -591.0), "yaw": -0.42},
			{"pos": Vector3(-209.5, 24.065, -590.5), "yaw": 0.0},
			{"pos": Vector3(-225.5, 24.065, -591.0), "yaw": 0.42}
		]
	elif current_field == "pine_ridge":
		bays = [
			{"pos": Vector3(446.5, 36.065, -475.0), "yaw": -0.42},
			{"pos": Vector3(430.5, 36.065, -474.5), "yaw": 0.0},
			{"pos": Vector3(414.5, 36.065, -475.0), "yaw": 0.42}
		]
	elif current_field == "mirror_lake":
		bays = [
			{"pos": Vector3(-253.5, 12.065, 425.0), "yaw": -0.42},
			{"pos": Vector3(-269.5, 12.065, 425.5), "yaw": 0.0},
			{"pos": Vector3(-285.5, 12.065, 425.0), "yaw": 0.42}
		]
	var specs := {
		"heron": ["MV-4 Heron", 3, 80, "$0"],
		"osprey": ["MV-6 Osprey", 5, 120, "$1,100"],
		"albatross": ["MV-10 Albatross", 9, 200, "$1,800"],
		"skywhale": ["MV-16 Skywhale", 15, 320, "$3,200"]
	}
	var bay_idx := 0
	for id: String in ["heron", "osprey", "albatross", "skywhale"]:
		var node: Node3D = parked_fleet.get(id) as Node3D
		var lbl: Label3D = parked_fleet_labels.get(id) as Label3D
		if node == null:
			continue
		if id == active_id:
			node.visible = false
			node.position = Vector3(0, -50, 0)
		else:
			var bay: Dictionary = bays[mini(bay_idx, bays.size() - 1)]
			bay_idx += 1
			node.position = bay["pos"]
			node.rotation.y = float(bay["yaw"])
			node.visible = true
			if lbl:
				var info: Array = specs.get(id, [id, 3, 80, "$0"])
				var is_owned: bool = id == "heron" or owned_map.has(id)
				if is_owned:
					lbl.modulate = Color(0.68, 1.0, 0.80, 0.96)
					lbl.text = I18n.t(
						"◆ %s (%d인승 · %dL)\n✓ 보유 중 · [격납고]에서 전환" % [info[0], info[1], info[2]],
						"◆ %s (%d seats · %dL)\n✓ OWNED · Switch in [Fleet]" % [info[0], info[1], info[2]]
					)
				else:
					lbl.modulate = Color(1.0, 0.93, 0.72, 0.96)
					lbl.text = I18n.t(
						"◆ %s (%d인승 · %dL · %s)\n[격납고]에서 구매/탑승" % [info[0], info[1], info[2], info[3]],
						"◆ %s (%d seats · %dL · %s)\nBuy/Fly in [Fleet]" % [info[0], info[1], info[2], info[3]]
					)

func collect_meshes(root: Node3D, node: Node, groups: Dictionary) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		var relative: Transform3D = root.global_transform.affine_inverse()*instance.global_transform
		for s in range(instance.mesh.get_surface_count()):
			var material := instance.get_active_material(s)
			var key := str(material.get_instance_id())
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = {"tool":st,"material":material}
			groups[key].tool.append_from(instance.mesh,s,relative)
	for child in node.get_children(): collect_meshes(root,child,groups)

func instance_asset(path: String, placements: Array[Transform3D]) -> void:
	var source := place_asset(path,Vector3.ZERO)
	var groups := {}
	collect_meshes(source,source,groups)
	# Bake material colours into vertices: one material for the complete tree.
	# Chunk by location so the GPU doesn't draw the entire forest from every view.
	var bake := SurfaceTool.new()
	bake.begin(Mesh.PRIMITIVE_TRIANGLES)
	for entry in groups.values():
		var surface_mesh: ArrayMesh = entry.tool.commit()
		var arrays := surface_mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		bake.set_color(entry.material.albedo_color)
		if indices.is_empty():
			for i in range(vertices.size()):
				bake.set_normal(normals[i]);bake.add_vertex(vertices[i])
		else:
			for index in indices:
				bake.set_normal(normals[index]);bake.add_vertex(vertices[index])
	var combined := bake.commit()
	var vertex_material := standard(Color.WHITE,.9)
	vertex_material.vertex_color_use_as_albedo = true
	vertex_material.vertex_color_is_srgb = true
	combined.surface_set_material(0,vertex_material)
	var chunks := {}
	for transform in placements:
		var key := Vector2i(floori(transform.origin.x/80),floori(transform.origin.z/80))
		if not chunks.has(key):chunks[key]=[]
		chunks[key].append(transform)
	for key in chunks:
		var transforms: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = combined
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):mm.set_instance_transform(i,transforms[i])
		var draw := MultiMeshInstance3D.new()
		draw.multimesh = mm
		if Vector2(key).length()>2:draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		draw.visibility_range_end = 800
		add_child(draw)
	source.queue_free()

func excluded(x: float,z: float) -> bool:
	return (absf(x)<320 and absf(z+52)<23) or (x>-30 and x<15 and z>-20 and z<18) or (absf(x+4)<6 and z>-45 and z<-15) or (absf(x+220)<280 and absf(z+630)<67) or (absf(x-420)<260 and absf(z+505)<55) or (absf(x+280)<250 and absf(z-395)<55)

func build_vegetation() -> void:
	var placements: Array[Transform3D] = []
	for i in range(360):
		var x := rng.randf_range(-450,450)
		var z := rng.randf_range(-370,260)
		if excluded(x,z) or (absf(x)<48 and z>-95 and z<65): continue
		var scale := rng.randf_range(.85,1.65)
		placements.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale),Vector3(x,height_at(x,z),z)))
	# A wooded boundary, rather than evenly spaced isolated trees on every hill.
	for i in range(65):
		var x := rng.randf_range(-150,130)
		var z := rng.randf_range(-150,-105)
		var scale := rng.randf_range(1.1,1.7)
		placements.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale),Vector3(x,height_at(x,z),z)))
	for pos in [Vector3(-40,0,-17),Vector3(-32,0,8),Vector3(22,0,5),Vector3(34,0,-12),Vector3(38,0,6),Vector3(-47,0,-34)]:
		placements.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*1.05),pos))
	for i in range(95):
		var x := rng.randf_range(-570,130)
		var z := rng.randf_range(-800,-480)
		if excluded(x,z):continue
		var tree_scale := rng.randf_range(.9,1.55)
		placements.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*tree_scale),Vector3(x,height_at(x,z),z)))
	instance_asset("birch",placements)
	for placement in placements:CollisionBuilder.tree_at(self,placement)
	placements = []
	for i in range(65):
		var x := rng.randf_range(-130,130)
		var z := rng.randf_range(-130,130)
		if excluded(x,z) or Vector2(x,z).length()<23:continue
		placements.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(.3,1.4)),Vector3(x,height_at(x,z),z)))
	instance_asset("boulder",placements)
	for placement in placements:CollisionBuilder.rock_at(self,placement)
	# Grass clumps are tapered blades; chunked to permit spatial culling and tuned for high FPS on Web & Desktop.
	var is_web := OS.has_feature("web")
	var blade_count := 4 if is_web else 5
	var clump_density := 420 if is_web else (950 if cinematic else 660)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(blade_count):
		var a := blade*2.399
		var p := Vector3(cos(a),0,sin(a))*.1
		var w := Vector3(cos(a+.8),0,sin(a+.8))*.023
		var h := .36+blade*.038
		var tip := p+Vector3(cos(a)*.13,h,sin(a)*.13)
		for data in [[p-w,Vector2(0,0)],[p+w,Vector2(1,0)],[p+w*.52+Vector3(0,h*.58,0),Vector2(1,.58)], [p-w,Vector2(0,0)],[p+w*.52+Vector3(0,h*.58,0),Vector2(1,.58)],[p-w*.52+Vector3(0,h*.58,0),Vector2(0,.58)], [p-w*.52+Vector3(0,h*.58,0),Vector2(0,.58)],[p+w*.52+Vector3(0,h*.58,0),Vector2(1,.58)],[tip,Vector2(.5,1)]]:
			st.set_uv(data[1]);st.set_normal(Vector3.UP);st.add_vertex(data[0])
	var grass_mesh := st.commit()
	var grass_material := ShaderMaterial.new()
	grass_material.shader = load("res://shaders/grass.gdshader")
	grass_mesh.surface_set_material(0,grass_material)
	for cz in range(-3,3):
		for cx in range(-3,3):
			var transforms: Array[Transform3D] = []
			for i in range(clump_density):
				var x := cx*24.0+rng.randf()*24.0
				var z := cz*24.0+rng.randf()*24.0
				if excluded(x,z):continue
				var size := rng.randf_range(.72,1.35)
				transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(size,size,size)),Vector3(x,height_at(x,z),z)))
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = grass_mesh
			mm.instance_count = transforms.size()
			for i in range(transforms.size()):
				mm.set_instance_transform(i,transforms[i])
				mm.set_instance_custom_data(i,Color(rng.randf(),0,0,1))
			var chunk := MultiMeshInstance3D.new()
			chunk.multimesh = mm
			chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk.visibility_range_end = 78 if is_web else 96
			chunk.visibility_range_end_margin = 14
			add_child(chunk)
			grass_chunks.append(chunk)

func setup_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 55
	camera.near = .12
	camera.far = 2000
	add_child(camera)
	camera.position = views[0].pos
	camera.look_at(views[0].target)

func label_at(parent: Node, text: String, pos: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	label.add_theme_color_override("font_shadow_color",Color(0,0,0,.65))
	label.add_theme_constant_override("shadow_offset_y",1)
	label.add_theme_color_override("font_outline_color",Color(0.02, 0.05, 0.06, 0.45))
	label.add_theme_constant_override("outline_size",1)
	parent.add_child(label)
	return label

func button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(0.82, 0.73, 0.54, 0.24)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func ui_button(title: String, width: float = 0.0) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(width,42)
	button.add_theme_font_size_override("font_size",14)
	button.add_theme_color_override("font_color",Color("e0e5dc"))
	button.add_theme_color_override("font_hover_color",Color("fff3d6"))
	button.add_theme_color_override("font_pressed_color",Color("f0cf91"))
	button.add_theme_color_override("font_disabled_color",Color("aab8ad"))
	button.add_theme_stylebox_override("normal",button_style(Color(.035,.064,.067,.94)))
	button.add_theme_stylebox_override("hover",button_style(Color(.13,.19,.18,.98)))
	button.add_theme_stylebox_override("pressed",button_style(Color(.16,.23,.21,.98)))
	button.add_theme_stylebox_override("disabled",button_style(Color(.035,.064,.067,.80)))
	var focus := button_style(Color(0,0,0,0))
	focus.set_border_width_all(2)
	focus.border_color = Color("d8b780")
	button.add_theme_stylebox_override("focus",focus)
	# Keyboard shortcuts remain active after clicking, while Tab still focuses controls.
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	return button

func ui_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func setup_ui() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	label_at(root,"M O S S V A L E",Vector2(30,24),21,Color("f2e8d0"))
	subtitle_label = label_at(root,I18n.t("모스베일 항공 서비스   /   첫 번째 정기 노선","AIR SERVICE    /    FIRST ROUTE"),Vector2(31,54),13,Color("e4ede7"))
	var atmosphere := HBoxContainer.new()
	root.add_child(atmosphere)
	atmosphere.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	atmosphere.offset_left = -520
	atmosphere.offset_right = -28
	atmosphere.offset_top = 28
	atmosphere.add_theme_constant_override("separation",6)
	lang_button = ui_button("",72)
	lang_button.tooltip_text = "Switch language (한국어 / English) · L"
	lang_button.pressed.connect(toggle_language)
	atmosphere.add_child(lang_button)
	var previous := ui_button("‹",42)
	previous.tooltip_text = "Previous time of day · Shift + T"
	previous.pressed.connect(func():cycle_time(-1))
	atmosphere.add_child(previous)
	time_button = ui_button("",240)
	time_button.tooltip_text = "Next time of day · T\nMorning → Midday → Golden hour → Blue hour → Night"
	time_button.pressed.connect(cycle_time)
	atmosphere.add_child(time_button)
	rain_button = ui_button("",116)
	rain_button.toggle_mode = true
	rain_button.tooltip_text = "Toggle rain without changing the time · R"
	rain_button.pressed.connect(func():set_weather(not rain_enabled))
	atmosphere.add_child(rain_button)
	var bottom := PanelContainer.new()
	root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 28
	bottom.offset_right = -28
	bottom.offset_top = -86
	bottom.offset_bottom = -26
	bottom.add_theme_stylebox_override("panel",button_style(Color(.025,.048,.052,.91)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	bottom.add_child(row)
	var caption := VBoxContainer.new()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caption.custom_minimum_size.x = 150
	caption.add_theme_constant_override("separation",2)
	row.add_child(caption)
	mode_label = ui_label("Apron",17,Color("f0e5cc"))
	mode_label.clip_text = true
	caption.add_child(mode_label)
	caption_label = ui_label("MV–4 HERON   ·   FOUR SEATS",13,Color("dce8e0"))
	caption_label.clip_text = true
	caption.add_child(caption_label)
	walk_button = ui_button("Photo mode",142)
	walk_button.toggle_mode = true
	walk_button.tooltip_text = "Open Photo mode · the camera moves separately while your pilot stays here · C"
	walk_button.pressed.connect(func():set_walk_mode(not walking_mode))
	row.add_child(walk_button)
	for i in range(views.size()):
		var b := ui_button(["Apron","Aircraft","Airfield","Hangar"][i],96)
		b.toggle_mode = true
		b.tooltip_text = "View " + str(i+1) + " · V cycles views"
		b.pressed.connect(func():select_view(i))
		row.add_child(b)
		view_buttons.append(b)
	var gap := Control.new()
	gap.custom_minimum_size.x = 14
	row.add_child(gap)
	status_label = ui_label("— FPS",11,Color("91a99e"))
	status_label.custom_minimum_size.x = 60
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.visible = capture_mode or stress_mode
	row.add_child(status_label)
	help_button = ui_button("Controls  ?",106)
	help_button.toggle_mode = true
	help_button.tooltip_text = "Show controls · F1"
	help_button.pressed.connect(toggle_help)
	row.add_child(help_button)
	help_panel = PanelContainer.new()
	root.add_child(help_panel)
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	help_panel.offset_left = -548
	help_panel.offset_right = -28
	help_panel.offset_top = -456
	help_panel.offset_bottom = -102
	help_panel.add_theme_stylebox_override("panel",button_style(Color(.025,.048,.052,.97)))
	var help_content := VBoxContainer.new()
	help_content.add_theme_constant_override("separation",10)
	help_panel.add_child(help_content)
	help_title = ui_label("On foot · Third person",18,Color("f0dfbb"))
	help_content.add_child(help_title)
	help_shortcuts = GridContainer.new()
	help_shortcuts.columns = 2
	help_shortcuts.add_theme_constant_override("h_separation",22)
	help_shortcuts.add_theme_constant_override("v_separation",7)
	help_content.add_child(help_shortcuts)
	help_panel.hide()
	refresh_ui()

func toggle_language() -> void:
	I18n.toggle_lang()
	if session and session.has_method("refresh_language"):
		session.refresh_language()
	refresh_ui()

func refresh_help() -> void:
	if not help_shortcuts:return
	for child in help_shortcuts.get_children():
		help_shortcuts.remove_child(child)
		child.queue_free()
	var entries: Array
	if session and session.seated:
		help_title.text = I18n.t("비행 조작법 · " + session.aircraft_name() + " (3인칭 고정)", "Flying · "+session.aircraft_name()+" (Third person)")
		entries = [
			[I18n.t("W / S", "W / S"), I18n.t("엔진 자동 시동 및 가속 / 감속", "Auto-start engine & increase / reduce power")],
			[I18n.t("A / D  또는  ← / →", "A / D  or  Left / Right"), I18n.t("좌우 방향 전환 (지상 조향 및 공중 선회)", "Steer on ground and bank/turn in flight")],
			[I18n.t("↑ 위 화살표 / ↓ 아래 화살표", "Up (↑) / Down (↓) arrows"), I18n.t("[↑] 고도 상승(위로)  /  [↓] 고도 하강(내려가기)", "[↑] Climb altitude (nose up) / [↓] Descend altitude (nose down)")],
			[I18n.t("F", "F"), I18n.t("활주로 출발선에 즉시 정렬 (지상에서)", "Line up directly on the runway (on ground)")],
			[I18n.t("Space", "Space"), I18n.t("활주로 착륙 후 브레이크 (이륙 시엔 부양 보조)", "Wheel brake on ground / takeoff lift assist")],
			[I18n.t("E · B · Home", "E · B · Home"), I18n.t("정차 후 하차 · 운항 데스크 · 비상 복귀", "Leave aircraft · flight desk · recovery")],
			[I18n.t("T / Shift+T · R", "T / Shift + T · R"), I18n.t("시간대 변경 · 비 내리기 토글", "Time forward / back · rain")],
			[I18n.t("L · F1 · H · F11", "L · F1 · H · F11"), I18n.t("언어(한/영) · 도움말 · HUD 숨김 · 전체화면", "Language · Help · HUD · full screen")]
		]
	elif walking_mode:
		help_title.text = I18n.t("도보 조작법 · 3인칭 고정 시점", "On foot · Third person")
		entries = [
			[I18n.t("WASD / 방향키 · Shift", "WASD / Arrows · Shift"), I18n.t("걷기 (자동 방향 회전) · 빠르게 달리기", "Walk · run")],
			[I18n.t("마우스 우클릭 드래그", "Hold RMB"), I18n.t("주변 둘러보기", "Look around")],
			[I18n.t("B", "B"), I18n.t("운항 데스크 열기 (승객 좌석 판매 · 연료 주유 · 기체 구매)", "Open flight desk (sell seats, refuel, fleet)")],
			[I18n.t("E", "E"), I18n.t("비행기 탑승하기", "Board aircraft")],
			[I18n.t("Space · Home", "Space · Home"), I18n.t("점프 · 비행장 주기장으로 복귀", "Jump · return to airfield")],
			[I18n.t("T / Shift+T · R", "T / Shift + T · R"), I18n.t("시간대 변경 · 비 내리기 토글", "Time forward / back · rain")],
			[I18n.t("L · F1 · H · F11", "L · F1 · H · F11"), I18n.t("언어(한/영) · 도움말 · HUD 숨김 · 전체화면", "Language · Help · HUD · full screen")]
		]
	else:
		help_title.text = I18n.t("Photo mode · 비행장 전경 카메라", "Photo mode · Pilot stays in place")
		entries = [
			[I18n.t("C · 도보 복귀", "C · Return to walking"), I18n.t("파일럿 3인칭 도보 시점으로 복귀", "Resume at your pilot's location")],
			[I18n.t("하단 뷰 버튼 · V", "Fixed view buttons · V"), I18n.t("고정 전경 뷰 선택 / 순환", "Choose / cycle composed views")],
			[I18n.t("마우스 우클릭 유지", "Hold right mouse"), I18n.t("자유 카메라 시점 회전", "Look freely with the photo camera")],
			[I18n.t("WASD · Q / E · Shift", "WASD · Q / E · Shift"), I18n.t("자유 카메라 이동 · 상하 · 가속", "Move free camera · down / up · faster")],
			[I18n.t("Space", "Space"), I18n.t("전경 카메라 투어 시작 / 정지", "Start / stop a gentle fixed-view tour")],
			[I18n.t("Esc", "Esc"), I18n.t("마우스 커서 표시", "Release the mouse")],
			[I18n.t("T / Shift+T · R", "T / Shift + T · R"), I18n.t("시간대 변경 · 비 토글", "Time forward / back · rain")],
			[I18n.t("L · F1 · H · F11", "L · F1 · H · F11"), I18n.t("언어(한/영) · 도움말 · HUD · 전체화면", "Language · Help · HUD · full screen")]
		]
	for entry in entries:
		help_shortcuts.add_child(ui_label(entry[0],12,Color("e6c791")))
		help_shortcuts.add_child(ui_label(entry[1],12,Color("c1cfc7")))

func toggle_help() -> void:
	help_panel.visible = not help_panel.visible
	help_button.set_pressed_no_signal(help_panel.visible)
	pilot.controls_blocked = help_panel.visible
	if help_panel.visible:Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if session:
		if help_panel.visible:
			session.panel.hide()
			session.fleet_panel.hide()
		session.update_blocks()

func refresh_ui() -> void:
	if time_button:
		if subtitle_label:
			subtitle_label.text = I18n.t("모스베일 항공 서비스   /   첫 번째 정기 노선","AIR SERVICE    /    FIRST ROUTE")
		if lang_button:
			lang_button.text = "한 / EN"
		var preset := TIME_PRESETS[time_index]
		var time_ko_list: Array[String] = ["아침 (Morning)","정오 (Midday)","노을 (Golden hour)","황혼 (Blue hour)","밤 (Night)"]
		var time_ko: String = time_ko_list[time_index]
		time_button.text = "%s   ·   %s   ›" % [preset.clock, I18n.t(time_ko, str(preset.name))]
		rain_button.text = I18n.t("비: 켜짐" if rain_enabled else "비: 꺼짐", "Rain: on" if rain_enabled else "Rain: off")
		rain_button.set_pressed_no_signal(rain_enabled)
		help_button.text = I18n.t("조작법  ?", "Controls  ?")
		var photo_mode: bool = not walking_mode and not (session and session.seated)
		var view_names_ko: Array[String] = ["주기장","항공기","비행장","격납고"]
		var view_names_en: Array[String] = ["Apron","Aircraft","Airfield","Hangar"]
		if photo_mode:
			var vname: String = I18n.t(view_names_ko[view_index], view_names_en[view_index])
			mode_label.text = I18n.t("Photo mode · 자유 카메라" if free_camera else "Photo mode · %s 뷰" % vname, "Photo mode · Free camera" if free_camera else "Photo mode · "+view_names_en[view_index]+" view")
			if touring:
				mode_label.text = I18n.t("Photo mode · %s 투어 중" % vname, "Photo mode · Touring "+view_names_en[view_index])
			caption_label.text = I18n.t("우클릭 시점회전   ·   WASD + Q/E 이동   ·   SPACE 투어   ·   V 다음 뷰", "HOLD RMB LOOK   ·   WASD + Q/E MOVE   ·   SPACE TOUR   ·   V NEXT VIEW")
		elif session and session.seated:
			mode_label.text = I18n.t("비행 중 · %s (3인칭 고정)" % session.aircraft_name(), "Flying · "+session.aircraft_name()+" · Third person")
			caption_label.text = I18n.t("[W/S] 가속·감속   ·   [A/D·←/→] 좌우 선회   ·   [↑] 고도 상승(위로)   ·   [↓] 고도 하강(내려가기)   ·   [Space] 브레이크", "W/S POWER   ·   A/D STEER   ·   [↑] CLIMB UP   ·   [↓] DESCEND DOWN   ·   SPACE BRAKE")
		else:
			mode_label.text = I18n.t("도보 이동 · 3인칭 고정", "On foot · Third person")
			caption_label.text = I18n.t("[WASD/방향키] 이동   ·   [Shift] 달리기   ·   [B] 승객 예약/주유   ·   [E] 비행기 탑승", "WASD MOVE   ·   SHIFT RUN   ·   B FLIGHT DESK   ·   E BOARD AIRCRAFT")
		walk_button.text = I18n.t("Return to walking" if not I18n.is_ko() else "3인칭 도보 복귀", "Return to walking") if photo_mode else I18n.t("전경 카메라", "Photo mode")
		walk_button.tooltip_text = "Return to walking · C" if photo_mode else "Open Photo mode · C"
		walk_button.set_pressed_no_signal(photo_mode)
		walk_button.visible = photo_mode
		for i in range(view_buttons.size()):
			view_buttons[i].text = I18n.t(view_names_ko[i], view_names_en[i])
			view_buttons[i].visible = photo_mode
			view_buttons[i].set_pressed_no_signal(i==view_index and not free_camera and not walking_mode)
		status_label.visible = capture_mode or stress_mode
		if aircraft:
			update_parked_fleet(aircraft.aircraft_id)
		refresh_help()

func setup_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 1000
	rain.lifetime = 1.6
	rain.visibility_aabb = AABB(Vector3(-55,-25,-55),Vector3(110,80,110))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(30,2,30)
	process.direction = Vector3(-.13,-1,0)
	process.spread = 2
	process.initial_velocity_min = 24
	process.initial_velocity_max = 30
	process.gravity = Vector3(0,-5,0)
	rain.process_material = process
	var drop := BoxMesh.new()
	drop.size = Vector3(.009,.27,.009)
	drop.material = standard(Color(.48,.61,.7),.25)
	rain.draw_pass_1 = drop
	add_child(rain)

func set_weather(wet: bool) -> void:
	rain_enabled = wet
	apply_atmosphere()

func cycle_time(direction: int = 1) -> void:
	set_time(posmod(time_index+direction,TIME_PRESETS.size()))

func set_time(index: int) -> void:
	time_index = posmod(index,TIME_PRESETS.size())
	apply_atmosphere()

func apply_atmosphere() -> void:
	if applied_time==time_index and applied_rain==rain_enabled:
		refresh_ui()
		return
	applied_time = time_index
	applied_rain = rain_enabled
	atmosphere_revision += 1
	var preset := TIME_PRESETS[time_index]
	var sky_color: Color = preset.sky
	var horizon: Color = preset.horizon
	var fog_color: Color = preset.fog
	var wet := rain_enabled
	# Rain softens the selected lighting; it never selects a different time.
	var zenith_colors: Array[Color] = [Color("347dac"),Color("2379b8"),Color("397ba9"),Color("1f3a65"),Color("09162d")]
	sky_material.set_shader_parameter("zenith_color",zenith_colors[time_index].lerp(horizon*.62,.65 if wet else 0.0))
	sky_material.set_shader_parameter("horizon_color",horizon.lerp(fog_color,.4 if wet else 0.0))
	sky_material.set_shader_parameter("ground_color",Color("394c38").lerp(sky_color,.6))
	var cloud_lights: Array[Color] = [Color("fff1dc"),Color("f4f5ee"),Color("ffd5ab"),Color("a5b2cd"),Color("536982")]
	var cloud_shadows: Array[Color] = [Color("899eae"),Color("839bb0"),Color("8795a6"),Color("52617e"),Color("253950")]
	sky_material.set_shader_parameter("cloud_light",cloud_lights[time_index].lerp(fog_color,.5 if wet else 0.0))
	sky_material.set_shader_parameter("cloud_shadow",cloud_shadows[time_index].lerp(fog_color.darkened(.24),.55 if wet else 0.0))
	sky_material.set_shader_parameter("cloud_cover",.90 if wet else .48)
	sky_material.set_shader_parameter("overcast",1.0 if wet else 0.0)
	sky_material.set_shader_parameter("daylight",1.0 if time_index<3 else (.12 if time_index==3 else 0.0))
	sky_material.set_shader_parameter("moonlight",1.0 if time_index==4 else 0.0)
	ground_material.set_shader_parameter("wetness",1.0 if wet else 0.0)
	pavement_material.set_shader_parameter("wetness",1.0 if wet else 0.0)
	sun.rotation_degrees = preset.rotation
	sun.light_energy = float(preset.energy)*(.42 if wet else 1.0)
	sun.light_color = (preset.sun as Color).lerp(Color("c0d0e0"),.65 if wet else 0.0)
	# The light's +Z axis points toward the sun (or moon for the night preset).
	sky_material.set_shader_parameter("light_direction",sun.global_basis.z.normalized())
	sky_material.set_shader_parameter("light_color",sun.light_color)
	environment.ambient_light_energy = float(preset.ambient)*(1.12 if wet else 1.0)
	environment.fog_light_color = fog_color
	environment.fog_density = float(preset.density)*(1.65 if wet else 1.0)
	environment.volumetric_fog_density = .003 if wet else .001
	for lamp in lamps:lamp.light_energy = maxf(float(preset.lamps),1.0 if wet else 0.0)
	if rain:rain.emitting = wet
	refresh_ui()
	# Several changes in one frame need only one static reflection capture.
	if not reflection_refresh_pending:
		reflection_refresh_pending = true
		refresh_reflection.call_deferred()

func refresh_reflection() -> void:
	if OS.has_feature("web"):
		reflection_refresh_pending = false
		return
	# Let incremental sky filtering finish before the static probe sees it.
	# Rapid time/rain changes restart this wait, leaving just one final capture.
	var revision := atmosphere_revision
	var stable_frames := 0
	while stable_frames<8:
		if not is_inside_tree():
			return
		await get_tree().process_frame
		if not is_inside_tree():
			return
		if revision!=atmosphere_revision:
			revision = atmosphere_revision
			stable_frames = 0
		else:stable_frames += 1
	reflection_refresh_pending = false
	if is_instance_valid(reflection):reflection.queue_free()
	reflection = ReflectionProbe.new()
	reflection.position = Vector3(-3,3,-1)
	reflection.size = Vector3(65,22,60)
	reflection.box_projection = true
	reflection.update_mode = ReflectionProbe.UPDATE_ONCE
	reflection.max_distance = 100
	add_child(reflection)

func select_view(index: int) -> void:
	if session and session.seated:return
	view_index = index
	free_camera = false
	touring = false
	set_walk_mode(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh_ui()

func set_walk_mode(enabled: bool) -> void:
	if session and session.seated:return
	walking_mode = enabled
	free_camera = false
	touring = false
	pilot.set_enabled(enabled)
	camera.current = not enabled
	if enabled:pilot.camera.make_current()
	refresh_ui()

func _unhandled_input(event: InputEvent) -> void:
	if stress_mode or capture_mode:return
	if (session and session.is_menu_open()) or (help_panel and help_panel.visible):return
	if session and session.seated:
		aircraft.handle_pointer(event)
		return
	if walking_mode:
		pilot.handle_pointer(event)
		return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		free_camera = true
		touring = false
		refresh_ui()
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		camera.rotation.y -= event.relative.x*.002
		camera.rotation.x = clampf(camera.rotation.x-event.relative.y*.002,-1.48,1.48)

func _input(event: InputEvent) -> void:
	if stress_mode or capture_mode:return
	if not (event is InputEventKey and event.pressed and not event.echo):return
	if session and session.handle_key(event):
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_T:cycle_time(-1 if event.shift_pressed else 1)
		KEY_R:set_weather(not rain_enabled)
		KEY_L:toggle_language()
		KEY_C:
			if not walking_mode:set_walk_mode(true)
		KEY_HOME:
			pilot.respawn()
			set_walk_mode(true)
		KEY_V:
			if not walking_mode:select_view((view_index+1)%views.size())
		KEY_SPACE:
			if walking_mode:pilot.queue_jump()
			else:
				touring = not touring
				free_camera = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				refresh_ui()
		KEY_H:hud.visible = not hud.visible
		KEY_F1:
			hud.show()
			toggle_help()
		KEY_P:save_capture("manual")
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if help_panel.visible:toggle_help()
		KEY_F11:DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:return
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	elapsed += delta
	if camera == null:return
	if stress_mode:
		run_motion_check(delta)
		return
	if session and session.seated:
		pass
	elif walking_mode:
		pilot.controls_blocked = help_panel.visible or (session and session.is_menu_open())
	elif free_camera:
		var movement := Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W):movement.z -= 1
		if Input.is_physical_key_pressed(KEY_S):movement.z += 1
		if Input.is_physical_key_pressed(KEY_A):movement.x -= 1
		if Input.is_physical_key_pressed(KEY_D):movement.x += 1
		if Input.is_physical_key_pressed(KEY_E):movement.y += 1
		if Input.is_physical_key_pressed(KEY_Q):movement.y -= 1
		camera.position += camera.basis*movement.normalized()*delta*(24 if Input.is_physical_key_pressed(KEY_SHIFT) else 7)
		camera.position.y = maxf(camera.position.y,height_at(camera.position.x,camera.position.z)+.3)
	else:
		var destination: Vector3 = views[view_index].pos
		if touring:destination += Vector3(sin(elapsed*.12)*3, sin(elapsed*.09)*.35,cos(elapsed*.12)*2)
		camera.position = camera.position.lerp(destination,1-exp(-delta*3))
		var desired := camera.global_transform.looking_at(views[view_index].target).basis.get_rotation_quaternion()
		camera.quaternion = camera.quaternion.slerp(desired,1-exp(-delta*3))
	var rain_camera: Camera3D = pilot.camera if walking_mode else camera
	if session and session.seated:rain_camera = aircraft.chase
	rain.position = rain_camera.global_position+Vector3(0,18,0)
	if capture_mode and elapsed>4:frame_times.append(delta)
	if elapsed-last_metrics>1:
		last_metrics = elapsed
		var fps := Engine.get_frames_per_second()
		status_label.text = "%d FPS" % fps
		# Automatic FPS Governor: keep framerate smooth on integrated GPUs & Web browsers
		if not capture_mode and not stress_mode and elapsed > 3.5 and fps > 0:
			if fps < 46:
				if not OS.has_feature("web") and not cinematic and get_viewport().scaling_3d_scale > .68:
					get_viewport().scaling_3d_scale = maxf(.68, get_viewport().scaling_3d_scale - .05)
				for chunk in grass_chunks:
					if is_instance_valid(chunk) and chunk.visibility_range_end > 58.0:
						chunk.visibility_range_end = maxf(58.0, chunk.visibility_range_end - 8.0)
			elif fps >= 58 and not OS.has_feature("web") and not cinematic and get_viewport().scaling_3d_scale < .8:
				get_viewport().scaling_3d_scale = minf(.8, get_viewport().scaling_3d_scale + .02)
	if capture_mode and not capture_busy:
		capture_clock += delta
		if capture_clock>2 and capture_clock<6.8:view_times.append(delta)
		if capture_clock>7.0:
			capture_busy = true
			capture_current_view()

func save_capture(label: String) -> void:
	if not view_times.is_empty():
		var sum := 0.0
		for value in view_times:sum+=value
		var sorted := view_times.duplicate()
		sorted.sort()
		view_metrics[label]={"mean_fps":view_times.size()/sum,"p95_frame_ms":sorted[int(sorted.size()*.95)]*1000,"samples":view_times.size()}
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var output := preview_directory().path_join(label+".png")
	var error := image.save_png(output)
	print("CAPTURE ",output," error=",error)

func configure_capture() -> void:
	var step := CAPTURE_PLAN[capture_stage]
	select_view(step.view)
	time_index = step.time
	rain_enabled = step.rain
	apply_atmosphere()
	view_times.clear()
	capture_clock = 0

func capture_current_view() -> void:
	await save_capture(CAPTURE_PLAN[capture_stage].label)
	capture_stage += 1
	if capture_stage==CAPTURE_PLAN.size():
		capture_mode = false
		report_metrics()
		get_tree().quit()
		return
	configure_capture()
	capture_busy = false

func preview_directory() -> String:
	var directory := ProjectSettings.globalize_path(ROOT_OUT) if OS.has_feature("editor") else OS.get_user_data_dir().path_join("previews")
	DirAccess.make_dir_recursive_absolute(directory)
	return directory

func run_motion_check(delta: float) -> void:
	# Repeat the same fast 360-degree turn and translation in cold/warm phases.
	var t := fmod(elapsed,14.0)
	var angle := t*TAU/4.5
	camera.position = Vector3(5+sin(t*.5)*24,3.5+sin(t*.7)*2,8+cos(t*.5)*18)
	camera.rotation = Vector3(-.12+sin(t*.9)*.25,angle,0)
	rain.position = camera.position+Vector3(0,18,0)
	if t>2.0:stress_samples.append(delta)
	status_label.text = "%d FPS" % Engine.get_frames_per_second()
	mode_label.text = ["First sweep","Repeat sweep","Rain sweep"][stress_phase]
	if elapsed>=14.0*(stress_phase+1):
		var sorted := stress_samples.duplicate()
		sorted.sort()
		var sum := 0.0
		for value in sorted:sum+=value
		var result := {"mean_fps":sorted.size()/maxf(sum,.001),"p95_ms":sorted[int(sorted.size()*.95)]*1000,"worst_ms":sorted[-1]*1000,"frames":sorted.size()}
		stress_results[["first_sweep","repeat_sweep","rain_sweep"][stress_phase]]=result
		print("MOTION_PHASE ",JSON.stringify(result))
		stress_samples.clear()
		stress_phase+=1
		if stress_phase==2:
			time_index = 3
			set_weather(true)
		if stress_phase==3:
			stress_mode = false
			stress_results["gpu"]=RenderingServer.get_video_adapter_name()
			stress_results["render_scale"]=get_viewport().scaling_3d_scale
			var file := FileAccess.open(preview_directory().path_join("motion_test.json"),FileAccess.WRITE)
			file.store_string(JSON.stringify(stress_results,"\t"))
			get_tree().quit()

func report_metrics() -> void:
	if frame_times.is_empty():return
	var sorted := frame_times.duplicate()
	sorted.sort()
	var sum := 0.0
	for value in frame_times:sum += value
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"frames":frame_times.size(),"mean_fps":frame_times.size()/sum,"p95_frame_ms":sorted[int(sorted.size()*.95)]*1000,"resolution":str(get_viewport().get_visible_rect().size),"render_scale":get_viewport().scaling_3d_scale,"draw_calls_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"triangles_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"note":"Includes changing cameras/weather and screenshot capture; developer sample, not a minimum-spec certification."}
	report["stationary_views"] = view_metrics
	var file := FileAccess.open(preview_directory().path_join("performance.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("PERFORMANCE ",JSON.stringify(report))
