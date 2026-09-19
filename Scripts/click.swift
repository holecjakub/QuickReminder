// Minimal CGEvent-based mouse helper for E2E scripting.
//
// Usage:
//   click X Y         move to (X,Y) and click (left down + up)
//   click move X Y     just move to (X,Y), no click
//
// Coordinates are top-left global points (same space screencapture -R uses).
// Compiled on demand by Scripts/e2e.sh into build/tools/click.
import CoreGraphics
import Foundation

let args = CommandLine.arguments
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
