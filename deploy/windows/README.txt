DroneAcharya Simulator — Windows build
Version: {VERSION} (source commit {COMMIT})

Synthetic drone flight and counter-drone threat-detection training prototype.
Every place, contact and sensor is simulated. Not an operational system.

REQUIREMENTS
  Windows 10 or 11, 64-bit.
  A current graphics driver with Vulkan support (tested). Without Vulkan the
  engine is designed to fall back to Direct3D 12 or OpenGL 3.3 (untested).
  About 120 MB of disk space. Keyboard and mouse.
  No installation, internet connection, Python or Godot editor is needed.
  The trained ML classifier is built in and runs offline.

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
  does not delete them. The program folder itself can be anywhere and can
  be read-only; nothing is written into it.

TROUBLESHOOTING
  Nothing happens / the window closes at once:
    Check %APPDATA%\DroneAcharya\logs\godot.log for lines with "ERROR".
    Update the graphics driver. To force a renderer, run from PowerShell:
      .\DroneAcharya.exe --rendering-driver d3d12
      .\DroneAcharya.exe --rendering-method gl_compatibility   (OpenGL)
  A message about Vulkan or graphics drivers: update the graphics driver,
    or start with one of the two commands above.
  Slow or jerky: Settings -> Effects quality -> Reduced. Close other 3D programs.
  Keys stop working: click once inside the game window.
  The window is too big for the screen: start it with --resolution 1366x768.
  Decision support says "ML classifier unavailable": the build is damaged;
    extract the ZIP again. Decision support keeps working with the
    rule-based baseline and says so.

KNOWN LIMITATIONS
  Training prototype: all places, contacts and sensors are synthetic. The ML
  classifier's accuracy describes the simulator's own data, not real-world
  recognition, and its scores are not calibrated probabilities.
  Not code-signed, so SmartScreen warns on first run.
  Tested on one PC only: Windows 11, Intel Core Ultra 5 125H, Intel Arc
  integrated graphics, 16 GB RAM.

LICENCES
  Built with the Godot Engine (MIT licence): see GODOT_LICENSE.txt.
