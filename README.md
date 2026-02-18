# kawaii-pomodoro 🐱

A kawaii RPG-themed pomodoro timer for the terminal.

## Features
- RPG system: hearts, HP bar (stamina), XP/leveling
- Cat sprite that evolves as you level up (kitten → cat → cool → wizard → legendary)
- Time-of-day theming (morning/afternoon/evening/night)
- Weather display via wttr.in
- Spotify now playing (via `spotify_player`)
- macOS notifications on phase transitions
- Anti-flicker rendering via synchronized output (`\033[?2026h`)
- Fully standalone — no other tools required besides bash

## Requirements
- bash 4+
- macOS or Linux
- `curl` (for weather)
- `jq` (for Spotify, optional)
- `spotify_player` CLI (optional)
- iTerm2 or Alacritty recommended (for synchronized output support)

## Usage
```bash
bash pomodoro.sh
```

### Keys
| Key | Action |
|-----|--------|
| `p` | Pause / unpause |
| `s` | Skip current phase |
| `r` | Reset (hearts, phase, interval back to 25 min) |
| `>` or `.` | +1 min to work interval |
| `<` | -1 min to work interval |
| `q` | Quit |

## Pomodoro phases
- **Work** (25 min default) — HP drains, stay focused
- **Rest** (5 min) — HP recharges
- **Big break** (15 min) — triggered when all 3 hearts are lost

## Data
Persistent data stored in `~/.pomodoro/`:
- `data/xp.txt` — total XP
- `data/work_interval.txt` — current work interval in seconds
- `data/streak.txt` — daily streak
- `data/cycles_today.txt` — cycles completed today
- `state/` — current session state (phase, timer, hearts)
