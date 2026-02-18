#!/usr/bin/env bash
# pomodoro.sh — standalone RPG pomodoro timer
# keys: p=pause  s=skip  r=reset  >/<= interval  q=quit

# --- Storage ---
DATA_DIR="$HOME/.pomodoro/data"
STATE_DIR="$HOME/.pomodoro/state"
mkdir -p "$DATA_DIR" "$STATE_DIR"

# persistent
XP_FILE="$DATA_DIR/xp.txt"
GOAL_FILE="$DATA_DIR/daily_goal.txt"
CYCLES_FILE="$DATA_DIR/cycles_today.txt"   # "YYYY-MM-DD COUNT"
STREAK_FILE="$DATA_DIR/streak.txt"         # "YYYY-MM-DD COUNT"
WORK_INT_FILE="$DATA_DIR/work_interval.txt"

# session state
PHASE_FILE="$STATE_DIR/phase.txt"
CYCLE_START_FILE="$STATE_DIR/cycle_start.txt"
HEARTS_FILE="$STATE_DIR/hearts.txt"
PAUSED_FILE="$STATE_DIR/paused.txt"

# init defaults
[[ ! -f "$XP_FILE"       ]] && echo "0"    > "$XP_FILE"
[[ ! -f "$GOAL_FILE"     ]] && echo "8"    > "$GOAL_FILE"
[[ ! -f "$WORK_INT_FILE" ]] && echo "1500" > "$WORK_INT_FILE"

now_ts=$(date +%s)
[[ ! -f "$PHASE_FILE"       ]] && echo "work"     > "$PHASE_FILE"
[[ ! -f "$CYCLE_START_FILE" ]] && echo "$now_ts"  > "$CYCLE_START_FILE"
[[ ! -f "$HEARTS_FILE"      ]] && echo "3"        > "$HEARTS_FILE"

REST_INTERVAL=300
BIG_BREAK_INTERVAL=900
XP_PER_CYCLE=25

# --- Colors ---
RESET='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'
STM_HIGH='\033[38;5;82m'
STM_MID='\033[38;5;220m'
STM_LOW='\033[38;5;196m'
STM_REST='\033[38;5;123m'
BIG_BREAK_COLOR='\033[38;5;213m'
HEART_FULL='\033[38;5;196m'
HEART_EMPTY='\033[38;5;240m'
PINK='\033[38;5;218m'
LAVENDER='\033[38;5;183m'
GOLD='\033[38;5;220m'

hour=$(date +%H)
if   [[ $hour -ge 6  && $hour -lt 12 ]]; then
  CAT_COLOR='\033[38;5;222m'; SKY='\033[38;5;214m'; THEME="morning"
elif [[ $hour -ge 12 && $hour -lt 18 ]]; then
  CAT_COLOR='\033[38;5;255m'; SKY='\033[38;5;153m'; THEME="afternoon"
elif [[ $hour -ge 18 && $hour -lt 22 ]]; then
  CAT_COLOR='\033[38;5;183m'; SKY='\033[38;5;141m'; THEME="evening"
else
  CAT_COLOR='\033[38;5;153m'; SKY='\033[38;5;67m';  THEME="night"
fi
MANA_COLOR='\033[38;5;105m'

# --- XP / Level ---
get_xp()      { cat "$XP_FILE" 2>/dev/null || echo 0; }
add_xp()      { echo $(( $(get_xp) + $1 )) > "$XP_FILE"; }
xp_to_level() { echo $(( $1 / 150 + 1 )); }
xp_in_level() { echo $(( $1 % 150 )); }

# --- Streak ---
get_streak() {
  [[ ! -f "$STREAK_FILE" ]] && echo 0 && return
  local stored=$(cat "$STREAK_FILE")
  local sdate="${stored%% *}"; local scount="${stored##* }"
  local today=$(date +%Y-%m-%d)
  local yesterday=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d yesterday +%Y-%m-%d 2>/dev/null)
  [[ "$sdate" == "$today" || "$sdate" == "$yesterday" ]] && echo "$scount" || echo 0
}
update_streak() {
  local today=$(date +%Y-%m-%d)
  local yesterday=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d yesterday +%Y-%m-%d 2>/dev/null)
  local count=1
  if [[ -f "$STREAK_FILE" ]]; then
    local stored=$(cat "$STREAK_FILE")
    local sdate="${stored%% *}"; local scount="${stored##* }"
    [[ "$sdate" == "$today"     ]] && return
    [[ "$sdate" == "$yesterday" ]] && count=$(( scount + 1 ))
  fi
  echo "$today $count" > "$STREAK_FILE"
}

# --- Daily cycles ---
get_cycles_today() {
  [[ ! -f "$CYCLES_FILE" ]] && echo 0 && return
  local stored=$(cat "$CYCLES_FILE")
  local sdate="${stored%% *}"; local scount="${stored##* }"
  [[ "$sdate" == "$(date +%Y-%m-%d)" ]] && echo "$scount" || echo 0
}
increment_cycles() {
  echo "$(date +%Y-%m-%d) $(( $(get_cycles_today) + 1 ))" > "$CYCLES_FILE"
}

# --- macOS notification ---
notify() { osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null; }

# --- Weather (cached 10 min) ---
WEATHER_CACHE="/tmp/pomodoro_weather.txt"
WEATHER_TS="/tmp/pomodoro_weather_ts.txt"
get_weather() {
  local now=$(date +%s) age=9999
  [[ -f "$WEATHER_TS" ]] && age=$(( now - $(cat "$WEATHER_TS") ))
  if [[ $age -ge 600 ]]; then
    local raw; raw=$(curl -s --max-time 4 "wttr.in/?format=%c+%t&u" 2>/dev/null | tr -d '\r\n')
    if [[ -n "$raw" && "$raw" != *"<html"* && ${#raw} -lt 80 ]]; then
      echo "$raw" > "$WEATHER_CACHE"
    else
      echo "" > "$WEATHER_CACHE"
    fi
    echo "$now" > "$WEATHER_TS"
  fi
  cat "$WEATHER_CACHE" 2>/dev/null
}

# --- Spotify (cached 15s) ---
SPOTIFY_CACHE="/tmp/pomodoro_spotify.txt"
SPOTIFY_TS="/tmp/pomodoro_spotify_ts.txt"
get_spotify() {
  local now=$(date +%s) age=9999
  [[ -f "$SPOTIFY_TS" ]] && age=$(( now - $(cat "$SPOTIFY_TS") ))
  if [[ $age -ge 15 ]] && command -v spotify_player &>/dev/null; then
    local json; json=$(spotify_player get key playback 2>/dev/null)
    if [[ -n "$json" ]]; then
      local track artist playing
      track=$(echo "$json"   | jq -r '.item.name // ""'            2>/dev/null)
      artist=$(echo "$json"  | jq -r '.item.artists[0].name // ""' 2>/dev/null)
      playing=$(echo "$json" | jq -r '.is_playing'                 2>/dev/null)
      if [[ -n "$track" ]]; then
        [[ "$playing" == "true" ]] \
          && echo "♪ $track — $artist" > "$SPOTIFY_CACHE" \
          || echo "⏸ $track — $artist" > "$SPOTIFY_CACHE"
      else
        echo "" > "$SPOTIFY_CACHE"
      fi
    else
      echo "" > "$SPOTIFY_CACHE"
    fi
    echo "$now" > "$SPOTIFY_TS"
  fi
  cat "$SPOTIFY_CACHE" 2>/dev/null
}

# --- ASCII scene ---
get_scene() {
  local w="$1" rain=false
  [[ "$w" == *"🌨"* || "$w" == *"🌧"* || "$w" == *"🌦"* || "$w" == *"⛈"* ]] && rain=true
  case $THEME in
    morning)
      $rain && { echo "  ′  ′  ′  ′  ′  ′  "; echo "  ′  ′  ′  ′  ′  ′  "; return; }
      echo "  · · · ☀ · · · · ·  "; echo "  ~ ~~~ ~ ~~~  ~~~~  " ;;
    afternoon)
      $rain && { echo "  ′  ′  ′  ′  ′  ′  "; echo "  ′  ′  ′  ′  ′  ′  "; return; }
      echo "  ~~~☁~~  · · ~~~☁~  "; echo "  ⛅ · · · · · · · ·  " ;;
    evening)
      echo "  · ✦ · 🌆 · · ✦ · ·  "; echo "  ~~~~ ~  ~~~~~~~ ~~  " ;;
    night)
      echo "  ★ · ✦ · · ★ · ✦ ·  "; echo "  · ✦ · 🌙 · · ★ · ✦  " ;;
  esac
}

# --- Cat sprite ---
cat_sprite() {
  local state=$1 frame=$2 level=$3
  local tier
  if   [[ $level -ge 15 ]]; then tier="legendary"
  elif [[ $level -ge 10 ]]; then tier="wizard"
  elif [[ $level -ge 6  ]]; then tier="cool"
  elif [[ $level -ge 3  ]]; then tier="cat"
  else                            tier="kitten"
  fi

  case $state in
    paused)
      case $(( frame % 2 )) in
        0) echo " /\\_/\\  "; echo " ( -.- ) "; echo "  zz~~  " ;;
        1) echo " /\\_/\\  "; echo "(~-.-~) "; echo "   Zz~  " ;;
      esac; return ;;
    rest)
      case $(( frame % 4 )) in
        0) echo " /\\_/\\  "; echo " ( ˘ω˘ ) "; echo "   z z  " ;;
        1) echo " /\\_/\\  "; echo " ( ˘ω˘ ) "; echo "  z Z   " ;;
        2) echo " /\\_/\\  "; echo " ( -_- ) "; echo "  z Z z " ;;
        3) echo " /\\_/\\  "; echo " ( ˘ω˘ ) "; echo "   Z Z  " ;;
      esac; return ;;
    bigbreak)
      case $(( frame % 3 )) in
        0) echo " /\\_/\\  "; echo " ( x_x ) "; echo "  !! !!  " ;;
        1) echo " /\\_/\\  "; echo " ( X_X ) "; echo " !!! !!  " ;;
        2) echo " /\\_/\\  "; echo " ( x_x ) "; echo "  !! !!! " ;;
      esac; return ;;
  esac

  case $tier in
    kitten)
      case $state in
        work_high) case $(( frame%4 )) in
          0) echo "♪ /\\_/\\ ♪"; echo " (^>ω<^) "; echo "  \\  /  " ;;
          1) echo "♫ /\\_/\\ ♫"; echo " (^>ω<^) "; echo "  /  \\  " ;;
          2) echo "♪ /\\_/\\ ♪"; echo " (^>ω<^) "; echo " \\  /   " ;;
          3) echo "♫ /\\_/\\ ♫"; echo " (^>ω<^) "; echo " /  \\   " ;; esac ;;
        work_mid) case $(( frame%2 )) in
          0) echo "  /\\_/\\  "; echo " ( •ω• ) "; echo "   \\  / " ;;
          1) echo "  /\\_/\\  "; echo " ( •ω• ) "; echo "   /  \\ " ;; esac ;;
        work_low) case $(( frame%2 )) in
          0) echo "  /\\_/\\  "; echo " ( ;ω; ) "; echo "  >(  )< " ;;
          1) echo "  /\\_/\\  "; echo " (;ω;  ) "; echo " >(  )<  " ;; esac ;;
      esac ;;
    cat)
      case $state in
        work_high) case $(( frame%4 )) in
          0) echo "  /\\_/\\  "; echo " ( ^ω^  )"; echo "  \\  /  " ;;
          1) echo "  /\\_/\\  "; echo " (  ^ω^ )"; echo "  /  \\  " ;;
          2) echo "  /\\_/\\  "; echo " ( ^ω^  )"; echo " \\  /   " ;;
          3) echo "  /\\_/\\  "; echo " (  ^ω^ )"; echo " /  \\   " ;; esac ;;
        work_mid) case $(( frame%2 )) in
          0) echo "  /\\_/\\  "; echo " ( •ω•  )"; echo "   \\  / " ;;
          1) echo "  /\\_/\\  "; echo " (  •ω• )"; echo "   /  \\ " ;; esac ;;
        work_low) case $(( frame%2 )) in
          0) echo "  /\\_/\\  "; echo " (  ;ω;  )"; echo "  >(  )< " ;;
          1) echo "  /\\_/\\  "; echo " (  ;ω;  )"; echo " >(  )<  " ;; esac ;;
      esac ;;
    cool)
      case $state in
        work_high) case $(( frame%2 )) in
          0) echo "  /\\_/\\  "; echo " ( ◕ω◕ )★"; echo " ♪\\  /♪ " ;;
          1) echo " ★/\\_/\\  "; echo " ( ◕ω◕ ) "; echo " ♫/  \\♫ " ;; esac ;;
        work_mid)  echo "  /\\_/\\  "; echo " ( ◕ω◕ )  "; echo " ♪\\  /  " ;;
        work_low)  echo "  /\\_/\\  "; echo " (  ;ω;  )"; echo "  > !! < " ;;
      esac ;;
    wizard)
      case $state in
        work_high) case $(( frame%2 )) in
          0) echo " /\\_/\\ ✦ "; echo " (  ✧ω✧ ) "; echo "  ✦\\  /✦ " ;;
          1) echo " ✦ /\\_/\\  "; echo " (  ✧ω✧ ) "; echo "  ✦/  \\✦ " ;; esac ;;
        work_mid)  echo "  /\\_/\\   "; echo " ( ✧ω✧  ) "; echo "  ✦\\  /✦ " ;;
        work_low)  echo "  /\\_/\\   "; echo " (  ;ω;  )"; echo "  > !! <  " ;;
      esac ;;
    legendary)
      case $state in
        work_high) case $(( frame%2 )) in
          0) echo "✨/\\_/\\✨ "; echo " (  ◉ω◉  )"; echo " ⚡\\  /⚡ " ;;
          1) echo "✨/\\_/\\✨ "; echo " (  ◉ω◉  )"; echo " ⚡/  \\⚡ " ;; esac ;;
        work_mid)  echo "  /\\_/\\   "; echo " (  ◉ω◉  )"; echo "  ⚡\\  /⚡ " ;;
        work_low)  echo "  /\\_/\\   "; echo " (  ;ω;  )"; echo "  > !! <  " ;;
      esac ;;
  esac
}

# --- Layout helpers ---
bar() {
  local filled=$1 total=$2 color=$3
  local width=$(( COLS * 75 / 100 )); [[ $width -lt 4 ]] && width=4
  local f=$(( filled * width / total )); [[ $f -gt $width ]] && f=$width
  local b=""
  for ((i=0; i<f; i++));       do b+="█"; done
  for ((i=0; i<width-f; i++)); do b+="░"; done
  printf "${color}%s${RESET}" "$b"
}
center() {
  local visible; visible=$(printf '%b' "$1" | sed 's/\x1b\[[0-9;]*m//g')
  local pad=$(( (COLS - ${#visible}) / 2 )); [[ $pad -lt 0 ]] && pad=0
  printf "%${pad}s"; printf '%b' "$1"; printf '\033[K'
}
trunc() { local s="$1" m=$2; [[ ${#s} -gt $m ]] && echo "${s:0:$((m-1))}…" || echo "$s"; }

# --- Line cache: only redraw lines that changed ---
declare -A _LC   # line cache
_row=0
_prev_rows=0

begin_frame() { _row=0; }

draw_line() {
  local raw="$1"
  if [[ "${_LC[$_row]:-__unset__}" != "$raw" ]]; then
    tput cup $_row 0
    printf '\033[2K'
    center "$raw"
    _LC[$_row]="$raw"
  fi
  (( _row++ ))
}

blank_line() { draw_line ""; }

end_frame() {
  # clear leftover lines from a taller previous frame
  while [[ $_row -lt $_prev_rows ]]; do
    tput cup $_row 0; printf '\033[2K'; _LC[$_row]=""
    (( _row++ ))
  done
  _prev_rows=$(( _row ))
}

println() { draw_line "$1"; }
blankln() { blank_line; }

# --- Init terminal ---
tput civis; printf '\033[?7l'
trap 'tput cnorm; printf "\033[?7h"; tput rmcup; echo' EXIT
tput smcup; clear

frame=0; last_phase=""; last_level=0

while true; do
  now_ts=$(date +%s)
  ROWS=$(tput lines); COLS=$(tput cols)

  phase=$(cat "$PHASE_FILE"       2>/dev/null || echo "work")
  hearts=$(cat "$HEARTS_FILE"     2>/dev/null || echo 3)
  cycle_start=$(cat "$CYCLE_START_FILE" 2>/dev/null || echo "$now_ts")
  WORK_INTERVAL=$(cat "$WORK_INT_FILE"  2>/dev/null || echo 1500)

  printf '\033[?2026h'   # begin synchronized update
  begin_frame

  is_paused=false
  if [[ -f "$PAUSED_FILE" ]]; then
    is_paused=true
    time_in_cycle=$(( $(cat "$PAUSED_FILE") - cycle_start ))
  else
    time_in_cycle=$(( now_ts - cycle_start ))
  fi

  # phase transitions
  if [[ "$phase" == "work" && $time_in_cycle -ge $WORK_INTERVAL ]]; then
    hearts=$(( hearts - 1 )); [[ $hearts -lt 0 ]] && hearts=0
    echo "$hearts" > "$HEARTS_FILE"
    if [[ $hearts -le 0 ]]; then echo "bigbreak" > "$PHASE_FILE"; phase="bigbreak"
    else                         echo "rest"     > "$PHASE_FILE"; phase="rest"; fi
    echo "$now_ts" > "$CYCLE_START_FILE"; cycle_start=$now_ts; time_in_cycle=0
  fi
  if [[ "$phase" == "rest" && $time_in_cycle -ge $REST_INTERVAL ]]; then
    echo "work" > "$PHASE_FILE"; echo "$now_ts" > "$CYCLE_START_FILE"
    phase="work"; cycle_start=$now_ts; time_in_cycle=0
  fi
  if [[ "$phase" == "bigbreak" && $time_in_cycle -ge $BIG_BREAK_INTERVAL ]]; then
    echo "3" > "$HEARTS_FILE"; echo "work" > "$PHASE_FILE"
    echo "$now_ts" > "$CYCLE_START_FILE"
    hearts=3; phase="work"; cycle_start=$now_ts; time_in_cycle=0
  fi

  # phase change events
  if [[ -n "$last_phase" && "$phase" != "$last_phase" ]]; then
    if [[ "$last_phase" == "work" ]]; then
      add_xp $XP_PER_CYCLE; increment_cycles; update_streak
      [[ "$phase" == "rest"     ]] && notify "Break time! ☕" "Great work! 5 min rest."
      [[ "$phase" == "bigbreak" ]] && notify "Big break! 💀" "All hearts lost — rest up."
    elif [[ "$last_phase" == "rest"     ]]; then notify "Back to work! ⚡" "Rest over — let's go!"
    elif [[ "$last_phase" == "bigbreak" ]]; then notify "Fully restored! ✨" "Hearts back — let's go!"
    fi
  fi
  last_phase="$phase"

  # level up event
  xp=$(get_xp); level=$(xp_to_level $xp); xp_now=$(xp_in_level $xp)
  if [[ $last_level -gt 0 && $level -gt $last_level ]]; then
    notify "Level up! 🎉" "You are now level $level!"
  fi
  last_level=$level

  # compute HP
  if [[ "$phase" == "work" ]]; then
    secs_left=$(( WORK_INTERVAL - time_in_cycle )); [[ $secs_left -lt 0 ]] && secs_left=0
    pct=$(( (secs_left * 100) / WORK_INTERVAL ))
    timer="$(printf "%d:%02d" $(( secs_left/60 )) $(( secs_left%60 )))"
    if   [[ $pct -le 20 ]]; then hc="$STM_LOW";  cat_state="work_low";  label="running low..."
    elif [[ $pct -le 50 ]]; then hc="$STM_MID";  cat_state="work_mid";  label="keep going"
    else                         hc="$STM_HIGH"; cat_state="work_high"; label="focused!"
    fi
    hp_filled=$pct; hp_total=100; phase_label="WORK  $timer"

  elif [[ "$phase" == "rest" ]]; then
    secs_left=$(( REST_INTERVAL - time_in_cycle )); [[ $secs_left -lt 0 ]] && secs_left=0
    timer="$(printf "%d:%02d" $(( secs_left/60 )) $(( secs_left%60 )))"
    hp_filled=$time_in_cycle; hp_total=$REST_INTERVAL
    hc="$STM_REST"; cat_state="rest"; phase_label="REST  $timer"
    label="recharging..."; [[ $secs_left -le 30 ]] && label="almost ready!"

  else
    secs_left=$(( BIG_BREAK_INTERVAL - time_in_cycle )); [[ $secs_left -lt 0 ]] && secs_left=0
    timer="$(printf "%d:%02d" $(( secs_left/60 )) $(( secs_left%60 )))"
    hp_filled=$time_in_cycle; hp_total=$BIG_BREAK_INTERVAL
    hc="$BIG_BREAK_COLOR"; cat_state="bigbreak"; phase_label="BIG BREAK  $timer"; label="go rest up!"
  fi

  $is_paused && cat_state="paused"

  # gather data
  heart_str=""
  for ((i=0; i<3; i++)); do
    [[ $i -lt $hearts ]] && heart_str+="${HEART_FULL}♥ ${RESET}" \
                         || heart_str+="${HEART_EMPTY}♡ ${RESET}"
  done
  (( now_ts % 2 == 0 )) && ! $is_paused && frame=$(( frame + 1 ))
  mapfile -t cat_lines < <(cat_sprite "$cat_state" "$frame" "$level")

  weather=$(get_weather)
  spotify=$(get_spotify)
  current_time=$(date +"%b %d  %H:%M")
  cycles_today=$(get_cycles_today)
  daily_goal=$(cat "$GOAL_FILE" 2>/dev/null || echo 8)
  streak=$(get_streak)
  mapfile -t scene < <(get_scene "$weather")
  work_min=$(( WORK_INTERVAL / 60 ))

  # --- vertical centering ---
  content_rows=18
  [[ -n "$streak" && $streak -gt 0 ]] && (( content_rows++ ))
  [[ "$phase" == "bigbreak" ]]        && (( content_rows += 3 ))
  [[ -n "$weather" ]]                 && (( content_rows++ ))
  [[ -n "$spotify" ]]                 && (( content_rows += 2 ))
  top_pad=$(( (ROWS - 1 - content_rows) / 2 ))
  [[ $top_pad -lt 0 ]] && top_pad=0
  for ((i=0; i<top_pad; i++)); do blankln; done

  # --- DRAW ---
  println "${DIM}${scene[0]}${RESET}"
  println "${DIM}${scene[1]}${RESET}"
  blankln

  if [[ -n "$weather" ]]; then
    println "${PINK}${weather}${RESET}  ${DIM}${SKY}${current_time}${RESET}"
  else
    println "${DIM}${SKY}${current_time}${RESET}"
  fi
  blankln

  println "${CAT_COLOR}${cat_lines[0]}${RESET}"
  println "${CAT_COLOR}${cat_lines[1]}${RESET}"
  println "${CAT_COLOR}${cat_lines[2]}${RESET}"
  blankln

  println "${GOLD}Lv.${level}${RESET}  ${DIM}${xp_now}/150 xp${RESET}"
  [[ $streak -gt 0 ]] && println "${PINK}🔥 ${streak} day streak${RESET}"
  blankln

  println "$heart_str"
  blankln

  if $is_paused; then println "${BOLD}${DIM}⏸  PAUSED${RESET}"
  else                 println "${BOLD}${hc}${phase_label}${RESET}"; fi
  println "$(bar $hp_filled $hp_total "$hc")"
  println "${DIM}${label}${RESET}"

  if [[ "$phase" == "bigbreak" ]]; then
    blankln
    println "${BIG_BREAK_COLOR}all hearts lost — time for a real break${RESET}"
    println "${DIM}step away · stretch · get some water${RESET}"
  fi
  blankln

  println "${DIM}today  ${cycles_today}/${daily_goal}${RESET}"

  if [[ -n "$spotify" ]]; then
    blankln
    println "${DIM}${PINK}$(trunc "$spotify" $(( COLS - 4 )))${RESET}"
  fi

  end_frame

  tput cup $(( ROWS - 1 )) 0; printf '\033[2K'
  center "${DIM}[p]pause [s]skip [r]reset [>/<]1m [q]quit${RESET}"
  printf '\033[?2026l'   # end synchronized update — flush atomically

  read -t 0.1 -n 1 -s key 2>/dev/null
  case "$key" in
    p|P)
      if [[ -f "$PAUSED_FILE" ]]; then
        dur=$(( $(date +%s) - $(cat "$PAUSED_FILE") ))
        echo $(( cycle_start + dur )) > "$CYCLE_START_FILE"
        rm -f "$PAUSED_FILE"
      else
        echo "$now_ts" > "$PAUSED_FILE"
      fi ;;
    s|S)
      rm -f "$PAUSED_FILE"
      if [[ "$phase" == "work" ]]; then
        if [[ $hearts -le 1 ]]; then
          echo "bigbreak" > "$PHASE_FILE"; echo "0" > "$HEARTS_FILE"
        else
          echo "rest" > "$PHASE_FILE"
        fi
      else
        echo "work" > "$PHASE_FILE"
      fi
      echo "$now_ts" > "$CYCLE_START_FILE" ;;
    r|R)
      rm -f "$PAUSED_FILE"
      echo "$now_ts" > "$CYCLE_START_FILE"
      echo "work" > "$PHASE_FILE"
      echo "3"    > "$HEARTS_FILE"
      echo "1500" > "$WORK_INT_FILE" ;;
    '>'|'.')
      ni=$(( WORK_INTERVAL + 60 )); [[ $ni -gt 7200 ]] && ni=7200
      echo "$ni" > "$WORK_INT_FILE" ;;
    '<')
      ni=$(( WORK_INTERVAL - 60 )); [[ $ni -lt 60 ]] && ni=60
      echo "$ni" > "$WORK_INT_FILE"
      if [[ "$phase" == "work" && $time_in_cycle -ge $(( ni - 10 )) ]]; then
        echo $(( now_ts - ni + 10 )) > "$CYCLE_START_FILE"
      fi ;;
    q|Q) exit 0 ;;
  esac
done
