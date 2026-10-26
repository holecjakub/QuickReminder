#!/bin/bash

# Raycast Script Command: type "Quick Reminder" in Raycast to open the notch panel.
# Add this folder in Raycast → Settings → Extensions → Script Commands → Add Directories.
#
# @raycast.schemaVersion 1
# @raycast.title Quick Reminder
# @raycast.mode silent
# @raycast.packageName QuickReminder
# @raycast.icon ✅
# @raycast.description Open the QuickReminder notch panel
# @raycast.keywords ["reminder", "připomínka", "notch"]

open "quickreminder://show"
