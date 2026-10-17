# Iron Horizon

A 3D arcade coastal-defense shooter built in **Godot 4.7** (`gl_compatibility` / WebGL 2.0 renderer). You hold a gun emplacement on a hilltop overlooking a beach and fight off waves of landing craft, armor, helicopters and jets. Everything (models, terrain, sound) is generated procedurally in code, so the project has no external asset dependencies.

**Play it in your browser:** https://marse337.github.io/iron-horizon/

## Controls

| Input | Action |
| :--- | :--- |
| **Mouse / Touch Drag / WASD** | Rotate the turret 360° and pitch -40° to +72° |
| **Left Mouse Button / Enter (Hold)** | Fire active primary weapon |
| **Space / Q / Scroll / 1, 2** | Switch between Dual 30mm Autocannon and the 105mm (or 155mm) cannon |
| **Right Mouse Button / M / E** | Fire guided SAM (locks onto aircraft in the reticle) |
| **F** | Launch parachute illumination flare (dusk & night waves) |
| **3** | 9mm backup sidearm (auto-equips when primary ammo runs out) |
| **Esc / P** | Pause and adjust mouse sensitivity |

## How It Plays

- **Waves from one direction at a time.** Each wave has a fixed roster and a single approach heading, starting straight in from the sea. New enemy types unlock one per wave: infantry → APCs → helicopters → tanks → paratrooper transports → jets. Enemy health rises 12% per wave.
- **Amphibious landings.** Troops and tanks arrive in landing craft. Each boat beaches, drops its bow ramp onto the sand, and unloads one soldier at a time. Nothing aboard can shoot until the ramp is down.
- **Weapon matchups.**
  - **30mm autocannon** shreds infantry, paratroopers, helicopters and incoming rockets, but ricochets off tanks and APCs.
  - **105mm cannon** kills armor with splash damage, but can't pierce a landing craft's hull.
  - **155mm Coastal Gun** (shop upgrade) replaces the 105mm and can sink landing craft, taking everyone aboard down with them.
  - **Homing SAMs** lock onto aircraft.
- **Supply drops.** Friendly cargo planes drop parachute crates. Shoot a crate before it lands to claim ammo and repairs, or CIWS Overdrive from golden crates.
- **Between-wave shop.** Spend score on repairs, ammo, fire-rate and reload upgrades, and the Coastal Gun.
- **Time-of-day cycle.** Dawn → noon → dusk → night, with a searchlight and flares for the dark waves.

## Running Locally

Open the folder in Godot 4.7 and press **F5**, or:

```powershell
& "C:\Users\nivek\Documents\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64.exe" --path "c:\Users\nivek\Documents\Godot\BeachHead"
```

## Web Deployment

Every push to `main` runs [`.github/workflows/deploy-web.yml`](.github/workflows/deploy-web.yml). It downloads the official Godot 4.7 Linux editor and export templates, exports the single-threaded **Web** preset (no `SharedArrayBuffer` / cross-origin isolation headers needed, which GitHub Pages can't send), and publishes the result to GitHub Pages. You can also start a deploy by hand from the repo's **Actions** tab ("Run workflow").
