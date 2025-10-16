# ------------------------------------------------------------------------------
# Script Name:      chrome_update_on_idle.sh
# Author:           Catalin Andrei Enache
# Created Date:     2025-07-14
# Last Modified:    2025-08-22
#
# Description:
#   Monitors macOS idle time and performs a silent Google Chrome update when the user
#   has been idle for at least 20 minutes. Designed for scheduled execution via Jamf Pro.
#
#   - Downloads and expands the Chrome PKG. Retry up to 12 times on any error
#   - Parses Distribution for latest version
#   - Checks the installed version via Info.plist
#   - If update needed, waits for idle >=20 minutes (checks every 5 minutes for up to 9 hours)
#   - If Chrome was running prior, reopens it in the user session after install
#   - Creates a backup of Google Chrome.app and uses it to restore if instalaltion fails
#   - Installs via `installer` as root
#   - Cleans up temporary and backup files
#
# Requirements:
#   - macOS (bash, curl, pkgutil, installer, defaults, stat, launchctl, ioreg)
#
# Usage in Jamf Pro:
#   Run this script as a Jamf policy (Shell: /bin/bash). Schedule in a
#   maintenance window when users are typically idle.
# ------------------------------------------------------------------------------

#!/bin/bash
set -eo pipefail

# 1. Configuration
URL='https://dl.google.com/chrome/mac/stable/accept_tos%3Dhttps%253A%252F%252Fwww.google.com%252Fintl%252Fen_ph%252Fchrome%252Fterms%252F%26_and_accept_tos%3Dhttps%253A%252F%252Fpolicies.google.com%252Fterms/googlechrome.pkg'

# --- unique work dir in /var/tmp
WORKDIR="$(mktemp -d /private/var/tmp/ChromeUpdate.XXXXXXXX)" || { echo "mktemp failed"; exit 1; }
trap 'rm -rf "$WORKDIR"' EXIT

PKG_PATH="${WORKDIR}/googlechrome.pkg"
EXTRACT_DIR="${WORKDIR}/expanded"
CHROME_BACKUP="${WORKDIR}/Google Chrome.app"
DIST_FILE="${EXTRACT_DIR}/Distribution"

# 2. Download the PKG
curl -sSfL --retry 12 --retry-all-errors -o "${PKG_PATH}" "${URL}"

# 3. Expand the PKG
pkgutil --expand-full "${PKG_PATH}" "${EXTRACT_DIR}"
if [[ ! -f "${DIST_FILE}" ]]; then
  echo "Error: Distribution file missing at ${DIST_FILE}" >&2
  exit 1
fi

# 4. Parse latest version
LATEST_VERSION=$(grep -oE '<product[^>]+version="[^"]+"' "${DIST_FILE}" \
  | sed -E 's/.*version="([^"]+)".*/\1/')
if [[ -z "${LATEST_VERSION}" ]]; then
  echo "Error: Could not parse latest version" >&2
  exit 1
fi

echo "Latest Chrome package version: ${LATEST_VERSION}"

# 5. Get installed version
PLIST="/Applications/Google Chrome.app/Contents/Info.plist"
if [[ -f "${PLIST}" ]]; then
  INSTALLED_VERSION=$(defaults read "${PLIST}" CFBundleShortVersionString)
else
  INSTALLED_VERSION="0"
fi

echo "Installed Chrome version: ${INSTALLED_VERSION}"

# 6. Compare versions
if [[ $(printf '%s\n%s' "${LATEST_VERSION}" "${INSTALLED_VERSION}" | sort -V | head -n1) == "${LATEST_VERSION}" ]]; then
  echo "Installed version is up-to-date or newer; exiting."
  exit 0
fi

echo "Update required: ${INSTALLED_VERSION} → ${LATEST_VERSION}"


# 7. Monitor idle time and wait for >=20 minutes
TOTAL_CHECKS=108        # 9 hours at 5-minute intervals
INTERVAL_SECONDS=300    # 5 minutes
IDLE_THRESHOLD=1200     # 20 minutes in seconds

for ((i=1; i<=TOTAL_CHECKS; i++)); do
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Idle check #$i"
  RAW_IDLE_NS=$(ioreg -c IOHIDSystem 2>/dev/null \
    | sed -En 's/.*HIDIdleTime.*= *([0-9]+).*/\1/p')
  if [[ -z "${RAW_IDLE_NS}" ]]; then
    echo "Warning: Could not read idle time; assuming 0"
    IDLETIME=0
  else
    IDLETIME=$((RAW_IDLE_NS / 1000000000))
  fi
  echo "Idle time: ${IDLETIME}s"

  if (( IDLETIME >= IDLE_THRESHOLD )); then
    echo "Idle threshold reached (>=${IDLE_THRESHOLD}s); proceeding with update."
    break
  fi

  if (( i < TOTAL_CHECKS )); then
    sleep "${INTERVAL_SECONDS}"
  fi

done

# After loop, if threshold never reached, abort
if (( i > TOTAL_CHECKS && IDLETIME < IDLE_THRESHOLD )); then
  echo "User not idle >=20 minutes within 9-hour window; aborting."
  exit 0
fi

# 8. Check if Chrome is running
if pgrep -x "Google Chrome" >/dev/null; then
  REOPEN=true
  echo "Chrome is currently running; will close reopen after update."
  osascript -e 'quit app "Google Chrome"'
else
  REOPEN=false
  echo "Chrome is not running."
fi

# 9. Backup existing Chrome & install update

CHROME_APP="/Applications/Google Chrome.app"

if [[ -d "${CHROME_APP}" ]]; then
echo "Backing up existing Chrome to: ${CHROME_BACKUP}"
cp -R "${CHROME_APP}" "${CHROME_BACKUP}"
else
  echo "Warning: Chrome app not found at expected location (${CHROME_APP})"
fi

echo "Installing Chrome pkg..."
if installer -pkg "${PKG_PATH}" -target /; then
  echo "Chrome installation successful."
if [[ -d "${CHROME_BACKUP}" ]]; then
  echo "Removing backup: ${CHROME_BACKUP}"
  rm -rf "${CHROME_BACKUP}"
fi
else
  echo "Chrome installation failed. Restoring from backup..."
  if [[ -d "${CHROME_BACKUP}" ]]; then
    rm -rf "${CHROME_APP}"
    mv "${CHROME_BACKUP}" "${CHROME_APP}"
    echo "Chrome has been restored from backup."
  else
    echo "Error: Backup not found. Chrome may be left in a broken state." >&2
  fi
  exit 1
fi

# 10. Reopen Chrome if needed
#if [[ "${REOPEN}" == true ]]; then
#  USER=$(stat -f%Su /dev/console)
#  launchctl asuser "$(id -u "${USER}")" open -a "Google Chrome"
#fi

# 11. Reopen Chrome (always)
USER=$(stat -f%Su /dev/console)
launchctl asuser "$(id -u "${USER}")" open -a "Google Chrome"

# 12. Cleanup
echo "Cleaning up temporary files..."
echo "Cleanup handled by trap for $WORKDIR"

echo "Chrome has been updated to ${LATEST_VERSION}"
