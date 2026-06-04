#!/bin/bash
# =============================================================
#  macOS Stealth Mode Manager
#
#  Options: "" (check status) | "1" (enable) | "0" (disable)
# =============================================================
SET_STEALTH_MODE={{setStealthMode}}
# =============================================================

SOCKETFILTERFW="/usr/libexec/ApplicationFirewall/socketfilterfw"

# Verify we're on macOS
if [[ ! -x "$SOCKETFILTERFW" ]]; then
  echo "Error: '$SOCKETFILTERFW' not found. This script requires macOS."
  exit 1
fi

get_status() {
  local output
  output=$(sudo "$SOCKETFILTERFW" --getstealthmode 2>&1)
  if [[ $? -ne 0 ]]; then
    echo "Error querying stealth mode: $output"
    exit 1
  fi
  if echo "$output" | grep -qi "on"; then
    echo "Stealth mode is: ENABLED"
  else
    echo "Stealth mode is: DISABLED"
  fi
}

set_mode() {
  local enable="$1"
  local flag action

  if [[ "$enable" == "1" ]]; then
    flag="on"
    action="Enabling"
  else
    flag="off"
    action="Disabling"
  fi

  echo "$action stealth mode..."
  local output
  output=$(sudo "$SOCKETFILTERFW" --setstealth "$flag" 2>&1)
  if [[ $? -ne 0 ]]; then
    echo "Error setting stealth mode: $output"
    exit 1
  fi
  [[ -n "$output" ]] && echo "$output"
  get_status
}

# Main logic
case "$SET_STEALTH_MODE" in
  "")  get_status ;;
  1)   set_mode 1 ;;
  0)   set_mode 0 ;;
  *)
    echo "Error: SET_STEALTH_MODE must be \"\", 0, or 1 (got '$SET_STEALTH_MODE')"
    exit 1
    ;;
esac
