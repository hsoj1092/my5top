# my5top — Cute/Anime NJ Transit Commute Assistant 🚆✨

A 100% free, local-first Flutter Android app designed for daily NJ Transit rail commutes (pre-configured with **NY Penn Station (`NY`) — Work** and **Metropark (`MP`) — Home**, plus the full NJ Transit rail network).

## Key Features
- **Live NJ Transit Departures & Track Assignments**: View upcoming Express & Local trains, track numbers (`TRACK 9`, `TRACK 7`), and toggle **Watch Track** on `TRACK TBA` trains to receive an immediate high-priority alert the moment DepartureVision posts your track.
- **1-Tap Commute Presets**: Instant **To Home (`NY → MP`)** and **To Work (`MP → NY`)** route switching + station picker for all NJ Transit stations.
- **"I'm on this train!" Active Ride Mode**:
  - Animated Chibi Train car gliding along the stop timeline.
  - **Hybrid GPS + API Stop Countdown**: Combines on-device GPS station geofencing with NJ Transit stop departure updates so it works both underground in NY Penn / Hudson tunnels and above ground in NJ with zero lag.
  - **Interactive Commute Simulator**: Step through stops (`+1 Stop`) or auto-play a ride to test animations and stop notifications anytime.
- **Customizable Stop Notifications**:
  - Choose **"Start notifying me X stops away"** ($1$–$6$ stops before destination).
  - Toggle **"Notify on every single stop"**.
  - Toggle **"Final Wake-Up Arrival Alarm"** + custom vibration waveforms.
- **Dual Switchable Anime Themes**:
  - **MyGO!!!!! Starry Rain** (`Tomori-navi` • Deep slate-blue & starry cyan with rain/star particles).
  - **Sakura Express Pastel** (`Hana-chan` • Warm pastel sakura pink & sky blue with falling sakura petals).
- **Local-First & Portable JSON Backups (`.my5top.json`)**:
  - Native Android Storage Access Framework (SAF) folder/file picker (`MainActivity.kt`) to save and restore `.my5top.json` backups directly to your **Google Drive** folder or local storage with zero cloud fees.
- **GitHub Releases APK Self-Updater**:
  - Checks GitHub Releases for newer `.apk` versions, streams the download with a progress bar, and launches the Android package installer (`OpenFilex`).
