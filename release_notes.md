# v1.0.5 — 1-Second Track Watch Burst, Headphone Silent Bypass, Background Guard & Startup Fix 🚆🎧🛡️

### ✨ What's New in v1.0.5

#### ⚡ 1-Second Track Watch Fast Polling Burst
- **11-Minute Precision Window**: Watched trains automatically switch to a lightweight **1-second single-station DepartureVision poll** starting at the **11-minute mark** before scheduled departure so you get your track number the instant it posts.
- **Smart 9-Minute Guardrail & Delay Exception**: Standard on-time trains automatically step back down once the track posts or at the **9-minute mark**; delayed or non-routine trains extend fast polling past 9 minutes with an 8-minute continuous burst cap and automatic HTTP 429/503 backoff.
- **Live Burst Indicators**: Displays a highlighted **`⚡ 1s Track Watch`** header pill and **`⚡ 1s Watch`** card badge whenever the 1-second track watcher is active.

#### 🎧 Headphone-Only Sound Bypass on Silent / Vibrate
- **Strict Headphone Routing**: When your phone is on **Vibrate**, **Silent**, or **Do Not Disturb**, commute alert chimes (track drops, stop countdowns, and arrival wake-up alarms) now play **strictly through connected wired, USB-C, or Bluetooth headphones**—never through phone speakers.
- **Instant Disconnect Safeguard**: Automatically ducks background media while chiming and immediately halts playback on headphone disconnect (`ACTION_AUDIO_BECOMING_NOISY`) to prevent speaker bleed.
- **Toggleable Control**: Enable or disable **Headphone sound on Silent/Vibrate** anytime from **Settings**, **Quick Commute Alert Settings**, or **Active Ride** notification controls.

#### 🛡️ Persistent Background Silent Guard (Survives Accidental Closing)
- **Accidental-Close Protection**: Once a ride or track watch is active, pressing Back silently moves the app to the background instead of closing, and a native Android Foreground Service keeps tracking even if the app is swiped away from Recents—continuing to deliver stop, arrival, and track notifications until your commute completes.
- **Seamless State Sync**: Any stops passed or tracks announced while running silently in the background automatically sync back into the app when reopened.
- **Battery-Safe Automatic Cutoffs**: Automatically shuts down **2 minutes** after reaching your destination stop, **20 minutes** past scheduled arrival ETA, after a **3-hour** hard ride cap (or **45-minute** / **15m-past-departure** track watch cap), plus a 1-tap **End Ride** / **Stop Watch** action button right on the persistent notification.

#### 🔧 Startup Reliability & Infinite-Loading Fix
- **Guaranteed Cold-Launch Completion**: Protected startup initialization with strict timeouts, `try/catch/finally` guarantees, and automatic recovery for corrupted local storage so the app can never get stuck on the loading spinner on launch.
- **Non-Blocking Background Sync & Platform Calls**: Deferred background guard sync and permission requests until after the home screen loads, added timeouts to every Android platform channel and HTTP stream call, and hardened native `MainActivity` / foreground service lifecycle handlers against startup errors.
