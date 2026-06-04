#!/bin/bash
# =============================================================
#  macOS Firewall Manager
#
#  Options: "" (check status) | "1" (enable) | "0" (disable)
# =============================================================
SET_FIREWALL={{setFirewallStatus}}
# =============================================================

SOCKETFILTERFW="/usr/libexec/ApplicationFirewall/socketfilterfw"

# Verify we're on macOS
if [[ ! -x "$SOCKETFILTERFW" ]]; then
  echo "Error: '$SOCKETFILTERFW' not found. This script requires macOS."
  exit 1
fi

get_status() {
  local output
  output=$(sudo "$SOCKETFILTERFW" --getglobalstate 2>&1)
  if [[ $? -ne 0 ]]; then
    echo "Error querying firewall: $output"
    exit 1
  fi
  if echo "$output" | grep -qi "enabled"; then
    echo "Firewall is: ENABLED"
  else
    echo "Firewall is: DISABLED"
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

  echo "$action firewall..."
  local output
  output=$(sudo "$SOCKETFILTERFW" --setglobalstate "$flag" 2>&1)
  if [[ $? -ne 0 ]]; then
    echo "Error setting firewall: $output"
    exit 1
  fi
  [[ -n "$output" ]] && echo "$output"
  get_status
}

# Main logic
case "$SET_FIREWALL" in
  "")  get_status ;;
  1)   set_mode 1 ;;
  0)   set_mode 0 ;;
  *)
    echo "Error: SET_FIREWALL must be \"\", 0, or 1 (got '$SET_FIREWALL')"
    exit 1
    ;;
esac
