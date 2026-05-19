# QuickReminder

A macOS 26 menu bar app that provides an iOS-style floating overlay for quickly capturing reminders.

## Build

```bash
./build.sh
```

This installs xcodegen if needed, generates the Xcode project, and builds. The app lands at:

```
build/Build/Products/Debug/QuickReminder.app
```

## Run

```bash
open build/Build/Products/Debug/QuickReminder.app
```

On first launch, macOS will ask for Reminders permission — click Allow.

## Usage

| Action | Result |
|--------|--------|
| `⇧⌘R` | Show/hide the overlay |
| `⌘↩` | Save the reminder and dismiss |
| `Esc` or click outside | Dismiss without saving |
| Click "Reminders ▾" | Pick target list |
| Calendar icon | Set due date/time |
| Location icon | Add a location note |
| Flag icon | Toggle flagged state |

## Change the hotkey

Open the menu bar icon → Settings, then click the recorder next to "Show Quick Reminder" and press your preferred shortcut.

## Troubleshoot Reminders permission

If reminders don't save: System Settings → Privacy & Security → Reminders → enable QuickReminder.

## Requirements

- macOS 26.0 (Tahoe) or later
- Xcode 26.5 / Swift 6.3.2 for building
