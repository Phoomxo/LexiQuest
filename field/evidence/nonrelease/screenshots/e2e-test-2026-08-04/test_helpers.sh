#!/usr/bin/env bash
# Helper functions for LexiQuest e2e testing via adb
SERIAL=9582188822004C6
DIR="C:/Users/Phet/Documents/LexiQuest/.worktrees/p8a-voice-architecture/field/evidence/nonrelease/screenshots/e2e-test-2026-08-04"
export MSYS_NO_PATHCONV=1

# Check device; reconnect if needed
ck() {
  if ! adb devices | grep -q "$SERIAL.*device"; then
    echo "DEVICE LOST - reconnecting..."
    adb kill-server; sleep 2; adb start-server; sleep 2
  fi
  adb devices | grep "$SERIAL" || echo "STILL NO DEVICE"
}

# Tap at coordinates after verifying device
tap() {
  ck
  adb -s "$SERIAL" shell input tap "$1" "$2"
}

# Dump UI to a fresh file and echo it
dump() {
  ck
  adb -s "$SERIAL" shell uiautomator dump /sdcard/wd.xml >/dev/null 2>&1
  adb -s "$SERIAL" shell cat /sdcard/wd.xml 2>/dev/null
}

# Find element bounds by content-desc substring; prints "x y" center
# Extracts the FIRST bounds="[x1,y1][x2,y2]" on the matched node line
findc() {
  local desc="$1"
  local b
  b=$(dump | tr '<' '\n' | grep "content-desc=\"$desc\"" | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1)
  if [ -z "$b" ]; then
    # fallback: substring match anywhere in node
    b=$(dump | tr '<' '\n' | grep "$desc" | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1)
  fi
  echo "$b" | grep -oE '[0-9]+' | awk 'NR==1{a=$1} NR==2{b=$1} NR==3{c=$1} NR==4{d=$1} END{if(NR>=4) print int((a+c)/2), int((b+d)/2)}'
}

# Tap element by content-desc substring
tapc() {
  local desc="$1"
  local coords
  coords=$(findc "$desc")
  if [ -z "$coords" ]; then
    echo "NOT FOUND: $desc"
    return 1
  fi
  echo "Tapping '$desc' at $coords"
  tap $coords
}

# Screenshot with name
shot() {
  ck
  adb -s "$SERIAL" exec-out screencap -p > "$DIR/$1.png"
  echo "Saved $1.png"
}

# Type ASCII text
typetext() {
  ck
  adb -s "$SERIAL" shell input text "$1"
}

# Type Unicode text via ADBKeyboard
typethai() {
  ck
  adb -s "$SERIAL" shell am broadcast -a ADB_INPUT_TEXT --es msg "$1" >/dev/null 2>&1
}

# Show all visible content-desc and text
showui() {
  dump | tr '<' '\n' | grep -oE 'content-desc="[^"]*"|text="[^"]*"' | grep -ivE 'content-desc=""|text=""'
}
