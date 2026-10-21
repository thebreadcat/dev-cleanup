#!/usr/bin/env bash
# Installs the `dev-cleanup` command and, optionally, a weekly macOS schedule.
#
#   ./install.sh                         install the command to ~/.local/bin
#   ./install.sh --schedule ~/code       ...and run it weekly (Sunday 9:00) on ~/code
#   ./install.sh --schedule ~/code -- --days 60 --dropbox   extra flags for the weekly run
#   ./install.sh --uninstall             remove the command and the schedule

set -e

LABEL="com.github.dev-cleanup.weekly"
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/dev-cleanup"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/dev-cleanup.log"
HERE="$(cd "$(dirname "$0")" && pwd)"

unschedule() {
  if [ -f "$PLIST" ]; then
    launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "Removed weekly schedule."
  fi
}

xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

if [ "$1" = "--uninstall" ]; then
  unschedule
  rm -f "$BIN" && echo "Removed $BIN"
  exit 0
fi

SCHEDULE_DIRS=()
EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --schedule) shift; while [ $# -gt 0 ] && [ "$1" != "--" ]; do SCHEDULE_DIRS+=("$1"); shift; done; continue ;;
    --) shift; EXTRA=("$@"); break ;;
    *) echo "install.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$BIN_DIR"
cp "$HERE/dev-cleanup.sh" "$BIN"
chmod +x "$BIN"
echo "Installed $BIN"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "Note: $BIN_DIR isn't on your PATH. Add this to ~/.zshrc:"
     echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

if [ ${#SCHEDULE_DIRS[@]} -gt 0 ]; then
  [ "$(uname)" = "Darwin" ] || { echo "Scheduling uses launchd and is macOS only. Use cron elsewhere." >&2; exit 1; }
  ARGS="    <string>/bin/bash</string>
    <string>$(xml_escape "$BIN")</string>
    <string>--yes</string>"
  for a in ${EXTRA[@]+"${EXTRA[@]}"}; do
    ARGS="$ARGS
    <string>$(xml_escape "$a")</string>"
  done
  for d in "${SCHEDULE_DIRS[@]}"; do
    [ -d "$d" ] || { echo "Not a folder: $d" >&2; exit 1; }
    ARGS="$ARGS
    <string>$(xml_escape "$(cd "$d" && pwd -P)")</string>"
  done

  unschedule >/dev/null
  mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
$ARGS
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key><integer>0</integer>
    <key>Hour</key><integer>9</integer>
    <key>Minute</key><integer>0</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>$(xml_escape "$LOG")</string>
  <key>StandardErrorPath</key>
  <string>$(xml_escape "$LOG")</string>
</dict>
</plist>
EOF
  plutil -lint "$PLIST" >/dev/null
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "Scheduled weekly (Sunday 9:00) for: ${SCHEDULE_DIRS[*]}"
  echo "Log:      $LOG"
  echo "Run now:  launchctl kickstart gui/$(id -u)/$LABEL"
fi

echo
echo "Try a dry run:  dev-cleanup ~/code"
