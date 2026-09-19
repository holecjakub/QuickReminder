// Minimal CGEvent-based mouse helper for E2E scripting.
//
// Usage:
//   click X Y         move to (X,Y) and click (left down + up)
//   click move X Y     just move to (X,Y), no click
//   click geometry     print "width height notchHeight notchMidX hasNotch" of the built-in display
//
// Coordinates are top-left global points (same space screencapture -R uses).
// Compiled on demand by Scripts/e2e.sh into build/tools/click.
import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
if args.count > 1, args[1] == "geometry" {
    // Top-left global points, so the E2E suite can derive every coordinate instead of
    // hard-coding a 14" MacBook Pro.
    let screens = NSScreen.screens
    let builtIn = screens.first { $0.safeAreaInsets.top > 0 } ?? screens.first
    guard let s = builtIn else { print("0 0 0 0 0"); exit(0) }
    let main = NSScreen.main ?? s
    let midX = (s.frame.minX - main.frame.minX) + s.frame.width / 2
    print(String(format: "%.0f %.0f %.0f %.1f %d", s.frame.width, s.frame.height, s.safeAreaInsets.top, midX, s.safeAreaInsets.top > 0 ? 1 : 0))
    exit(0)
}
var move = false
var idx = 1
if args.count > 1, args[1] == "move" { move = true; idx = 2 }
guard args.count > idx + 1, let x = Double(args[idx]), let y = Double(args[idx + 1]) else {
    print("usage: click [move] x y")
    exit(1)
}
let p = CGPoint(x: x, y: y)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(60_000)
if !move {
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(40_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
