extends Node3D
## Visible third-person pilot body; limbs and torso animate from actual distance travelled.
const BODY = preload("res://assets/first_person_body.glb")
var skeleton: Skeleton3D
var rest := {}
var indices := {}
var motion := 0.0
var travel_direction := Vector3.FORWARD
var pilot: CharacterBody3D

func _ready() -> void:
	var model := BODY.instantiate()
	add_child(model)
	skeleton = find_skeleton(model)
	assert(skeleton != null, "The pilot body needs its exported skeleton")
	for i in range(skeleton.get_bone_count()):
		var key := skeleton.get_bone_name(i)
		indices[key] = i
		rest[key] = skeleton.get_bone_global_rest(i)

func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:return node
	for child in node.get_children():
		var found := find_skeleton(child)
		if found:return found
	return null

func point(key: String) -> Vector3:
	return (rest[key] as Transform3D).origin

func place_bone(key: String, at: Vector3, rotation_delta: Quaternion = Quaternion.IDENTITY) -> void:
	var pose: Transform3D = rest[key]
	pose.origin = at
	pose.basis = Basis(rotation_delta)*pose.basis
	skeleton.set_bone_global_pose(indices[key],pose)

func aim_bone(key: String, child: String, start: Vector3, end: Vector3) -> void:
	var original := (point(child)-point(key)).normalized()
	var desired := (end-start).normalized()
	place_bone(key,start,Quaternion(original,desired))

func knee_between(hip: Vector3, ankle: Vector3, upper_length: float, lower_length: float) -> Vector3:
	var axis := (ankle-hip).normalized()
	var distance := clampf(hip.distance_to(ankle),.1,upper_length+lower_length-.001)
	var along := (upper_length*upper_length-lower_length*lower_length+distance*distance)/(2.0*distance)
	var height := sqrt(maxf(upper_length*upper_length-along*along,0.0))
	var bend := (Vector3.FORWARD-axis*Vector3.FORWARD.dot(axis)).normalized()
	return hip+axis*along+bend*height

func ground_ankle(target: Vector3, ankle_height: float) -> Vector3:
	var contact := skeleton.to_global(target-Vector3.UP*ankle_height)
	var ray := PhysicsRayQueryParameters3D.create(contact+Vector3.UP*.32,contact-Vector3.UP*.42,5,[pilot.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		target.y = skeleton.to_local(hit.position).y+ankle_height
	return target

func animate(delta: float, speed: float, stride: float, grounded: bool, local_velocity: Vector3) -> void:
	if not skeleton or not visible:return
	var moving := grounded and speed>.12
	motion = move_toward(motion,1.0 if moving else 0.0,delta*7.5)
	var running := clampf((speed-2.85)/2.55,0.0,1.0)
	if moving and local_velocity.length()>.05:
		travel_direction = local_velocity.normalized()
	var bounce := absf(sin(stride*TAU))*lerpf(.018,.038,running)*motion
	var lower := lerpf(.035,.085,running)*motion - bounce
	var offset := Vector3(0,-lower,0)
	var chest_lean := Quaternion(Vector3.RIGHT, -lerpf(.04,.11,running)*motion)
	place_bone("hips",point("hips")+offset)
	place_bone("chest",point("chest")+offset,chest_lean)
	for i in range(2):
		var suffix := "L" if i==0 else "R"
		var thigh := "thigh_"+suffix
		var shin := "shin_"+suffix
		var foot := "foot_"+suffix
		var cycle := fposmod(stride*.5+float(i)*.5,1.0)
		var swing := maxf(cycle-.5,0.0)*2.0
		var reach := lerpf(.26,.38,running)
		var fore_aft := lerpf(reach,-reach,cycle*2.0) if cycle<.5 else lerpf(-reach,reach,smoothstep(0.0,1.0,swing))
		var lift := sin(swing*PI)*lerpf(.095,.17,running)*motion
		var hip := point(thigh)+offset
		var ankle := point(foot)+travel_direction*fore_aft*motion
		if grounded:ankle = ground_ankle(ankle,point(foot).y)
		ankle.y += lift
		if not grounded:ankle += Vector3(0,.10,.055)
		var upper_length := point(thigh).distance_to(point(shin))
		var lower_length := point(shin).distance_to(point(foot))
		var max_reach := upper_length+lower_length-.001
		if hip.distance_to(ankle)>max_reach:ankle = hip+(ankle-hip).normalized()*max_reach
		var knee := knee_between(hip,ankle,upper_length,lower_length)
		aim_bone(thigh,shin,hip,knee)
		aim_bone(shin,foot,knee,ankle)
		place_bone(foot,ankle,Quaternion(Vector3.RIGHT,-sin(swing*PI)*.14*motion))
		# Opposite arm swing, with a mild elbow bend; hands stay relaxed.
		var upper := "upper_"+suffix
		var forearm := "forearm_"+suffix
		var hand := "hand_"+suffix
		var angle := -cos(cycle*TAU)*lerpf(.19,.35,running)*motion
		var shoulder := point(upper)+offset
		var upper_rotation := Quaternion(Vector3.RIGHT,angle)
		var elbow := shoulder+upper_rotation*(point(forearm)-point(upper))
		var fore_rotation := Quaternion(Vector3.RIGHT,angle-.09*motion)
		var wrist := elbow+fore_rotation*(point(hand)-point(forearm))
		place_bone(upper,shoulder,upper_rotation)
		place_bone(forearm,elbow,fore_rotation)
		place_bone(hand,wrist,fore_rotation)
