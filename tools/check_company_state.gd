extends SceneTree
## Headless checks for the deterministic company economy and save boundary.

const CompanyState = preload("res://company_state.gd")
const TEST_PATH: String = "res://../art/previews/company_state_test.json"

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_files()
	_test_quotes_and_booking()
	_test_completion_and_free_arrival()
	_test_fuel_transactions()
	_test_save_roundtrip_and_contract_cancel()
	_test_backup_and_malformed_resilience()
	_test_missing_save_starts_new_company()
	_cleanup_files()
	if failures.is_empty():
		print("COMPANY_STATE_CHECK passed")
		quit(0)
		return
	for failure in failures:
		print("COMPANY_STATE_CHECK failure: ", failure)
	quit(1)


func _test_quotes_and_booking() -> void:
	var company := CompanyState.new()
	_check(company.money_cents == 120000, "new company money")
	_check(is_equal_approx(company.fuel_litres, 40.0), "new company fuel")
	_check(company.current_airfield == "mossvale", "new company airfield")
	_check(company.quote_seats(-1) == 0, "negative fare has no demand")
	_check(company.quote_seats(0) == 0, "zero fare has no demand")
	_check(company.quote_seats(4500) == 3, "$45 fills three seats")
	_check(company.quote_seats(7500) == 2, "$75 fills two seats")
	_check(company.quote_seats(11000) == 1, "$110 fills one seat")
	_check(company.quote_seats(14000) == 1, "$140 retains one seat")
	_check(company.quote_seats(14001) == 0, "over-$140 fare has no demand")
	_check(company.book_trip("mossvale", "mossvale", 4500).get("ok", true) == false, "same endpoint rejected")
	_check(company.book_trip("unknown", "birch_hollow", 4500).get("ok", true) == false, "unknown origin rejected")
	_check(company.book_trip("mossvale", "birch_hollow", 0).get("ok", true) == false, "zero fare rejected")
	_check(company.book_trip("mossvale", "birch_hollow", 14001).get("ok", true) == false, "no-demand fare rejected")
	_check(company.book_trip("birch_hollow", "mossvale", 4500).get("ok", true) == false, "wrong current origin rejected")
	var booked := company.book_trip("mossvale", "birch_hollow", 4500)
	_check(bool(booked.get("ok", false)), "valid trip booked")
	_check(company.active_trip.get("seats", 0) == 3, "booked seat count")
	_check(company.active_trip.get("payout_cents", 0) == 13500, "booked payout")
	_check(company.book_trip("mossvale", "birch_hollow", 7500).get("ok", true) == false, "concurrent trip rejected")


func _test_completion_and_free_arrival() -> void:
	var company := CompanyState.new()
	var starting_money := company.money_cents
	_check(company.book_trip("mossvale", "birch_hollow", 7500).get("ok", false), "completion setup booked")
	var wrong := company.complete_trip("mossvale")
	_check(not bool(wrong.get("ok", true)), "wrong destination rejected")
	_check(company.money_cents == starting_money, "wrong destination does not pay")
	_check(company.completed_trips == 0, "wrong destination does not increment stats")
	var completed := company.complete_trip("birch_hollow")
	_check(bool(completed.get("ok", false)), "valid trip completed")
	_check(company.money_cents == starting_money + 15000, "payout credited once")
	_check(company.total_revenue_cents == 15000, "revenue recorded")
	_check(company.completed_trips == 1, "trip count recorded")
	_check(company.current_airfield == "birch_hollow", "destination becomes current airfield")
	_check(company.active_trip.is_empty(), "completed trip cleared")
	var duplicate := company.complete_trip("birch_hollow")
	_check(not bool(duplicate.get("ok", true)), "duplicate completion rejected")
	_check(company.money_cents == starting_money + 15000, "duplicate completion does not pay")
	_check(bool(company.arrive_at("mossvale").get("ok", false)), "free arrival accepted")
	_check(company.current_airfield == "mossvale", "free arrival updates airfield")
	_check(not bool(company.arrive_at("not_an_airfield").get("ok", true)), "invalid free arrival rejected")
	_check(company.book_trip("mossvale", "birch_hollow", 4500).get("ok", false), "contract setup for arrival guard")
	_check(not bool(company.arrive_at("mossvale").get("ok", true)), "free arrival blocked during contract")
	company.cancel_trip()
	_check(company.active_trip.is_empty(), "cancel clears contract")
	_check(company.money_cents == starting_money + 15000, "cancel has no payout")


func _test_fuel_transactions() -> void:
	var company := CompanyState.new()
	var start_money := company.money_cents
	_check(not bool(company.refuel(-1.0).get("ok", true)), "negative fuel rejected")
	_check(not bool(company.refuel(NAN).get("ok", true)), "NaN fuel rejected")
	_check(not bool(company.refuel(INF).get("ok", true)), "infinite fuel rejected")
	_check(company.money_cents == start_money and is_equal_approx(company.fuel_litres, 40.0), "invalid fuel leaves state unchanged")
	var purchased := company.refuel(10.0)
	_check(bool(purchased.get("ok", false)), "fuel purchase accepted")
	_check(purchased.get("charge_cents", -1) == 2200, "fuel charge is integer cents")
	_check(company.money_cents == start_money - 2200, "fuel charge deducted")
	_check(is_equal_approx(company.fuel_litres, 50.0), "fuel added")
	var before_excess_money := company.money_cents
	var before_excess_fuel := company.fuel_litres
	_check(not bool(company.refuel(31.0).get("ok", true)), "tank excess rejected")
	_check(company.money_cents == before_excess_money and is_equal_approx(company.fuel_litres, before_excess_fuel), "tank excess is atomic")
	var consumed := company.consume_fuel(7.5)
	_check(is_equal_approx(consumed, 7.5), "fuel consumption amount")
	_check(is_equal_approx(company.fuel_litres, 42.5), "fuel consumption state")
	_check(is_equal_approx(company.consume_fuel(999.0), 42.5), "consumption clamps to tank")
	_check(is_equal_approx(company.fuel_litres, 0.0), "consumption reaches zero")
	_check(is_equal_approx(company.consume_fuel(-1.0), 0.0), "negative consumption rejected")
	_check(is_equal_approx(company.consume_fuel(NAN), 0.0), "NaN consumption rejected")
	company.money_cents = 1
	var before_funds_fuel := company.fuel_litres
	_check(not bool(company.refuel(1.0).get("ok", true)), "insufficient fuel funds rejected")
	_check(company.money_cents == 1 and is_equal_approx(company.fuel_litres, before_funds_fuel), "insufficient funds is atomic")


func _test_save_roundtrip_and_contract_cancel() -> void:
	var company := CompanyState.new()
	company.money_cents = 98765
	company.fuel_litres = 27.5
	company.completed_trips = 4
	company.total_revenue_cents = 54321
	var booked := company.book_trip("mossvale", "birch_hollow", 11000)
	_check(bool(booked.get("ok", false)), "save setup booked")
	var saved := company.save(TEST_PATH)
	_check(bool(saved.get("ok", false)), "save succeeds")
	var restored := CompanyState.new()
	restored.money_cents = 1
	restored.fuel_litres = 1.0
	restored.current_airfield = "birch_hollow"
	var loaded := restored.load_save(TEST_PATH)
	_check(bool(loaded.get("ok", false)), "roundtrip load succeeds")
	_check(restored.money_cents == 98765, "roundtrip money")
	_check(is_equal_approx(restored.fuel_litres, 27.5), "roundtrip fuel")
	_check(restored.current_airfield == "mossvale", "roundtrip airfield")
	_check(restored.completed_trips == 4 and restored.total_revenue_cents == 54321, "roundtrip stats")
	_check(restored.active_trip.is_empty(), "unfinished contract canceled on load")
	_check(bool(loaded.get("unfinished_trip_canceled", false)), "load reports canceled contract")
	_check(restored.complete_trip("birch_hollow").get("ok", true) == false, "canceled contract cannot pay later")


func _test_backup_and_malformed_resilience() -> void:
	_cleanup_files()
	var company := CompanyState.new()
	company.money_cents = 22222
	company.fuel_litres = 12.0
	company.current_airfield = "birch_hollow"
	_check(bool(company.save(TEST_PATH).get("ok", false)), "backup setup initial save")
	company.money_cents = 33333
	company.fuel_litres = 13.0
	_check(bool(company.save(TEST_PATH).get("ok", false)), "backup setup replacement save")
	var corrupt_file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	corrupt_file.store_string("{ this is not valid JSON")
	corrupt_file.close()
	var recovered := CompanyState.new()
	recovered.money_cents = 777
	recovered.fuel_litres = 7.0
	var recovery := recovered.load_save(TEST_PATH)
	_check(bool(recovery.get("ok", false)) and bool(recovery.get("used_backup", false)), "backup recovery succeeds")
	_check(recovered.money_cents == 22222 and is_equal_approx(recovered.fuel_litres, 12.0), "backup restores last known good state")
	_check(recovered.current_airfield == "birch_hollow", "backup restores airfield")
	_check(bool(recovered.save(TEST_PATH).get("ok", false)), "save after backup recovery succeeds")
	# A subsequent save must leave the good backup intact even though the
	# primary was corrupt when that save began.
	var corrupt_again := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	corrupt_again.store_string("corrupt primary after recovery")
	corrupt_again.close()
	var backup_after_recovery := CompanyState.new()
	var backup_result := backup_after_recovery.load_save(TEST_PATH)
	_check(bool(backup_result.get("ok", false)) and bool(backup_result.get("used_backup", false)), "good backup survives save after recovery")
	_check(backup_after_recovery.money_cents == 22222 and is_equal_approx(backup_after_recovery.fuel_litres, 12.0), "surviving backup retains state")

	_cleanup_files()
	var malformed := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	malformed.store_string(JSON.stringify({
		"version": 1,
		"money_cents": "not an integer",
		"fuel_litres": 10.0,
		"current_airfield": "mossvale",
		"completed_trips": 0,
		"total_revenue_cents": 0,
		"active_trip": {}
	}))
	malformed.close()
	var unchanged := CompanyState.new()
	unchanged.money_cents = 6543
	unchanged.fuel_litres = 19.0
	unchanged.current_airfield = "birch_hollow"
	var rejected := unchanged.load_save(TEST_PATH)
	_check(not bool(rejected.get("ok", true)), "malformed save rejected")
	_check(unchanged.money_cents == 6543 and is_equal_approx(unchanged.fuel_litres, 19.0) and unchanged.current_airfield == "birch_hollow", "malformed save leaves state untouched")


func _test_missing_save_starts_new_company() -> void:
	_cleanup_files()
	var company := CompanyState.new()
	company.money_cents = 321
	company.fuel_litres = 2.0
	company.current_airfield = "birch_hollow"
	var loaded := company.load_save(TEST_PATH)
	_check(bool(loaded.get("ok", false)) and bool(loaded.get("missing", false)), "missing save is normal new company")
	_check(company.money_cents == 120000 and is_equal_approx(company.fuel_litres, 40.0) and company.current_airfield == "mossvale", "missing save resets defaults")


func _cleanup_files() -> void:
	for path in [TEST_PATH, TEST_PATH + ".bak", TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
