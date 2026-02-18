# kawaii-pomodoro 🐱

A kawaii RPG-themed pomodoro timer for the terminal.

```
♪ /\_/\ ♪
 (^>ω<^)
   \  /

  ♥ ♥ ♥

  WORK  24:12
  ████████████░░░░
   focused!
```

## Features
- RPG system: hearts, HP bar (stamina), XP/leveling
- Cat sprite that evolves as you level up (kitten → cat → cool → wizard → legendary)
- Time-of-day theming (morning / afternoon / evening / night)
- Weather display via wttr.in — no setup needed
- Spotify now playing — optional, requires extra setup (see below)
- macOS notifications on phase transitions — macOS only, silently skipped on Linux
- Anti-flicker rendering via synchronized output
- Vertically centered, scales to terminal size

---

## Quick install
```bash
curl -o pomodoro.sh https://raw.githubusercontent.com/DDuongNguyen/kawaii-pomodoro/main/pomodoro.sh
chmod +x pomodoro.sh
bash pomodoro.sh
```

That's it — no config needed. Weather loads automatically, Spotify shows up only if you've set it up.

---

## Requirements

| Tool | Required | Notes |
|------|----------|-------|
| `bash` 4+ | yes | pre-installed on macOS/Linux |
| `tput` | yes | pre-installed (part of ncurses) |
| `curl` | yes | pre-installed on most systems |
| `jq` | only for Spotify | `brew install jq` / `apt install jq` |
| `spotify_player` | only for Spotify | see setup below |
| `osascript` | no | macOS only — used for notifications, silently skipped otherwise |

---

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

---

## Pomodoro phases
- **Work** (25 min default) — HP bar drains, stay focused
- **Rest** (5 min) — HP bar recharges
- **Big break** (15 min) — triggered when all 3 hearts are lost, step away from the screen

---

## Spotify setup (optional)

The timer shows your current Spotify track if `spotify_player` is installed and authenticated.

### 1. Install dependencies
```bash
# macOS
brew install jq spotify_player

# Linux (jq)
sudo apt install jq   # or your distro's package manager
# then install spotify_player via cargo:
cargo install spotify_player
```

### 2. Create a Spotify app
1. Go to [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard)
2. Click **Create app**
3. Fill in any name and description
4. Under **Redirect URIs**, add: `http://127.0.0.1:8989/login`
5. Save, then copy your **Client ID**

### 3. Configure spotify_player
```bash
mkdir -p ~/.config/spotify-player
```

Create `~/.config/spotify-player/app.toml`:
```toml
[app_config]
client_id = "your_client_id_here"
```

### 4. Authenticate
```bash
spotify_player
```
A browser window will open asking you to log in to Spotify and grant access.
Once complete, the token is saved locally — you won't need to do this again.

> **Note:** Spotify Premium is required for playback control. Free accounts will still show the now-playing display.

---

## Data
All data is stored in `~/.pomodoro/` — nothing is sent anywhere.

```
~/.pomodoro/
  data/
    xp.txt              — total XP earned
    work_interval.txt   — work interval in seconds (default 1500 = 25 min)
    streak.txt          — daily streak
    cycles_today.txt    — cycles completed today
    daily_goal.txt      — daily cycle goal (default 8)
  state/
    phase.txt           — current phase (work / rest / bigbreak)
    cycle_start.txt     — unix timestamp of current phase start
    hearts.txt          — remaining hearts (0–3)
    paused.txt          — exists only when paused, stores pause timestamp
```
