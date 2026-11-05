extends RefCounted
## Shared aircraft specifications used by the company and flight layers.

const DATA: Dictionary = {
	"heron": {
		"name": "MV–4 Heron",
		"asset": "heron_mv4",
		"passenger_seats": 3,
		"fuel_capacity": 80.0,
		"price_cents": 0,
		"purchase_fuel": 40.0,
		"takeoff_speed": 20.0,
		"stall_speed": 18.0,
		"thrust": 5.8,
		"idle_burn": 5.0,
		"full_burn": 24.0
	},
	"osprey": {
		"name": "MV–6 Osprey",
		"asset": "osprey_mv6",
		"passenger_seats": 5,
		"fuel_capacity": 120.0,
		"price_cents": 110000,
		"purchase_fuel": 60.0,
		"takeoff_speed": 21.5,
		"stall_speed": 19.0,
		"thrust": 6.8,
		"idle_burn": 7.0,
		"full_burn": 34.0
	},
	"albatross": {
		"name": "MV–10 Albatross",
		"asset": "albatross_mv10",
		"passenger_seats": 9,
		"fuel_capacity": 200.0,
		"price_cents": 180000,
		"purchase_fuel": 100.0,
		"takeoff_speed": 22.0,
		"stall_speed": 19.0,
		"thrust": 7.8,
		"idle_burn": 9.0,
		"full_burn": 44.0
	},
	"skywhale": {
		"name": "MV–16 Skywhale",
		"asset": "skywhale_mv16",
		"passenger_seats": 15,
		"fuel_capacity": 320.0,
		"price_cents": 320000,
		"purchase_fuel": 160.0,
		"takeoff_speed": 23.0,
		"stall_speed": 19.5,
		"thrust": 9.2,
		"idle_burn": 12.0,
		"full_burn": 58.0
	}
}
