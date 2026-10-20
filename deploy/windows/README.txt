DroneAcharya Simulator — Windows build
Version: {VERSION} (source commit {COMMIT})

Synthetic drone flight and counter-drone threat-detection training prototype.
Every place, contact and sensor is simulated. Not an operational system.

REQUIREMENTS
  Windows 10 or 11, 64-bit, with a graphics driver that supports Vulkan.
  No installation, internet connection, Python or Godot editor is needed.

START
  1. Extract the whole ZIP to a folder (do not run it from inside the ZIP).
  2. Double-click DroneAcharya.exe.
     If Windows SmartScreen says "Windows protected your PC", click
     "More info" and then "Run anyway" (the program is not code-signed).
  Optional, from PowerShell in this folder:
     .\DroneAcharya.exe --resolution 1366x768     (smaller window)
     .\DroneAcharya.exe --fullscreen

CONTROLS
  Flight training
    Space / C   climb / descend        W / S   forward / back
    A / D       sideways               Q / E   turn
    V           chase / onboard camera R       restart mission
    Esc         pause menu (controls, settings, back to menu)
  Threat detection training
    Left click   select a contact (marker, radar symbol or list row)
    Mouse wheel  change the highlighted option on the decision card
    Right click  confirm (alarms ask once more)
    Right drag or W A S D  look around     Shift + wheel  zoom
    Tab / Up / Down / Enter / Backspace  keyboard alternative
    V  simulated sensor camera      Esc  pause menu

YOUR DATA
  Settings, reports and logs are saved in %APPDATA%\DroneAcharya\
  (paste that into the Explorer address bar). Deleting the program folder
  does not delete them.

LICENCES
  Built with the Godot Engine (MIT licence): see GODOT_LICENSE.txt.
