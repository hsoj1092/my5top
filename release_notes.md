# v1.0.3 — Randomized Japanese Streetscape Diorama, Compact Train Board & Persistent Active Ride Resume 🚆🗾

### ✨ What's New in v1.0.3

#### 🗾 Randomized Japanese Streetscape & Trip-Synced Mountain
- **Trip-Progress Horizon Mountain**: The snow-capped mountain in the background now moves smoothly across the sky in sync with your overall trip progress (`0%` → `100%`), exiting off the horizon as you approach your destination.
- **New Japanese Streetscape Landmarks & Shops**: Alongside the classic **Red Torii Arches**, rides now pass **Lawson**, **7-Eleven**, a cozy **Ramen Shop** (with swaying red lanterns and split noren curtains), **Traditional Wooden Machiya Houses**, **Modern 2-Story Japanese Homes**, **Narrow Multi-Story Town Buildings**, and **Tea-House Pavilions with Street Vending Machines**.
- **Unique Every Check-In**: Boarding a train selects one of **5 curated streetscape variations** combined with seeded per-slot randomization so every commute feels fresh.

#### 📋 Compact Upcoming Board & Standout "Just Departed" Section
- **Streamlined Upcoming List + Load More**: Shows the next **3** upcoming trains based on the current time with a **Load More Trains** button to expand additional departures (`+4` at a time) and a **Show Fewer Trains** toggle to collapse back down.
- **Highlighted "Just Departed" Wrapper**: En-route departed trains now sit inside an accent-tinted card wrapper with a larger header and `EN ROUTE` pill badge so they stand out clearly from upcoming departures.
- **Train Tile Layout & Overflow Fixes**: Fixed horizontal text overflow on train cards and section headers when long live statuses (such as `En Route → Newark Penn`) or scaled system font sizes are displayed.

#### 🔄 Automatic Active Ride Resume & 20-Minute Staleness Cutoff
- **Seamless App Reopen**: Closing and reopening the app while tracking a train now brings you straight back to the live tracked train screen, preserving your stop progress, alert history, and streetscape variation.
- **Smart 20-Minute Arrival Cutoff**: If the app is reopened **20 minutes or more** after the tracked train's arrival time, the completed trip is automatically archived to your ride log and the app opens directly to the main train departure board.
