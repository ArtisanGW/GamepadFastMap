#!/usr/bin/env bash
# In-game test: closing the world map with the cursor on a quest pin, again and
# again, at different moments. The crash this checks: SetPreferredGamepadInteractTarget()
# blocked ("Interface action failed") when the map closed on a hovered pin.
# Needs WoW running with a debug build of GamepadFastMap (Debug.lua and
# DebugPinClose.lua installed), out of combat, with quests on the map; don't
# touch the mouse or keys until the game's reload box opens.
#
# It presses L5 (Keypad 5, DevBindOnce running /gpfm debug pins: its COMMAND
# must be that), then for each round: opens the map (M),
# finds the magenta square the game puts on a quest pin (a screenshot), and
# moves the mouse onto that pin and closes the map (M):
#   same     the move and the close in one go (the same frame or the next)
#   wait     a short wait first (ROUND_WAITS, in turn)
#   leave    onto the pin and off it again, then the close
# After ROUNDS closes the game shows its reload box; after your Reload, the
# results are read from GamepadFastMapDB.debugPinClose.
#
#   tests/ingame_pin_close.sh
# Exit codes: 0 passed, 1 failed, 2 the game isn't running, 3 the test didn't
# start in the game (no square on the map), 5 no reload in time.
set -u
SCRIPT_FOLDER="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../devAddons/game_window.sh
. "$SCRIPT_FOLDER/../../devAddons/game_window.sh"

ROUNDS=30                         # DebugPinClose.lua's ROUNDS
ROUND_WAITS=(0.02 0.05 0.1 0.3)   # seconds on the pin before the close, "wait" rounds
MAP_KEY="m"                       # the game's default for the world map
RELOAD_WAIT=120
SAVED_VARIABLES="/var/mnt/data/Jeux - Installations/World of Warcraft/_forever_/WTF/Account/129527646#1/SavedVariables/GamepadFastMap.lua"
SCREENSHOT_FILE="$(mktemp --suffix=.png)"
trap 'rm -f "$SCREENSHOT_FILE"' EXIT

window="$(find_game_window)"
if [ -z "$window" ]; then echo "World of Warcraft isn't running." >&2; exit 2; fi
focus_game_with_kwin
xdotool windowactivate --sync "$window" 2>/dev/null
sleep 0.3

# Prints "x y", the middle of the magenta square on the screen, or nothing.
find_marker() {
    spectacle --background --nonotify --fullscreen --output "$SCREENSHOT_FILE" >/dev/null 2>&1 || return
    python3 - "$SCREENSHOT_FILE" <<'PY'
import sys
from PIL import Image
image = Image.open(sys.argv[1]).convert("RGB")
width, height = image.size
pixels = image.load()
xs, ys = [], []
for y in range(0, height, 2):
    for x in range(0, width, 2):
        if x < 60 and y < 60:
            continue   # DevReload's box square
        red, green, blue = pixels[x, y]
        if red > 220 and blue > 220 and green < 40:
            xs.append(x); ys.append(y)
if len(xs) >= 4:
    print(sum(xs) // len(xs), sum(ys) // len(ys))
PY
}

saved_time_before="$(stat -c %Y "$SAVED_VARIABLES" 2>/dev/null || echo 0)"
xdotool key --clearmodifiers KP_5; sleep 0.3   # L5: /gpfm debug pins

missed=0
for round in $(seq 1 "$ROUNDS"); do
    xdotool key --clearmodifiers "$MAP_KEY"; sleep 0.35
    position="$(find_marker)"
    # The first open after a reload loads the map: up to 3 more tries.
    for _ in 1 2 3; do [ -n "$position" ] && break; sleep 0.5; position="$(find_marker)"; done
    if [ -z "$position" ]; then
        missed=$((missed + 1))
        echo "round $round: no square on the map"
        xdotool key --clearmodifiers "$MAP_KEY"; sleep 0.3
        if [ "$round" = 1 ]; then echo "The test didn't start in the game (no square on the map)." >&2; exit 3; fi
        continue
    fi
    read -r x y <<< "$position"
    xdotool mousemove $((x + 160)) $((y + 160)); sleep 0.1   # off the pin first
    case $((round % 3)) in
        0) kind="same";  xdotool mousemove "$x" "$y" key --clearmodifiers "$MAP_KEY" ;;
        1) wait_seconds="${ROUND_WAITS[$(( (round / 3) % ${#ROUND_WAITS[@]} ))]}"
           kind="wait $wait_seconds"
           xdotool mousemove "$x" "$y"; sleep "$wait_seconds"; xdotool key --clearmodifiers "$MAP_KEY" ;;
        2) kind="leave"; xdotool mousemove "$x" "$y"; sleep 0.25
           xdotool mousemove $((x + 160)) $((y + 160)); sleep 0.05; xdotool key --clearmodifiers "$MAP_KEY" ;;
    esac
    echo "round $round: $kind at $x,$y"
    sleep 0.35
done
echo "Rounds done ($missed without a square). Waiting up to ${RELOAD_WAIT}s for the reload box's Reload."

for _ in $(seq 1 "$RELOAD_WAIT"); do
    [ "$(stat -c %Y "$SAVED_VARIABLES" 2>/dev/null || echo 0)" -gt "$saved_time_before" ] && break
    sleep 1
done
if [ "$(stat -c %Y "$SAVED_VARIABLES" 2>/dev/null || echo 0)" -le "$saved_time_before" ]; then
    echo "No reload in time: the results aren't saved." >&2; exit 5
fi
sleep 1
luajit - "$SAVED_VARIABLES" <<'LUA'
dofile(arg[1])
local test = GamepadFastMapDB and GamepadFastMapDB.debugPinClose
if not test then print("No results saved (the test didn't finish in the game).") os.exit(1) end
local summary = test.summary
print(string.format("%s, fix running: %s", test.date, tostring(test.fixRunning)))
for i, round in ipairs(test.rounds) do
    print(string.format("  close %2d: hovered %-5s frames %-4s stale %d secure %s cursor %s",
        i, tostring(round.hovered), tostring(round.frames), round.stale or -1, tostring(round.secure), tostring(round.cursor)))
end
for _, blocked in ipairs(test.blocked) do
    print(string.format("  BLOCKED in close %d: %s %s %s", blocked.round, blocked.event, blocked.addon, blocked.func))
end
print(string.format("%d closes, %d on a hovered pin (%d same frame), %d blocked, %d stale highlights, %d tainted",
    summary.closes, summary.hovered, summary.sameFrame, summary.blocked, summary.stale, summary.tainted))
print(test.passed and "PASSED" or "FAILED")
os.exit(test.passed and 0 or 1)
LUA
