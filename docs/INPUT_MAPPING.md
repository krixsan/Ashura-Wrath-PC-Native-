# Input Architecture & Control Mapping — Asura's Wrath (`BLUS30721`)

## 1. Input Backend Confirmation
- The Windows D3D12 build uses **Windows XInput** (`XInput1_4.dll` / `XInput1_3.dll` / `XInput9_1_0.dll`) for physical gamepads (ports `0..3`) and **Win32 `GetAsyncKeyState`** keyboard fallback on Port 0.
- **SDL3 / SDL2 is NOT used** in the PS3 build (`PAD_BACKEND_XINPUT = 1`). PlayStation DualShock/DualSense controllers must run through an XInput wrapper (such as Steam Input or DS4Windows).
- Keyboard fallback only triggers when **no XInput controller** occupies slot 0 and the **`Asura's Wrath` window has OS focus** (`Alt+Tab` centers sticks to `128` and clears held keys).

---

## 2. Keyboard -> PS3 DualShock 3 Mapping (Port 0)

> **Important:** The `ps3recomp` keyboard scheme is **NOT WASD**!
> - **Left Stick + D-Pad** share the **`Arrow Keys`**.
> - **Right Stick** uses **`I / J / K / L`**.
> - **`W` / `A` / `S`** are mapped to **`R1` / `Square` / `Triangle`** respectively.

| Category | PS3 DualShock 3 | Windows Keyboard Key | Analog / Pressure Behavior |
| :--- | :--- | :--- | :--- |
| **D-Pad + Left Stick** | `Up` / `L↑` | **`Up Arrow`** | `LY = 0`, `press_up = 255` |
| **D-Pad + Left Stick** | `Down` / `L↓` | **`Down Arrow`** | `LY = 255`, `press_down = 255` |
| **D-Pad + Left Stick** | `Left` / `L←` | **`Left Arrow`** | `LX = 0`, `press_left = 255` |
| **D-Pad + Left Stick** | `Right` / `L→` | **`Right Arrow`** | `LX = 255`, `press_right = 255` |
| **Right Stick** | `R↑` / `R↓` | **`I`** / **`K`** | `RY = 0` (`I`) or `255` (`K`) |
| **Right Stick** | `R←` / `R→` | **`J`** / **`L`** | `RX = 0` (`J`) or `255` (`L`) |
| **Face Buttons** | `Cross` (`×`, Confirm / Melee) | **`Z`** | `press_cross = 255` |
| **Face Buttons** | `Circle` (`○`, Cancel / Burst) | **`X`** | `press_circle = 255` |
| **Face Buttons** | `Square` (`□`, Shoot) | **`A`** | `press_square = 255` |
| **Face Buttons** | `Triangle` (`△`, Heavy Attack) | **`S`** | `press_triangle = 255` |
| **Shoulders** | `L1` / `R1` | **`Q`** / **`W`** | `press_l1` / `press_r1 = 255` |
| **Triggers** | `L2` / `R2` | **`1`** / **`2`** *(top row)* | `press_l2` / `press_r2 = 255` |
| **Stick Clicks** | `L3` / `R3` | **`3`** / **`4`** *(top row)* | Digital click |
| **System** | `START` / `SELECT` | **`Enter`** / **`Right Shift`** | Digital |

- **Episode 1 QTE Tip:** Prompt **`L↓ + R↓`** requires pressing **`Down Arrow + K`** together on keyboard (or pulling both analog sticks straight down on an XInput gamepad).
