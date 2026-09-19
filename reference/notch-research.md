# Notch panel research

Sources: [boring.notch](https://github.com/TheBoredTeam/boring.notch), [NotchDrop](https://github.com/Lakr233/NotchDrop), [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit). All three draw the same shape — DynamicNotchKit's `NotchShape` is the original; boring.notch vendored it verbatim.

## Window configuration

| | boring.notch | NotchDrop | DynamicNotchKit |
|---|---|---|---|
| class | `NSPanel` (`isFloatingPanel = true`) | `NSWindow` | `NSPanel` |
| styleMask | `[.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]` | `[.borderless, .fullSizeContentView]` | passed in by caller |
| level | `.mainMenu + 3` | `.statusBar + 8` | `.screenSaver` |
| collectionBehavior | `[.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]` | same | `[.canJoinAllSpaces, .stationary]` |
| key/main | `canBecomeKey = false` | both `true` | `canBecomeKey = true` |

All share: `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false` (SwiftUI draws it so it can animate), `isMovable = false`, `titleVisibility = .hidden`, `titlebarAppearsTransparent = true`, `isReleasedWhenClosed = false`.

**Sizing/positioning.** The window is *not* the notch — it is a big rect pinned to the top of `screen.frame` (not `visibleFrame`, which excludes the menu bar), and the notch shape is drawn at its top-centre.

boring.notch: `openNotchSize 640×190 + shadowPadding 20`, origin `x = frame.midX - width/2`, `y = frame.maxY - height`. NotchDrop: full screen width × a fixed 200pt top strip. DynamicNotchKit sizes the panel to its content.

`ignoresMouseEvents` is never set globally — the panel stays hittable and SwiftUI decides. NotchDrop `.disabled(true)`s the shape itself and hit-tests only the content. Keep the closed hit region at the notch rect; expand it only while open.

## Shape and sizes

`NSScreen`: `safeAreaInsets.top` = notch height (38pt on 14"/16" MBP); width = `frame.width - auxiliaryTopLeftArea!.width - auxiliaryTopRightArea!.width` (221pt here). `nil` auxiliary areas ⇒ no notch.

The shape rect is `notchWidth + 2 × topCornerRadius` wide (DynamicNotchKit `minWidth`), because the top fillets consume `topCornerRadius` of horizontal space on each side before the straight sides begin.

Radii: closed `6 / 14`; open `19 / 24` (boring.notch), `15 / 20` (DynamicNotchKit preset), `32` bottom-only (NotchDrop).

Fake notch without hardware: NotchDrop `150×28`, DynamicNotchKit `300 × menuBarHeight` (`frame.maxY - visibleFrame.maxY`), boring.notch width 185 × 32.

## Animation

- boring.notch: `.spring(.bouncy(duration: 0.4))` for everything (fallback `.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)` pre-macOS 14).
- DynamicNotchKit: open `.bouncy(duration: 0.4)`, close `.smooth(duration: 0.4)`, compact↔expanded `.snappy(duration: 0.4)`. Content enters/leaves with `.blur(intensity: 10) + .scale(y: 0.6, anchor: .top) + .opacity`; hover width changes use `.smooth`.
- NotchDrop: `.interactiveSpring(duration: 0.5, extraBounce: 0.25, blendDuration: 0.125)`; content transition `.scale + .opacity + .offset(y: -openedHeight/2)`.

Animate both radii (via `AnimatablePair`) and the frame in one transaction; fade/blur content slightly behind the geometry so text doesn't stretch. A bouncy spring overshoots the mask — back the content with a rectangle padded `-50` (DynamicNotchKit) or the edge flashes transparent.

## Gotchas

- **Draw bigger than the hardware.** boring.notch adds `+4` to the computed notch width; NotchDrop uses `inset: -4`. Without it an anti-aliased seam of wallpaper shows along the cutout. DynamicNotchKit additionally pads the mask `.horizontal, 0.5`.
- **Menu bar clicks.** At `level >= .mainMenu` the panel swallows clicks on the menu bar behind it. Keep the closed window narrow (notch width only) or let the closed state ignore mouse events.
- **Full screen.** `.fullScreenAuxiliary` + `.stationary` + `.canJoinAllSpaces` are required for the panel to survive over full-screen apps; boring.notch additionally puts the window in a private `CGSSpace` (`NotchSpaceManager`).
- **Screen changes.** Recompute on `NSApplication.didChangeScreenParametersNotification`; rebuild the window if it changed screens.
- **`visibleFrame` is wrong for positioning** — it starts below the menu bar. Use `frame.maxY`.
- **Hover**: `.onHover` on the mask fires on the bounding box, not the path — attach it to the content frame.
