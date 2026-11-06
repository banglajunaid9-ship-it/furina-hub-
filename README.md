# Furina Hub

Script hub for **Forsaken** on Roblox. Works on PC and phone executors.

## Load (always the newest version)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/banglajunaid9-ship-it/furina-hub-/main/FurinaHub.lua"))()
```

Paste that one line into your executor. Because it downloads the script from
this repo every time, you always get the latest version. GitHub can take up to
about 5 minutes to serve a new push.

## Controls

| | PC | Phone |
|---|---|---|
| Open / close menu | RightControl | Tap the floating **F** button |
| Toggle auto farm | F6 | Tap the floating **⚡** button (green = on) |
| Panic unload | End | Misc tab, then Unload Hub |

The floating buttons can be dragged anywhere.

## Features

- **Auto Farm.** Plays whichever role you get.
  - Survivor: runs to the best generator, solves all 4 puzzle types, and flees the killer.
  - Killer: chases with prediction and attacks, and can optionally use its other abilities.
- **Safe Mode** (on by default):
  - no teleports
  - human-paced timing
  - real interaction ranges
  - sprints like a player
  - anti-AFK
- **Auto Save.** Every setting saves itself and comes back next time.
- **Stats.** Money earned, money per hour, rounds, puzzles solved and hits landed.
- **Server tools.**
  - FPS Boost, which helps a lot on phones
  - auto-rejoin on disconnect
  - server hop to the emptiest or a random server
- **ESP.** Killers, survivors, generators and items.
- **Visuals.** Fullbright and no fog.

## Phone executors

Furina Hub checks which functions your executor has and falls back to plain Roblox
APIs when one is missing (`getconnections`, `fireproximityprompt`, `mouse1click`,
`gethui`). If auto-save does nothing, your executor has no file functions.
