#!/bin/sh

# timezone Europe/Kyiv
export TZ="EET-2EEST,M3.5.0/3,M10.5.0/4"

OUTPUT_DIR="../output"
OUTPUT_SVG_FILE="$OUTPUT_DIR/image.svg"
OUTPUT_PNG_FILE="$OUTPUT_DIR/image.png"
OUTPUT_OPTIMIZED_PNG_FILE="$OUTPUT_DIR/image_optimized.png"
EXIT_FILE="$OUTPUT_DIR/EXIT"
SETTINGS_FILE="$OUTPUT_DIR/settings"
FONT_PATH="../fonts/DejaVuSans.ttf"
LOG_FILE="/tmp/kclock.log"

# Full flash refresh every N minute ticks (partial updates in between)
FULL_REFRESH_MINUTES=10
MINUTE_TICK=0

ORIENTATION="landscape_right"
FONT_SIZE=240
FONT_SIZE_MIN=80
FONT_SIZE_MAX=300
FONT_SIZE_STEP=20

# K4 keycodes (press = "CODE 1")
KEY_HOME="102 1"
KEY_UP="103 1"
KEY_DOWN="108 1"
KEY_LEFT="105 1"
KEY_RIGHT="106 1"
KEY_PAGEUP="104 1"
KEY_PAGEDOWN="109 1"

log() {
  echo "$(date +%H:%M:%S) $*" >>"$LOG_FILE"
}

stop_framework() {
  /etc/init.d/framework stop || true
  /usr/bin/lipc-set-prop com.lab126.powerd preventScreenSaver 1 || true
  /usr/bin/lipc-set-prop com.lab126.wifid enable 0 || true
}

start_framework() {
  /usr/bin/lipc-set-prop -- com.lab126.powerd preventScreenSaver 0 || true
  /etc/init.d/framework start || true
}

get_battery_level() {
  LEVEL=$(gasgauge-info -c 2>/dev/null | sed 's/[^0-9]//g')
  if [ -z "$LEVEL" ]; then
    echo "0"
  else
    echo "$LEVEL"
  fi
}

get_ukrainian_weekday() {
  case $(date +%u) in
    1) echo "Понеділок" ;;
    2) echo "Вівторок" ;;
    3) echo "Середа" ;;
    4) echo "Четвер" ;;
    5) echo "Пятниця" ;;
    6) echo "Субота" ;;
    7) echo "Неділя" ;;
    *) echo "День" ;;
  esac
}

strip_leading_zero() {
  echo "$1" | sed 's/^0//'
}

get_ukrainian_month() {
  case $(strip_leading_zero "$(date +%m)") in
    1) echo "січня" ;;
    2) echo "лютого" ;;
    3) echo "березня" ;;
    4) echo "квітня" ;;
    5) echo "травня" ;;
    6) echo "червня" ;;
    7) echo "липня" ;;
    8) echo "серпня" ;;
    9) echo "вересня" ;;
    10) echo "жовтня" ;;
    11) echo "листопада" ;;
    12) echo "грудня" ;;
    *) echo "" ;;
  esac
}

get_ukrainian_date() {
  DAY=$(strip_leading_zero "$(date +%d)")
  [ -n "$DAY" ] || DAY=$(date +%d)
  echo "$DAY $(get_ukrainian_month) $(date +%Y)"
}

load_settings() {
  if [ -f "$SETTINGS_FILE" ]; then
    ORIENTATION_LOADED=$(sed -n 's/^ORIENTATION=//p' "$SETTINGS_FILE" | head -n 1)
    FONT_SIZE_LOADED=$(sed -n 's/^FONT_SIZE=//p' "$SETTINGS_FILE" | head -n 1)
    [ -n "$ORIENTATION_LOADED" ] && ORIENTATION="$ORIENTATION_LOADED"
    [ -n "$FONT_SIZE_LOADED" ] && FONT_SIZE="$FONT_SIZE_LOADED"
  fi

  case "$ORIENTATION" in
    portrait|landscape_left|landscape_right) ;;
    *) ORIENTATION="landscape_right" ;;
  esac

  FONT_SIZE=$(echo "$FONT_SIZE" | sed 's/[^0-9]//g')
  [ -n "$FONT_SIZE" ] || FONT_SIZE=240
  if [ "$FONT_SIZE" -lt "$FONT_SIZE_MIN" ]; then
    FONT_SIZE=$FONT_SIZE_MIN
  fi
  if [ "$FONT_SIZE" -gt "$FONT_SIZE_MAX" ]; then
    FONT_SIZE=$FONT_SIZE_MAX
  fi
}

save_settings() {
  mkdir -p "$OUTPUT_DIR"
  echo "ORIENTATION=$ORIENTATION" >"$SETTINGS_FILE"
  echo "FONT_SIZE=$FONT_SIZE" >>"$SETTINGS_FILE"
}

increase_font() {
  load_settings
  FONT_SIZE=$((FONT_SIZE + FONT_SIZE_STEP))
  if [ "$FONT_SIZE" -gt "$FONT_SIZE_MAX" ]; then
    FONT_SIZE=$FONT_SIZE_MAX
  fi
  save_settings
  log "font+ $FONT_SIZE"
}

decrease_font() {
  load_settings
  FONT_SIZE=$((FONT_SIZE - FONT_SIZE_STEP))
  if [ "$FONT_SIZE" -lt "$FONT_SIZE_MIN" ]; then
    FONT_SIZE=$FONT_SIZE_MIN
  fi
  save_settings
  log "font- $FONT_SIZE"
}

set_orientation() {
  ORIENTATION="$1"
  save_settings
}

resolve_font_path() {
  if [ -f "$FONT_PATH" ]; then
    DIR=$(cd "$(dirname "$FONT_PATH")" && pwd)
    echo "$DIR/$(basename "$FONT_PATH")"
  else
    # Relative to output/image.svg
    echo "../fonts/DejaVuSans.ttf"
  fi
}

build_svg() {
  HOURS=$(strip_leading_zero "$(date +%H)")
  MINUTES=$(strip_leading_zero "$(date +%M)")
  [ -n "$HOURS" ] || HOURS=0
  [ -n "$MINUTES" ] || MINUTES=0
  HOURS_PADDED=$(printf "%02d" "$HOURS")
  MINUTES_PADDED=$(printf "%02d" "$MINUTES")

  DATE=$(get_ukrainian_date)
  WEEKDAY=$(get_ukrainian_weekday)
  BATTERY_LABEL="Батарея"

  BATTERY_LEVEL=$(get_battery_level)
  BATTERY_WIDTH=$((BATTERY_LEVEL * 2))

  ABS_FONT_PATH=$(resolve_font_path)

  if [ "$ORIENTATION" = "portrait" ]; then
    TEMPLATE_FILE="template_portrait.svg"
    TRANSFORM=""
    # Content band 160..750 → mid 455; baseline ≈ mid + 0.35*size
    CLOCK_Y=$((455 + FONT_SIZE * 35 / 100))
  else
    TEMPLATE_FILE="template_landscape.svg"
    if [ "$ORIENTATION" = "landscape_left" ]; then
      TRANSFORM="translate(0, 800) rotate(-90)"
    else
      TRANSFORM="translate(600, 0) rotate(90)"
    fi
    # Content band 130..550 → mid 340
    CLOCK_Y=$((340 + FONT_SIZE * 35 / 100))
  fi

  if [ ! -f "$TEMPLATE_FILE" ]; then
    log "ERROR missing template $TEMPLATE_FILE"
    return 1
  fi

  sed \
    -e "s|FONT_PATH|$ABS_FONT_PATH|" \
    -e "s|LANDSCAPE_TRANSFORM|$TRANSFORM|" \
    -e "s/CLOCK_Y/$CLOCK_Y/" \
    -e "s/FONT_SIZE/$FONT_SIZE/" \
    -e "s/BATTERY_WIDTH/$BATTERY_WIDTH/" \
    -e "s/BATTERY_LEVEL/$BATTERY_LEVEL/" \
    -e "s/BATTERY_LABEL/$BATTERY_LABEL/" \
    -e "s/WEEKDAY/$WEEKDAY/" \
    -e "s/DATE/$DATE/" \
    -e "s/HOURS/$HOURS_PADDED/" \
    -e "s/MINUTES/$MINUTES_PADDED/" \
    "$TEMPLATE_FILE" >"$OUTPUT_SVG_FILE"
}

build_png() {
  ../third_party/rsvg-convert --background-color=white -o "$OUTPUT_PNG_FILE" "$OUTPUT_SVG_FILE" || {
    log "ERROR rsvg-convert failed"
    return 1
  }
  ../third_party/pngcrush -c 0 "$OUTPUT_PNG_FILE" "$OUTPUT_OPTIMIZED_PNG_FILE" || {
    log "ERROR pngcrush failed"
    return 1
  }
}

print_clock_full() {
  load_settings
  build_svg || return 1
  build_png || return 1
  # Full refresh: clear + draw (flash). Needed to clear ghosting.
  eips -c || true
  eips -f -g "$OUTPUT_OPTIMIZED_PNG_FILE" 2>/dev/null || \
    eips -g "$OUTPUT_OPTIMIZED_PNG_FILE" || log "ERROR eips failed"
  MINUTE_TICK=0
  log "refresh=full"
}

print_clock_partial() {
  load_settings
  build_svg || return 1
  build_png || return 1
  # K4: -x/-y unsupported; omit -c/-f for a quieter partial waveform update.
  eips -g "$OUTPUT_OPTIMIZED_PNG_FILE" || log "ERROR eips partial failed"
  log "refresh=partial"
}

# Back-compat name used by key handlers — always full after UI changes
print_clock() {
  print_clock_full
}

process_key() {
  while true; do
    [ -f "$EXIT_FILE" ] && exit 0
    KEY="$(waitforkey)"
    log "key=$KEY"
    case "$KEY" in
      "$KEY_HOME")
        touch "$EXIT_FILE"
        start_framework
        exit 0
        ;;
      "$KEY_UP")
        set_orientation "portrait"
        print_clock_full
        ;;
      "$KEY_DOWN")
        decrease_font
        print_clock_full
        ;;
      "$KEY_LEFT")
        set_orientation "landscape_left"
        print_clock_full
        ;;
      "$KEY_RIGHT")
        set_orientation "landscape_right"
        print_clock_full
        ;;
      "$KEY_PAGEUP")
        increase_font
        print_clock_full
        ;;
      "$KEY_PAGEDOWN")
        decrease_font
        print_clock_full
        ;;
      *)
        case "$KEY" in
          104)
            increase_font
            print_clock_full
            ;;
          109|108)
            decrease_font
            print_clock_full
            ;;
        esac
        ;;
    esac
  done
}

sleep_until_next_minute() {
  SEC=$(date +%S)
  SEC=$(strip_leading_zero "$SEC")
  [ -n "$SEC" ] || SEC=0
  REMAIN=$((60 - SEC))
  [ "$REMAIN" -lt 1 ] && REMAIN=60
  i=0
  while [ "$i" -lt "$REMAIN" ]; do
    [ -f "$EXIT_FILE" ] && return 1
    sleep 1
    i=$((i + 1))
  done
  return 0
}

print_clock_loop() {
  while true; do
    [ -f "$EXIT_FILE" ] && exit 0
    sleep_until_next_minute || exit 0
    [ -f "$EXIT_FILE" ] && exit 0

    MINUTE_TICK=$((MINUTE_TICK + 1))
    if [ "$MINUTE_TICK" -ge "$FULL_REFRESH_MINUTES" ]; then
      print_clock_full
    else
      print_clock_partial
    fi
  done
}

main() {
  cd "$(dirname "$0")" || exit 1
  mkdir -p "$OUTPUT_DIR"
  : >"$LOG_FILE"
  log "start cwd=$(pwd)"

  [ -f "$EXIT_FILE" ] && rm -f "$EXIT_FILE"

  load_settings
  save_settings
  log "orientation=$ORIENTATION font=$FONT_SIZE"

  stop_framework
  print_clock_full || log "ERROR first print_clock failed"

  process_key &
  print_clock_loop &
  wait
}

main
