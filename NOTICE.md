# Notice

QuickReminder — Copyright (c) 2026 Jakub Holec. Released under the MIT License (see `LICENSE`).

## Trademarks

QuickReminder is not affiliated with, endorsed by or sponsored by Apple Inc.

Apple, macOS, iOS, Xcode, SF Symbols, Reminders and Dynamic Island are trademarks of Apple Inc., registered in the U.S. and other countries. They are used here only to describe what the app runs on and what it works with. "Reminders" refers to the Apple Reminders app that QuickReminder reads and writes through the public EventKit framework.

QuickReminder is an independent, from-scratch implementation. It uses only public Apple frameworks (AppKit, SwiftUI, EventKit, Carbon hotkeys), contains no Apple source code, artwork or other assets, and uses no private APIs. The app icon is original work. The layout of the quick-reminder panel is inspired by the iOS quick-reminder overlay; its metrics were measured and are documented in words in `SPEC.md`.

## Third-party acknowledgements

No third-party code is bundled or linked. The notch silhouette in `Sources/QuickReminder/Notch/NotchShape.swift` was written for this project; its geometry (four quadratic fillets, closed / open corner radii, bleed around the hardware bezel, fallback pill size on displays without a notch) follows conventions documented publicly by these projects, which are credited here with thanks:

- **DynamicNotchKit** — Kai Azim (MrKai77), MIT License, Copyright (c) 2025 Kai Azim. https://github.com/MrKai77/DynamicNotchKit
- **NotchDrop** — Lakr Aream (Lakr233), MIT License, Copyright (c) 2024 Lakr Aream. https://github.com/Lakr233/NotchDrop
- **boring.notch** — TheBoredTeam, GPL-3.0. https://github.com/TheBoredTeam/boring.notch — consulted for its published constants only; no GPL-licensed code is included in QuickReminder.

The comparison of the three is in `reference/notch-research.md`.

SF Symbols are rendered by the system at runtime under Apple's SF Symbols licence terms; none are embedded as image assets.
