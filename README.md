# Mossvale Air Service (모스베일 항공 서비스)

A 3D regional aviation business and flight simulation game built with **Godot 4** and **Blender**. Start with a single 4-seat bush plane at Mossvale Airfield, sell passenger tickets, manage fuel, fly through scenic mountain valleys across four regional airfields, and expand your airline fleet up to a 16-seat twin-turboprop commuter airliner.

---

## Key Features

### 1. Four-Aircraft Fleet Progression (`◆ Fleet / 격납고`)
Walk onto the apron to see all four aircraft parked in 3D, or open the **Fleet Hangar** to purchase and switch planes:
| Aircraft | Configuration | Passenger Seats | Fuel Capacity | Cruise Speed | Price |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **MV-4 Heron** | High-wing single-prop utility bush plane | 3 (+1 pilot) | 80 L | ~155 km/h | Starter ($0) |
| **MV-6 Osprey** | Twin-engine high-wing mountain commuter | 5 (+1 pilot) | 120 L | ~185 km/h | $1,100 |
| **MV-10 Albatross** | Twin-engine cabin regional liner | 9 (+1 pilot) | 200 L | ~210 km/h | $1,800 |
| **MV-16 Skywhale** | Heavy twin-turboprop T-tail airliner | 15 (+1 pilot) | 320 L | ~235 km/h | $3,200 |

### 2. Four Regional Airfields & 3D Sky Route Rings
Fly passenger contracts across a sculpted 2 km × 2 km mountain valley with four distinct airfields:
- **Mossvale Airfield (모스베일)** — Main valley hub with timber hangar, fuel pump, and passenger pavilion (`0 m` elevation).
- **Birch Hollow Strip (버치 할로우)** — Northern mountain terrace airstrip (`24 m` elevation).
- **Pine Ridge Strip (파인 리지 고원)** — Eastern highland plateau runway (`36 m` elevation).
- **Mirror Lake Landing (미러 레이크)** — Southwestern lakeside meadow strip (`12 m` elevation).

Each route features **3D Golden Sky Rings (`◎`)**, a **Flight-Path Vector (FPV)** HUD predictor, a **Runway Touchdown Beacon**, and a live **Valley Radar (`항로 레이더`)** mini-map.

### 3. Airline Economy & Landing Grades
- **Passenger Fares:** Choose between `$45` (guaranteed full cabin), `$75` (medium demand), or `$110` (premium fare) per passenger seat.
- **Fuel Management:** Buy fuel in `10 L` increments (`$2.20 / L`) or top up the entire tank with one click at any airfield.
- **Landing Evaluation:** Touchdown vertical speed is graded (`S` Butter Landing `+$45`, `A` Smooth Landing `+$25`, `B` Safe Landing) and credited automatically upon stopping on the destination runway.
- **Resilient Persistence:** Company state saves automatically to `user://company_v1.json` with `.bak` backup validation.

### 4. Bilingual UI (한국어 / English) & Dynamic Atmosphere
- Press **`L`** at any time to toggle between **Korean (한국어)** and **English**, rendered with an embedded `Noto Sans KR Medium` font covering full KS X 1001 Hangul syllables and geometric HUD symbols.
- Press **`T` / `Shift+T`** to cycle through 5 lighting presets (**Morning**, **Midday**, **Golden Hour**, **Blue Hour**, **Night**) and **`R`** to toggle rain showers and wet runway reflections.

---

## Controls

### On Foot (Third-Person Pilot)
- **`WASD` / Arrow Keys**: Walk (`Shift` to run, `Space` to jump)
- **`Right Mouse Button` (Hold)**: Rotate camera around pilot
- **`B`**: Open Flight Desk (choose destination airfield, sell passenger seats, refuel, open Fleet Hangar)
- **`E`**: Board aircraft (or auto-walk to the aircraft boarding door from anywhere on the apron)
- **`F`**: One-click quick book, board, and line up on the departure runway

### In Flight (Third-Person Chase Camera)
- **`W` / `S`**: Increase / reduce throttle (`W` automatically starts the engine on the runway)
- **`A` / `D`** or **`←` / `→`**: Steer on the ground and bank/turn in the air
- **`↑` (Up Arrow)**: Raise nose / **Climb altitude (고도 상승)**
- **`↓` (Down Arrow)**: Lower nose / **Descend altitude (고도 하강)**
- **`Space`**: Wheel brakes on the runway (lift assist during takeoff roll)
- **`G`**: Toggle Smart Co-Pilot Flight Assist (auto-level & gentle route alignment)
- **`F`**: Align immediately on the nearest departure runway
- **`Backspace` / `Home`**: Safely reset to the current airfield apron

### Global Shortcuts
- **`L`**: Switch Language (`한국어` / `English`)
- **`T` / `Shift+T`**: Next / previous time of day
- **`R`**: Toggle rain weather
- **`C`**: Toggle Photo Mode (`V` cycles composed camera views)
- **`F1`**: Controls Help overlay
- **`H`**: Toggle HUD visibility
- **`F11`**: Toggle Fullscreen

---

## Project Structure

```text
AviationGame/
├── game/                        # Godot 4 project root (project.godot)
│   ├── main.gd                  # World builder, terrain, 4 airfields, atmosphere & HUD
│   ├── flight_session.gd        # Airline loop, Flight Desk UI, HUD telemetry & payouts
│   ├── navigation_guide.gd      # 3D sky route rings, ground trail & FPV HUD marker
│   ├── aircraft_controller.gd   # Flight physics, Co-Pilot assist & procedural engine audio
│   ├── aircraft_catalog.gd      # Specs for Heron, Osprey, Albatross & Skywhale
│   ├── fleet_panel.gd           # 4-aircraft Fleet Hangar purchase & selection UI
│   ├── company_state.gd         # Economy, bookings, fuel & save/backup persistence
│   ├── airfields.gd             # Coordinates & terrain flattening for all 4 airfields
│   ├── valley_map.gd            # Live top-right Valley Radar mini-map
│   ├── first_person_controller.gd # Third-person pilot movement & auto-walk
│   ├── first_person_body.gd     # Articulated pilot mesh animation
│   ├── i18n.gd                  # Korean/English localization helper
│   ├── assets/                  # Exported .glb 3D models & Noto Sans KR UI font
│   ├── audio/                   # Synthesized engine & footstep .wav audio
│   └── shaders/                 # Custom sky, terrain, grass & detail .gdshader files
├── art/
│   └── source/                  # Original editable Blender (.blend) source files
└── tools/
    ├── blender/                 # Python scripts to procedurally build all Blender assets
    ├── check_company_state.gd   # Headless economy & save-state verification suite
    ├── check_fleet_expansion.gd # Headless 4-aircraft fleet & flight verification suite
    └── check_preview_controls.gd# Headless UI, atmosphere & controls verification suite
```

---

## Running From Source & Verification

1. Open `game/project.godot` in **Godot 4.3+** (tested with Godot 4.7).
2. Press **F5** to launch the game.
3. Run the automated headless verification suites from the command line:

```bash
godot --headless --path game --script ../tools/check_company_state.gd
godot --headless --path game --script ../tools/check_fleet_expansion.gd
godot --headless --path game --script ../tools/check_preview_controls.gd
godot --headless --path game -- --walk-check
godot --headless --path game -- --flight-check
```
