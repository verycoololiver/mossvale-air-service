extends SceneTree
## Verifies the 4-aircraft fleet expansion (Heron, Osprey, Albatross, Skywhale),
## scaled passenger seat sales (3 / 5 / 9 / 15 seats), full-tank refueling, and 3D parked fleet showcase.

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var session = game.session
	var company = session.company
	company.reset_new_company()
	session.test_mode = false

	# 1. Verify 4 aircraft in catalog and 3 parked showcase aircraft visible on apron when Heron is active
	game.update_parked_fleet("heron")
	var visible_parked := 0
	for id in ["heron", "osprey", "albatross", "skywhale"]:
		var node: Node3D = game.parked_fleet.get(id)
		check(node != null, "Parked showcase node exists for " + id)
		if node and node.visible:
			visible_parked += 1
	check(visible_parked == 3, "Three showcase aircraft are visibly parked on the apron alongside the active aircraft")

	# 2. Give company enough money to purchase Osprey, Albatross, and Skywhale
	company.money_cents = 1000000
	session.buy_aircraft("osprey")
	await physics_frame
	check(company.owned_aircraft.has("osprey") and company.active_aircraft_id == "osprey", "Buying Osprey immediately selects it on the apron")
	check(company.get_passenger_capacity() == 5 and is_equal_approx(company.get_fuel_capacity(), 120.0), "Osprey has 5 seats and 120L tank")
	check(session.exit_position().is_finite(), "Osprey exit door is unobstructed")

	session.buy_aircraft("albatross")
	await physics_frame
	check(company.owned_aircraft.has("albatross") and company.active_aircraft_id == "albatross", "Buying Albatross immediately selects it on the apron")
	check(company.get_passenger_capacity() == 9 and is_equal_approx(company.get_fuel_capacity(), 200.0), "Albatross has 9 seats and 200L tank")
	check(company.quote_seats(4500) == 9, "Albatross sells 9 seats at $45 fare")
	check(session.exit_position().is_finite(), "Albatross exit door is unobstructed")

	session.buy_aircraft("skywhale")
	await physics_frame
	check(company.owned_aircraft.has("skywhale") and company.active_aircraft_id == "skywhale", "Buying Skywhale immediately selects it on the apron")
	check(company.get_passenger_capacity() == 15 and is_equal_approx(company.get_fuel_capacity(), 320.0), "Skywhale has 15 seats and 320L tank")
	check(company.quote_seats(4500) == 15, "Skywhale sells 15 seats at $45 fare")
	check(session.exit_position().is_finite(), "Skywhale exit door is unobstructed")
	check(game.aircraft.aircraft_id == "skywhale" and game.aircraft.name == "Skywhale", "Active 3D aircraft controller switched to Skywhale")
	check(game.parked_fleet["heron"].visible and not game.parked_fleet["skywhale"].visible, "Heron moves to showcase bay when Skywhale is active")

	# 3. Test one-click full tank refuel on Skywhale (160L -> 320L)
	game.pilot.global_position = game.aircraft.global_position + Vector3(2.0, 0.0, 0.0)
	session.refuel_full()
	check(is_equal_approx(company.fuel_litres, 320.0), "Full-tank refuel button fills Skywhale to 320L")

	# 4. Test booking 15 seats on Skywhale
	session.fare_cents = 4500
	session.book_trip()
	check(not company.active_trip.is_empty() and int(company.active_trip.get("seats", 0)) == 15, "Skywhale books 15 passengers ($675 payout)")

	print("FLEET_EXPANSION_CHECK ", JSON.stringify({"passed": failures.is_empty(), "failures": failures}))
	game.pilot.footstep.stop()
	await create_timer(0.15).timeout
	quit(0 if failures.is_empty() else 1)
