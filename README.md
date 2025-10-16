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

# It created to run from Jamf Pro. The idle time was added to make sure that the user is not impacted during his work by the update script. 
