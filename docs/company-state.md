# Company state

`game/company_state.gd` is a deterministic `RefCounted` economy and persistence module. It has no scene, UI, flight-physics, network or real-money dependencies. Callers own flight validation and choose when to call `save()`; no method autosaves.

## Economy rules

- A new company starts with `120000` cents, `40.0` litres, no trips, no revenue and `current_airfield == "mossvale"`.
- The allowed airfields are `mossvale` and `birch_hollow`.
- The four-seat aircraft has one pilot seat, so at most three seats pay. `quote_seats()` returns 3 seats through 4500 cents, 2 seats through 7500 cents, 1 seat through 14000 cents, and 0 above 14000 cents or for non-positive fares. A booked fare must be positive and have at least one paying seat.
- `book_trip()` requires the origin to be the current airfield, different endpoints, and no active contract. It stores `origin`, `destination`, `seats`, `fare_cents` and `payout_cents`.
- The flight layer must verify takeoff, touchdown and parking before calling `complete_trip(destination)`. Completion checks the booked destination, credits the payout once, updates revenue/trip counters, moves the current airfield and clears the contract. A second call cannot pay again.
- `arrive_at()` is for a free flight with no contract. It rejects every arrival while a contract is active; the contract path is `complete_trip()` after the flight layer's landing checks. `cancel_trip()` clears the contract without payout.
- Fuel is capped at 80 litres and costs 220 cents per litre. `refuel()` rejects non-finite, negative, over-capacity or unaffordable requests and applies a valid request atomically. Fractional-litre charges use ceiling-to-the-next-cent. `consume_fuel()` returns the actual finite positive amount consumed, clamped to available fuel; invalid amounts return `0.0`.

## Save schema

`save()` writes version 1 JSON to `user://company_v1.json` by default. The schema has exactly these fields:

```json
{
  "version": 1,
  "money_cents": 120000,
  "fuel_litres": 40.0,
  "current_airfield": "mossvale",
  "completed_trips": 0,
  "total_revenue_cents": 0,
  "active_trip": {}
}
```

An active trip, when present, has exactly `origin`, `destination`, `seats`, `fare_cents` and `payout_cents`; it is validated against the current airfield, demand curve and payout calculation. Integer JSON values are accepted as either Godot integer or finite integral numeric variants because Godot's JSON parser may decode whole numbers as floats. Fractions, strings, non-finite numbers, negative values, unknown fields, invalid airfield IDs and values above the bounded limits are rejected.

Saving writes a temporary file, checks the write status and validates the stored bytes before installing it with a rename. Rotation preserves a valid `.bak` even when the primary was corrupt; loading tries the primary file first and then the backup. A valid load restores money, fuel, current airfield and completed statistics. Any unfinished contract is deliberately canceled because this stage does not persist an aircraft in the air. A missing primary and backup starts a normal new company. If existing copies are malformed, the live company is left untouched and an error dictionary is returned. The session blocks autosaving after that failure. Normal close saves immediately; forced termination can lose up to the last ten seconds of fuel consumption between periodic checkpoints.

The headless check is run from `AviationGame` with:

```text
Godot_v4.7-stable_win64_console.exe --headless --path game --script ../tools/check_company_state.gd
```

The check uses only `art/previews/company_state_test.json` and its `.tmp`/`.bak` siblings, and removes them before exit.
