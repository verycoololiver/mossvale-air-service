extends RefCounted
## Static world geometry uses layer 1; the pilot uses layer 2.

static func box_at(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.position = at
	return body

static func mesh_at(parent: Node3D, mesh: Mesh) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body

static func asset_at(asset: Node3D) -> void:
	var faces := PackedVector3Array()
	collect_faces(asset,asset,faces)
	if faces.is_empty():return
	var body := StaticBody3D.new()
	body.name = "AssetCollision"
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	collision.shape = shape
	body.add_child(collision)
	asset.add_child(body)

static func collect_faces(root: Node3D, node: Node, faces: PackedVector3Array) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var transform := root.global_transform.affine_inverse()*mesh.global_transform
		for vertex in mesh.mesh.get_faces():faces.append(transform*vertex)
	for child in node.get_children():collect_faces(root,child,faces)

static func tree_at(parent: Node3D, placement: Transform3D) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	var scale := placement.basis.get_scale().x
	shape.radius = .17*scale
	shape.height = 3.6*scale
	collision.shape = shape
	collision.position.y = shape.height*.5
	body.add_child(collision)
	parent.add_child(body)
	body.position = placement.origin

static func rock_at(parent: Node3D, placement: Transform3D) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = .65*placement.basis.get_scale().x
	collision.shape = shape
	collision.position.y = shape.radius*.5
	body.add_child(collision)
	parent.add_child(body)
	body.position = placement.origin
