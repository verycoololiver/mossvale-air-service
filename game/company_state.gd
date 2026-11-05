extends RefCounted
## Deterministic, UI-free company economy and persistence state.
##
## The flight layer owns takeoff, touchdown and parking validation. It should
## call complete_trip() only after those checks have passed. This class never
## autosaves and never depends on a scene, node, network or real-world money.

const AircraftCatalog = preload("res://aircraft_catalog.gd")

const SAVE_PATH: String = "user://company_v1.json"
const SAVE_VERSION: int = 2
const LEGACY_SAVE_VERSION: int = 1

# Kept for callers that still need the original Heron tank size. New code
# should ask get_fuel_capacity() for the selected aircraft's specification.
const FUEL_CAPACITY: float = 80.0
const FUEL_PRICE_CENTS: int = 220
const STARTING_MONEY_CENTS: int = 120000
const STARTING_FUEL_LITRES: float = 40.0

const MAX_SEATS: int = 20
const MAX_FARE_CENTS: int = 14000
const MAX_MONEY_CENTS: int = 900000000000000
const MAX_COMPLETED_TRIPS: int = 1000000000
const MAX_TOTAL_REVENUE_CENTS: int = 900000000000000
const FUEL_EPSILON: float = 0.000001

const AIRFIELDS: PackedStringArray = ["mossvale", "birch_hollow", "pine_ridge", "mirror_lake"]
const SAVE_FIELDS_V1: PackedStringArray = [
	"version",
	"money_cents",
	"fuel_litres",
	"current_airfield",
	"completed_trips",
	"total_revenue_cents",
	"active_trip"
]
const SAVE_FIELDS_V2: PackedStringArray = [
	"version",
	"money_cents",
	"active_aircraft_id",
	"owned_aircraft",
	"current_airfield",
	"completed_trips",
	"total_revenue_cents",
	"active_trip"
]
const AIRCRAFT_LEDGER_FIELDS: PackedStringArray = ["fuel_litres", "airfield"]
const LEGACY_TRIP_FIELDS: PackedStringArray = [
	"origin",
	"destination",
	"seats",
	"fare_cents",
	"payout_cents"
]
const TRIP_FIELDS: PackedStringArray = [
	"aircraft_id",
	"origin",
	"destination",
	"seats",
	"fare_cents",
	"payout_cents"
]

var money_cents: int = STARTING_MONEY_CENTS
var active_aircraft_id: String = "heron"
var owned_aircraft: Dictionary = {
	"heron": {
		"fuel_litres": STARTING_FUEL_LITRES,
		"airfield": "mossvale"
	}
}
var active_trip: Dictionary = {}
var completed_trips: int = 0
var total_revenue_cents: int = 0
var _current_airfield: String = "mossvale"
var current_airfield: String:
	get:
		return _current_airfield
	set(value):
		_current_airfield = value
		if _is_valid_airfield(value) and owned_aircraft.has(active_aircraft_id):
			var ledger_value: Variant = owned_aircraft[active_aircraft_id]
			if typeof(ledger_value) == TYPE_DICTIONARY:
				var ledger: Dictionary = ledger_value
				ledger["airfield"] = value
				owned_aircraft[active_aircraft_id] = ledger

# Compatibility view for the flight layer. Fuel is stored per aircraft, and
# reads/writes through this property always target the selected aircraft.
var fuel_litres: float:
	get:
		var stored_fuel: float = _record_fuel(active_aircraft_id)
		return stored_fuel if is_finite(stored_fuel) else 0.0
	set(value):
		if not is_finite(value) or not owned_aircraft.has(active_aircraft_id):
			return
		var ledger_value: Variant = owned_aircraft[active_aircraft_id]
		if typeof(ledger_value) != TYPE_DICTIONARY:
			return
		var ledger: Dictionary = ledger_value
		ledger["fuel_litres"] = value
		owned_aircraft[active_aircraft_id] = ledger


func get_fuel_capacity() -> float:
	var spec: Dictionary = _aircraft_spec(active_aircraft_id)
	return float(spec.get("fuel_capacity", 0.0))


func get_passenger_capacity() -> int:
	var spec: Dictionary = _aircraft_spec(active_aircraft_id)
	return int(spec.get("passenger_seats", 0))


func quote_seats(fare_cents: int) -> int:
	return _quote_seats_for_aircraft(active_aircraft_id, fare_cents)


func book_trip(origin: String, destination: String, fare_cents: int) -> Dictionary:
	if not _is_valid_airfield(origin):
		return _failure("Unknown origin airfield.")
	if not _is_valid_airfield(destination):
		return _failure("Unknown destination airfield.")
	if origin == destination:
		return _failure("Origin and destination must differ.")
	if not active_trip.is_empty():
		return _failure("A trip is already active.")
	if not _is_valid_company_state(false):
		return _failure("Company state is invalid.")
	if origin != current_airfield:
		return _failure("Trips must depart from the current airfield.")
	if fare_cents <= 0:
		return _failure("Fare must be positive.")
	var seats: int = quote_seats(fare_cents)
	if seats <= 0:
		return _failure("That fare has no paying demand.")
	var payout_cents: int = seats * fare_cents
	# quote_seats() bounds both factors, but keep the invariant explicit here.
	if payout_cents <= 0 or payout_cents > MAX_TOTAL_REVENUE_CENTS:
		return _failure("Payout is outside the company limits.")
	active_trip = {
		"aircraft_id": active_aircraft_id,
		"origin": origin,
		"destination": destination,
		"seats": seats,
		"fare_cents": fare_cents,
		"payout_cents": payout_cents
	}
	return {
		"ok": true,
		"message": "Trip booked.",
		"aircraft_id": active_aircraft_id,
		"origin": origin,
		"destination": destination,
		"seats": seats,
		"fare_cents": fare_cents,
		"payout_cents": payout_cents
	}


func complete_trip(destination: String) -> Dictionary:
	# The caller must have separately validated takeoff, touchdown and parking.
	if not _is_valid_airfield(destination):
		return _failure("Unknown destination airfield.")
	if active_trip.is_empty():
		return _failure("There is no active trip to complete.")
	if not _is_valid_company_state(true):
		return _failure("Active trip or company data is invalid.")
	if str(active_trip["aircraft_id"]) != active_aircraft_id:
		return _failure("The active aircraft does not match the booked trip.")
	if destination != str(active_trip["destination"]):
		return _failure("The parked destination does not match the trip.")
	var payout_cents: int = int(active_trip["payout_cents"])
	if money_cents < 0 or payout_cents < 0 or money_cents > MAX_MONEY_CENTS - payout_cents:
		return _failure("Company funds cannot accept this payout.")
	if completed_trips >= MAX_COMPLETED_TRIPS or total_revenue_cents > MAX_TOTAL_REVENUE_CENTS - payout_cents:
		return _failure("Company statistics cannot accept this payout.")
	var seats: int = int(active_trip["seats"])
	money_cents += payout_cents
	completed_trips += 1
	total_revenue_cents += payout_cents
	_move_active_aircraft_to(destination)
	active_trip = {}
	return {
		"ok": true,
		"message": "Trip completed and payout credited.",
		"destination": destination,
		"aircraft_id": active_aircraft_id,
		"seats": seats,
		"payout_cents": payout_cents,
		"money_cents": money_cents
	}


func arrive_at(airfield: String) -> Dictionary:
	if not _is_valid_airfield(airfield):
		return _failure("Unknown arrival airfield.")
	if not active_trip.is_empty():
		return _failure("An active trip must use complete_trip at its booked destination.")
	if not _is_valid_company_state(false):
		return _failure("Company state is invalid.")
	_move_active_aircraft_to(airfield)
	return {
		"ok": true,
		"message": "Arrived on a free flight.",
		"current_airfield": current_airfield
	}


func purchase_aircraft(aircraft_id: String) -> Dictionary:
	if not _aircraft_spec(aircraft_id).is_empty() == false:
		return _failure("Unknown aircraft.")
	if not active_trip.is_empty():
		return _failure("Aircraft cannot be purchased while a trip is booked.")
	if not _is_valid_company_state(false):
		return _failure("Company state is invalid.")
	if owned_aircraft.has(aircraft_id):
		return _failure("That aircraft is already owned.")
	var spec: Dictionary = _aircraft_spec(aircraft_id)
	var price_cents: int = int(spec.get("price_cents", -1))
	var delivery_fuel: float = float(spec.get("purchase_fuel", NAN))
	var capacity: float = float(spec.get("fuel_capacity", 0.0))
	if price_cents < 0 or delivery_fuel < 0.0 or not is_finite(delivery_fuel) or delivery_fuel > capacity:
		return _failure("Aircraft catalog data is invalid.")
	if money_cents < price_cents:
		return _failure("Insufficient funds to purchase that aircraft.")
	owned_aircraft[aircraft_id] = {
		"fuel_litres": delivery_fuel,
		"airfield": current_airfield
	}
	money_cents -= price_cents
	return {
		"ok": true,
		"message": "Aircraft purchased.",
		"aircraft_id": aircraft_id,
		"price_cents": price_cents,
		"fuel_litres": delivery_fuel,
		"airfield": current_airfield,
		"money_cents": money_cents
	}


func select_aircraft(aircraft_id: String) -> Dictionary:
	if _aircraft_spec(aircraft_id).is_empty():
		return _failure("Unknown aircraft.")
	if not active_trip.is_empty():
		return _failure("Aircraft cannot be switched while a trip is booked.")
	if not _is_valid_company_state(false):
		return _failure("Company state is invalid.")
	if not owned_aircraft.has(aircraft_id):
		return _failure("That aircraft is not owned.")
	var ledger_value: Variant = owned_aircraft[aircraft_id]
	if typeof(ledger_value) != TYPE_DICTIONARY:
		return _failure("Aircraft record is invalid.")
	var ledger: Dictionary = ledger_value
	if str(ledger.get("airfield", "")) != current_airfield:
		ledger["airfield"] = current_airfield
		owned_aircraft[aircraft_id] = ledger
	active_aircraft_id = aircraft_id
	return {
		"ok": true,
		"message": "Aircraft selected.",
		"aircraft_id": active_aircraft_id,
		"airfield": current_airfield,
		"fuel_litres": fuel_litres
	}


func cancel_trip() -> void:
	# Cancellation never changes money or revenue counters.
	active_trip = {}


func refuel(litres: float) -> Dictionary:
	if not is_finite(litres):
		return _failure("Fuel amount must be finite.")
	if litres < 0.0:
		return _failure("Fuel amount cannot be negative.")
	if not _is_valid_company_state(false):
		return _failure("Company state is outside the fuel limits.")
	var requested_total: float = fuel_litres + litres
	if requested_total > get_fuel_capacity() + FUEL_EPSILON:
		return _failure("That amount exceeds tank capacity.")
	var charge_cents: int = ceili(litres * float(FUEL_PRICE_CENTS))
	if charge_cents < 0 or charge_cents > money_cents:
		return _failure("Insufficient funds for fuel.")
	# A valid request is applied as one transaction: no partial fill or charge.
	fuel_litres = clampf(requested_total, 0.0, get_fuel_capacity())
	money_cents -= charge_cents
	return {
		"ok": true,
		"message": "Fuel purchased.",
		"litres": litres,
		"charge_cents": charge_cents,
		"fuel_litres": fuel_litres,
		"fuel_capacity": get_fuel_capacity(),
		"money_cents": money_cents
	}


func consume_fuel(litres: float) -> float:
	if not is_finite(litres) or litres <= 0.0:
		return 0.0
	var stored_fuel: float = _record_fuel(active_aircraft_id)
	var capacity: float = get_fuel_capacity()
	if not is_finite(stored_fuel) or stored_fuel <= 0.0 or stored_fuel > capacity + FUEL_EPSILON:
		return 0.0
	var consumed: float = minf(litres, stored_fuel)
	fuel_litres = clampf(stored_fuel - consumed, 0.0, capacity)
	return consumed


func reset_new_company() -> void:
	money_cents = STARTING_MONEY_CENTS
	active_aircraft_id = "heron"
	owned_aircraft = {
		"heron": {
			"fuel_litres": STARTING_FUEL_LITRES,
			"airfield": "mossvale"
		}
	}
	active_trip = {}
	completed_trips = 0
	total_revenue_cents = 0
	current_airfield = "mossvale"


func save(path: String = SAVE_PATH) -> Dictionary:
	if path.is_empty():
		return _failure("Save path cannot be empty.")
	if not _is_valid_company_state(true):
		return _failure("Company state is invalid and was not saved.")
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"money_cents": money_cents,
		"active_aircraft_id": active_aircraft_id,
		"owned_aircraft": owned_aircraft.duplicate(true),
		"current_airfield": current_airfield,
		"completed_trips": completed_trips,
		"total_revenue_cents": total_revenue_cents,
		"active_trip": active_trip.duplicate(true)
	}
	var encoded: String = JSON.stringify(payload, "\t")
	var parent: String = path.get_base_dir()
	var absolute_parent: String = ProjectSettings.globalize_path(parent)
	if not DirAccess.dir_exists_absolute(absolute_parent):
		var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_parent)
		if mkdir_error != OK:
			return _failure("Could not create the save directory.")
	var temp_path: String = path + ".tmp"
	var backup_path: String = path + ".bak"
	var absolute_temp: String = ProjectSettings.globalize_path(temp_path)
	var absolute_backup: String = ProjectSettings.globalize_path(backup_path)
	var absolute_path: String = ProjectSettings.globalize_path(path)
	# A stale temp file is never a valid save and can be safely replaced.
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(absolute_temp)
	var temp_file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if temp_file == null:
		return _failure("Could not open the temporary save file.")
	temp_file.store_string(encoded)
	var write_error: Error = temp_file.get_error()
	temp_file.close()
	if write_error != OK or not FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(absolute_temp)
		return _failure("Temporary save file could not be written.")
	# Validate the bytes on disk before moving any existing save. This catches
	# short writes and encoding/filesystem failures without touching live state.
	var temp_check: Dictionary = _read_save(temp_path)
	if not bool(temp_check.get("valid", false)):
		DirAccess.remove_absolute(absolute_temp)
		return _failure("Temporary save file failed validation.")

	var had_previous: bool = FileAccess.file_exists(path)
	var previous_check: Dictionary = _read_save(path) if had_previous else {"valid": false}
	var previous_valid: bool = bool(previous_check.get("valid", false))
	var backup_check: Dictionary = _read_save(backup_path)
	var backup_valid: bool = bool(backup_check.get("valid", false))
	if had_previous:
		if previous_valid:
			# Move the known-good primary into the recovery slot. A rename keeps
			# it intact if installing the new primary later fails.
			if FileAccess.file_exists(backup_path):
				DirAccess.remove_absolute(absolute_backup)
			var backup_error: Error = DirAccess.rename_absolute(absolute_path, absolute_backup)
			if backup_error != OK:
				# Copy is a less atomic fallback on platforms that refuse a rename.
				backup_error = DirAccess.copy_absolute(absolute_path, absolute_backup)
				if backup_error == OK and FileAccess.file_exists(path):
					DirAccess.remove_absolute(absolute_path)
			if backup_error != OK:
				DirAccess.remove_absolute(absolute_temp)
				return _failure("Could not preserve the previous save.")
		else:
			# Never demote a known-good backup over a corrupt/unknown primary.
			# The primary is disposable after the new temp bytes have passed
			# validation; the backup remains the recovery source.
			if not backup_valid and FileAccess.file_exists(backup_path):
				DirAccess.remove_absolute(absolute_backup)
			DirAccess.remove_absolute(absolute_path)
	var replace_error: Error = DirAccess.rename_absolute(absolute_temp, absolute_path)
	if replace_error != OK:
		# Restore a moved valid primary when replacement itself fails. For an
		# invalid primary, retain the valid backup so load can still recover.
		if previous_valid and FileAccess.file_exists(backup_path) and not FileAccess.file_exists(path):
			DirAccess.rename_absolute(absolute_backup, absolute_path)
		DirAccess.remove_absolute(absolute_temp)
		return _failure("Could not atomically install the save.")
	return {
		"ok": true,
		"message": "Company saved.",
		"path": path,
		"backup_path": backup_path if previous_valid or backup_valid else ""
	}


func load_save(path: String = SAVE_PATH) -> Dictionary:
	if path.is_empty():
		return _failure("Save path cannot be empty.")
	var primary: Dictionary = _read_save(path)
	if bool(primary.get("valid", false)):
		_apply_loaded_state(primary["state"])
		return {
			"ok": true,
			"message": "Company loaded.",
			"path": path,
			"migrated_from_version": int(primary.get("migrated_from_version", SAVE_VERSION)),
			"unfinished_trip_canceled": bool(primary.get("had_active_trip", false))
		}

	var backup_path: String = path + ".bak"
	var backup: Dictionary = _read_save(backup_path)
	if bool(backup.get("valid", false)):
		_apply_loaded_state(backup["state"])
		return {
			"ok": true,
			"message": "Primary save was invalid; backup loaded.",
			"path": backup_path,
			"used_backup": true,
			"migrated_from_version": int(backup.get("migrated_from_version", SAVE_VERSION)),
			"unfinished_trip_canceled": bool(backup.get("had_active_trip", false))
		}

	var primary_missing: bool = not FileAccess.file_exists(path)
	var backup_missing: bool = not FileAccess.file_exists(backup_path)
	if primary_missing and backup_missing:
		reset_new_company()
		return {
			"ok": true,
			"message": "No save found; started a new company.",
			"missing": true
		}
	# Parse and validation happened without touching live fields. Keep the
	# current company intact when both existing copies are malformed.
	return _failure("Save file is malformed; current company was kept.")


func _apply_loaded_state(state: Dictionary) -> void:
	money_cents = int(state["money_cents"])
	owned_aircraft = (state["owned_aircraft"] as Dictionary).duplicate(true)
	active_aircraft_id = str(state["active_aircraft_id"])
	current_airfield = str(state["current_airfield"])
	completed_trips = int(state["completed_trips"])
	total_revenue_cents = int(state["total_revenue_cents"])
	# This stage has no in-air persistence. An unfinished contract is canceled
	# on reload and never pays out.
	active_trip = {}


func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"valid": false, "missing": true}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"valid": false, "missing": false}
	if file.get_length() > 1048576:
		file.close()
		return {"valid": false, "missing": false}
	var text: String = file.get_as_text()
	file.close()
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		return {"valid": false, "missing": false}
	var decoded: Variant = parser.data
	if typeof(decoded) != TYPE_DICTIONARY:
		return {"valid": false, "missing": false}
	var state: Dictionary = _decode_save(decoded)
	if not bool(state.get("valid", false)):
		return {"valid": false, "missing": false}
	return state


func _decode_save(data: Dictionary) -> Dictionary:
	if not data.has("version") or not _is_nonnegative_int(data["version"], SAVE_VERSION):
		return {"valid": false}
	var version: int = int(data["version"])
	if version == LEGACY_SAVE_VERSION:
		return _decode_v1_save(data)
	if version == SAVE_VERSION:
		return _decode_v2_save(data)
	return {"valid": false}


func _decode_v1_save(data: Dictionary) -> Dictionary:
	if not _has_exact_keys(data, SAVE_FIELDS_V1):
		return {"valid": false}
	if not _is_nonnegative_int(data["version"], LEGACY_SAVE_VERSION) or int(data["version"]) != LEGACY_SAVE_VERSION:
		return {"valid": false}
	if not _is_nonnegative_int(data["money_cents"], MAX_MONEY_CENTS):
		return {"valid": false}
	if not _is_finite_number(data["fuel_litres"]):
		return {"valid": false}
	var decoded_fuel: float = float(data["fuel_litres"])
	if decoded_fuel < 0.0 or decoded_fuel > FUEL_CAPACITY:
		return {"valid": false}
	if typeof(data["current_airfield"]) != TYPE_STRING or not _is_valid_airfield(str(data["current_airfield"])):
		return {"valid": false}
	if not _is_nonnegative_int(data["completed_trips"], MAX_COMPLETED_TRIPS):
		return {"valid": false}
	if not _is_nonnegative_int(data["total_revenue_cents"], MAX_TOTAL_REVENUE_CENTS):
		return {"valid": false}
	if typeof(data["active_trip"]) != TYPE_DICTIONARY:
		return {"valid": false}
	var decoded_trip: Dictionary = data["active_trip"]
	var current: String = str(data["current_airfield"])
	var had_active: bool = not decoded_trip.is_empty()
	if had_active and not _is_valid_legacy_trip(decoded_trip, current):
		return {"valid": false}
	return {
		"valid": true,
		"migrated_from_version": LEGACY_SAVE_VERSION,
		"state": {
			"money_cents": int(data["money_cents"]),
			"active_aircraft_id": "heron",
			"owned_aircraft": {
				"heron": {
					"fuel_litres": decoded_fuel,
					"airfield": current
				}
			},
			"current_airfield": current,
			"completed_trips": int(data["completed_trips"]),
			"total_revenue_cents": int(data["total_revenue_cents"])
		},
		"had_active_trip": had_active
	}


func _decode_v2_save(data: Dictionary) -> Dictionary:
	if not _has_exact_keys(data, SAVE_FIELDS_V2):
		return {"valid": false}
	if not _is_nonnegative_int(data["version"], SAVE_VERSION) or int(data["version"]) != SAVE_VERSION:
		return {"valid": false}
	if not _is_nonnegative_int(data["money_cents"], MAX_MONEY_CENTS):
		return {"valid": false}
	if typeof(data["active_aircraft_id"]) != TYPE_STRING:
		return {"valid": false}
	var decoded_active_id: String = str(data["active_aircraft_id"])
	if typeof(data["current_airfield"]) != TYPE_STRING or not _is_valid_airfield(str(data["current_airfield"])):
		return {"valid": false}
	var current: String = str(data["current_airfield"])
	if not _is_nonnegative_int(data["completed_trips"], MAX_COMPLETED_TRIPS):
		return {"valid": false}
	if not _is_nonnegative_int(data["total_revenue_cents"], MAX_TOTAL_REVENUE_CENTS):
		return {"valid": false}
	if typeof(data["owned_aircraft"]) != TYPE_DICTIONARY:
		return {"valid": false}
	var decoded_owned: Dictionary = data["owned_aircraft"]
	if not _is_valid_aircraft_records(decoded_owned, decoded_active_id, current):
		return {"valid": false}
	if typeof(data["active_trip"]) != TYPE_DICTIONARY:
		return {"valid": false}
	var decoded_trip: Dictionary = data["active_trip"]
	var had_active: bool = not decoded_trip.is_empty()
	if had_active and not _is_valid_trip(decoded_trip, current, decoded_active_id, decoded_owned):
		return {"valid": false}
	return {
		"valid": true,
		"migrated_from_version": SAVE_VERSION,
		"state": {
			"money_cents": int(data["money_cents"]),
			"active_aircraft_id": decoded_active_id,
			"owned_aircraft": decoded_owned.duplicate(true),
			"current_airfield": current,
			"completed_trips": int(data["completed_trips"]),
			"total_revenue_cents": int(data["total_revenue_cents"])
		},
		"had_active_trip": had_active
	}


func _is_valid_company_state(require_trip_validation: bool) -> bool:
	if money_cents < 0 or money_cents > MAX_MONEY_CENTS:
		return false
	if not _is_valid_airfield(current_airfield):
		return false
	if completed_trips < 0 or completed_trips > MAX_COMPLETED_TRIPS:
		return false
	if total_revenue_cents < 0 or total_revenue_cents > MAX_TOTAL_REVENUE_CENTS:
		return false
	if not _is_valid_aircraft_records(owned_aircraft, active_aircraft_id, current_airfield):
		return false
	if require_trip_validation and not active_trip.is_empty():
		return _is_valid_trip(active_trip, current_airfield, active_aircraft_id, owned_aircraft)
	return true


func _is_valid_aircraft_records(records: Dictionary, selected_id: String, current: String) -> bool:
	if records.is_empty() or records.size() > AircraftCatalog.DATA.size():
		return false
	if not records.has("heron") or not records.has(selected_id):
		return false
	if not AircraftCatalog.DATA.has(selected_id):
		return false
	for key: Variant in records.keys():
		if typeof(key) != TYPE_STRING:
			return false
		var aircraft_id: String = str(key)
		if not AircraftCatalog.DATA.has(aircraft_id):
			return false
		var ledger_value: Variant = records[key]
		if typeof(ledger_value) != TYPE_DICTIONARY:
			return false
		var ledger: Dictionary = ledger_value
		if not _has_exact_keys(ledger, AIRCRAFT_LEDGER_FIELDS):
			return false
		if not _is_finite_number(ledger["fuel_litres"]):
			return false
		var spec: Dictionary = _aircraft_spec(aircraft_id)
		var fuel_value: float = float(ledger["fuel_litres"])
		var capacity: float = float(spec.get("fuel_capacity", 0.0))
		if fuel_value < 0.0 or fuel_value > capacity:
			return false
		if typeof(ledger["airfield"]) != TYPE_STRING or not _is_valid_airfield(str(ledger["airfield"])):
			return false
		if aircraft_id == selected_id and str(ledger["airfield"]) != current:
			return false
	return true


func _is_valid_legacy_trip(trip: Dictionary, expected_origin: String) -> bool:
	if not _has_exact_keys(trip, LEGACY_TRIP_FIELDS):
		return false
	if typeof(trip["origin"]) != TYPE_STRING or typeof(trip["destination"]) != TYPE_STRING:
		return false
	var origin: String = str(trip["origin"])
	var destination: String = str(trip["destination"])
	if not _is_valid_airfield(origin) or not _is_valid_airfield(destination):
		return false
	if origin == destination or origin != expected_origin:
		return false
	if not _is_nonnegative_int(trip["seats"], 3) or int(trip["seats"]) <= 0:
		return false
	if not _is_nonnegative_int(trip["fare_cents"], MAX_FARE_CENTS) or int(trip["fare_cents"]) <= 0:
		return false
	if not _is_nonnegative_int(trip["payout_cents"], MAX_TOTAL_REVENUE_CENTS) or int(trip["payout_cents"]) <= 0:
		return false
	var seats: int = int(trip["seats"])
	var fare: int = int(trip["fare_cents"])
	return seats == _quote_seats_for_aircraft("heron", fare) and int(trip["payout_cents"]) == seats * fare


func _is_valid_trip(trip: Dictionary, expected_origin: String, expected_aircraft_id: String, records: Dictionary) -> bool:
	if not _has_exact_keys(trip, TRIP_FIELDS):
		return false
	if typeof(trip["aircraft_id"]) != TYPE_STRING:
		return false
	if typeof(trip["origin"]) != TYPE_STRING or typeof(trip["destination"]) != TYPE_STRING:
		return false
	var aircraft_id: String = str(trip["aircraft_id"])
	var origin: String = str(trip["origin"])
	var destination: String = str(trip["destination"])
	if aircraft_id != expected_aircraft_id or not records.has(aircraft_id):
		return false
	if not _is_valid_airfield(origin) or not _is_valid_airfield(destination):
		return false
	if origin == destination or origin != expected_origin:
		return false
	if not _is_nonnegative_int(trip["seats"], MAX_SEATS) or int(trip["seats"]) <= 0:
		return false
	if not _is_nonnegative_int(trip["fare_cents"], MAX_FARE_CENTS) or int(trip["fare_cents"]) <= 0:
		return false
	if not _is_nonnegative_int(trip["payout_cents"], MAX_TOTAL_REVENUE_CENTS) or int(trip["payout_cents"]) <= 0:
		return false
	var seats: int = int(trip["seats"])
	var fare: int = int(trip["fare_cents"])
	return seats == _quote_seats_for_aircraft(aircraft_id, fare) and int(trip["payout_cents"]) == seats * fare


func _quote_seats_for_aircraft(aircraft_id: String, fare_cents: int) -> int:
	if fare_cents <= 0 or fare_cents > MAX_FARE_CENTS:
		return 0
	var capacity: int = int(_aircraft_spec(aircraft_id).get("passenger_seats", 0))
	if capacity == 3:
		if fare_cents <= 4500:
			return 3
		if fare_cents <= 7500:
			return 2
		return 1
	if capacity == 5:
		if fare_cents <= 4500:
			return 5
		if fare_cents <= 7500:
			return 4
		return 2
	if capacity == 9:
		if fare_cents <= 4500:
			return 9
		if fare_cents <= 7500:
			return 7
		return 4
	if capacity == 15:
		if fare_cents <= 4500:
			return 15
		if fare_cents <= 7500:
			return 12
		return 7
	return 0


func _aircraft_spec(aircraft_id: String) -> Dictionary:
	if not AircraftCatalog.DATA.has(aircraft_id):
		return {}
	var spec: Dictionary = AircraftCatalog.DATA[aircraft_id]
	return spec


func _record_fuel(aircraft_id: String) -> float:
	if not owned_aircraft.has(aircraft_id):
		return NAN
	var ledger_value: Variant = owned_aircraft[aircraft_id]
	if typeof(ledger_value) != TYPE_DICTIONARY:
		return NAN
	var ledger: Dictionary = ledger_value
	var fuel_value: Variant = ledger.get("fuel_litres", NAN)
	if not _is_finite_number(fuel_value):
		return NAN
	return float(fuel_value)


func _move_active_aircraft_to(airfield: String) -> void:
	var ledger: Dictionary = owned_aircraft[active_aircraft_id]
	ledger["airfield"] = airfield
	owned_aircraft[active_aircraft_id] = ledger
	current_airfield = airfield


func _is_valid_airfield(airfield: String) -> bool:
	return AIRFIELDS.has(airfield)


func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


func _is_nonnegative_int(value: Variant, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var numeric: float = float(value)
	if not is_finite(numeric):
		return false
	return numeric >= 0.0 and numeric <= float(maximum) and numeric == floor(numeric)


func _has_exact_keys(data: Dictionary, expected: PackedStringArray) -> bool:
	if data.size() != expected.size():
		return false
	for key: String in expected:
		if not data.has(key):
			return false
	return true


func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
