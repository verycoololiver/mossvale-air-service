extends RefCounted
## Compact prototype valley. Runways run east/west; coordinates are metres.
const ORDER: PackedStringArray = ["mossvale", "birch_hollow", "pine_ridge", "mirror_lake"]
const DATA := {
	"mossvale": {"name":"Mossvale", "centre":Vector3(0,0,-52), "length":580.0, "width":16.0,
		"apron":Vector3(-8,0,-1), "spawn":Vector3(0,.07,3), "yaw":-.23,
		"lineup":Vector3(-250,.09,-52)},
	"birch_hollow": {"name":"Birch Hollow", "centre":Vector3(-220,24,-640), "length":500.0, "width":18.0,
		"apron":Vector3(-210,24,-604), "spawn":Vector3(-205,24.07,-602), "yaw":PI,
		"lineup":Vector3(-435,24.09,-640)},
	"pine_ridge": {"name":"Pine Ridge", "centre":Vector3(420,36,-520), "length":480.0, "width":18.0,
		"apron":Vector3(430,36,-484), "spawn":Vector3(435,36.07,-482), "yaw":PI,
		"lineup":Vector3(215,36.09,-520)},
	"mirror_lake": {"name":"Mirror Lake", "centre":Vector3(-280,12,380), "length":500.0, "width":18.0,
		"apron":Vector3(-270,12,416), "spawn":Vector3(-265,12.07,418), "yaw":PI,
		"lineup":Vector3(-495,12.09,380)}
}

static func field_at(at: Vector3) -> String:
	for id in DATA:
		var field: Dictionary = DATA[id]
		var runway: Vector3 = at-field.centre
		var apron: Vector3 = at-field.apron
		if absf(runway.y)>3:continue
		if absf(runway.x)<field.length*.5 and absf(runway.z)<field.width*.5+1:return id
		if absf(apron.x)<28 and absf(apron.z)<22:return id
		if absf(apron.x)<6 and apron.z<0 and at.z>field.centre.z:return id
	return ""

static func other(id: String) -> String:
	return "birch_hollow" if id=="mossvale" else "mossvale"

static func next_in_circuit(id: String) -> String:
	var idx := ORDER.find(id)
	if idx < 0:
		return "birch_hollow"
	return ORDER[(idx + 1) % ORDER.size()]

static func flatten_height(x: float, z: float, natural: float) -> float:
	for id in DATA:
		var field: Dictionary = DATA[id]
		var p := Vector2(x-field.centre.x,z-field.centre.z)
		var edge := maxf(absf(p.x)-(field.length*.5+22),absf(p.y-12)-52)
		var weight := 1.0-smoothstep(0.0,78.0,edge)
		natural = lerpf(natural,field.centre.y-.03,weight)
	return natural
