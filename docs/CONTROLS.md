# DroneAcharya — Controls

The in-game reference is the same list:

- `simulator/scripts/ui/controls_reference.gd`, shown on the briefings and under **Esc → Controls**.
- `simulator/tests/test_input_map.gd` checks every key below, and checks that no physical key is bound to two actions.

## Menus

| Input | Action |
|---|---|
| Mouse | Click buttons, list rows and options |
| Tab / arrow keys + Enter | Move between buttons and press one (menus and pause screens) |
| Esc (in a mission or exercise) | Open or close the pause menu: Resume, Restart, Controls, Settings, (Tutorial), Back to menu |

In-game buttons never keep keyboard focus. Space, Enter and the arrow keys used for flying or deciding therefore cannot press a button by accident.

## Flight training

| Key | Action |
|---|---|
| W / S | Forward / back |
| A / D | Sideways left / right |
| Q / E | Turn left / right |
| Space / C | Climb / descend |
| V | Chase camera / onboard camera |
| R | Restart the mission (same drone profile; clock, battery and integrity reset) |
| Esc | Pause menu |
| Radar "Legend" button | Show what each radar symbol means |

**Ground stability:** releasing all keys holds position (assisted flight). Below 0.3 m with no climb input, the drone settles onto the ground.

## Threat detection (observation post)

### Mouse-first workflow

| Mouse | Action |
|---|---|
| Hover a marker | Short tooltip: contact id, range, "click to select" |
| **Left click** a marker, a radar symbol or a Contacts row | Select the contact; the decision card binds to it. A swarm group row selects its first member |
| Left click an option in the decision card | Highlight that option |
| **Mouse wheel** | With a contact selected: move the highlighted option (classification, then response). With nothing selected: zoom |
| **Right click** (press and release without moving) | Confirm the highlighted option |
| Right drag | Look around (never confirms anything) |
| Shift + wheel | Zoom, even while a contact is selected |

### Keyboard equivalents

| Key | Action |
|---|---|
| Tab | Next contact |
| ↑ / ↓ | Move the highlighted option |
| Enter (or K) | Confirm the highlighted option |
| Backspace | Back one step (confirmation → response → classification → deselect) |
| 1 / 2 / 3 | Confidence low 30 % / medium 60 % / high 90 % |
| F | Mark the selected contact as seen, without classifying |
| W A S D | Look around |
| = / - | Zoom in / out |
| V | Eye view / simulated sensor camera |
| R | Restart the exercise |
| Esc | Pause menu |

### How a decision works

1. **Classify.** Wheel or ↑/↓ to the category, optionally 1/2/3 for confidence, then right-click or Enter.
   - A contact not yet marked as seen is marked seen in the same step. This is logged as its own acknowledge action, so detection time is still measured.
2. **Respond.** Wheel to the response, then right-click or Enter.
   - Routine responses (continue observing, request identification, log) are submitted at once.
   - **Alarm responses** (notify the supervisor, training-area alert) show a confirmation with the consequence. They are submitted only by a second explicit Confirm (button, right-click or Enter). Cancel or Backspace goes back.
3. The response is **final** for that contact. A second confirmation within 0.35 s, or any confirmation after the final response, is ignored by the card and not counted as a repeated action.

**Scope:** the card always states what a decision applies to.

- Normally it is "this contact only".
- When the category is *Coordinated swarm*, it is "the whole swarm group (n contacts: …)".

## Settings that affect controls

Settings → **Mouse look sensitivity** scales right-drag looking (0.25×–3×).
