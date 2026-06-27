import AppKit
import CoreGraphics
import Foundation

// Generate a Codex-format test atlas: 1536×1872, 8 cols × 9 rows, 192×208 cells.
// Each row gets a distinct hue; a dot bounces across the 8 frames so playback is
// visibly animated. Row 8 intentionally uses only 5 frames to exercise the
// non-empty-frame detection.

let cols = 8, rows = 9, cw = 192, ch = 208
let W = cols * cw, H = rows * ch

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("ctx")
}
// Transparent background.
ctx.clear(CGRect(x: 0, y: 0, width: W, height: H))

let rowNames = ["idle", "run-R", "run-L", "wave", "jump", "fail", "wait", "run", "review"]

for r in 0..<rows {
    let frames = (r == 8) ? 5 : 8
    let hue = CGFloat(r) / CGFloat(rows)
    let color = NSColor(hue: hue, saturation: 0.7, brightness: 0.95, alpha: 1).cgColor
    for c in 0..<frames {
        // Note: CGContext origin is bottom-left; row 0 should be the TOP row to
        // match the atlas contract, so flip vertically.
        let x = c * cw
        let y = (rows - 1 - r) * ch
        // Body.
        let bw = 120, bh = 130
        let bx = x + (cw - bw) / 2
        let bob = Int(20 * sin(Double(c) / Double(max(1, frames - 1)) * .pi))
        let by = y + (ch - bh) / 2 + bob
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: bx, y: by, width: bw, height: bh))
        // Eyes.
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: bx + 30, y: by + 70, width: 24, height: 24))
        ctx.fillEllipse(in: CGRect(x: bx + 66, y: by + 70, width: 24, height: 24))
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillEllipse(in: CGRect(x: bx + 38, y: by + 78, width: 10, height: 10))
        ctx.fillEllipse(in: CGRect(x: bx + 74, y: by + 78, width: 10, height: 10))
    }
}

guard let img = ctx.makeImage() else { fatalError("img") }

let outDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".codepet/pets/testsprite", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let sheetURL = outDir.appendingPathComponent("spritesheet.png")
guard let dest = CGImageDestinationCreateWithURL(sheetURL as CFURL,
        "public.png" as CFString, 1, nil) else { fatalError("dest") }
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)

let manifest = """
{
  "id": "testsprite",
  "displayName": "Test Sprite",
  "description": "Synthetic atlas to validate the Codex-format loader.",
  "spritesheetPath": "spritesheet.png"
}
"""
try? manifest.write(to: outDir.appendingPathComponent("pet.json"), atomically: true, encoding: .utf8)
print("✓ wrote \(sheetURL.path) (\(W)x\(H), \(cols)x\(rows))")
