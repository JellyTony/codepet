import AppKit
import ImageIO

/// pet.json manifest — identical schema to Codex's pet contract so CodePet can
/// load real Codex pets verbatim.
struct PetManifest: Codable {
    var id: String
    var displayName: String
    var description: String?
    var spritesheetPath: String?       // Codex spritesheet pets
    var form: String?                  // CodePet vector pets: blob|cat|robot|ghost
    var color: String?                 // identity colour, hex "#rrggbb"

    enum CodingKeys: String, CodingKey {
        case id, displayName, description, spritesheetPath, form, color
    }
}

/// A loaded Petdex / Codex spritesheet (see `SpriteContract`): a grid of
/// `columns × PetAction.count` cells, recommended 1536×1872. Slices each row
/// into its non-empty animation frames, keyed by `PetAction`.
final class SpriteAtlas {
    let manifest: PetManifest
    let directory: URL
    private let sheetURL: URL
    private var actionFrames: [Int: [CGImage]] = [:]

    /// The spritesheet is decoded lazily on first frame access, so building the
    /// catalog (one atlas per pet) stays cheap and only pets actually rendered
    /// ever hold a decoded bitmap.
    private lazy var image: CGImage? = {
        guard let src = CGImageSourceCreateWithURL(sheetURL as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }()

    init?(directory: URL) {
        let manifestURL = directory.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let m = try? JSONDecoder().decode(PetManifest.self, from: data),
              let sheetPath = m.spritesheetPath else {
            return nil
        }
        let sheetURL = directory.appendingPathComponent(sheetPath)
        // Validate it's a readable image from the header only (no pixel decode),
        // so a sprite-less or corrupt entry falls back to a vector pet as before.
        guard let src = CGImageSourceCreateWithURL(sheetURL as CFURL, nil),
              CGImageSourceGetCount(src) > 0 else {
            return nil
        }
        self.manifest = m
        self.directory = directory
        self.sheetURL = sheetURL
    }

    /// Actual cell width/height — derive from the sheet so atlases that aren't
    /// exactly 1536×1872 still slice into the contract's grid.
    private var cw: Int { (image?.width ?? 0) / SpriteContract.columns }
    private var ch: Int { (image?.height ?? 0) / SpriteContract.rows }

    /// Non-empty frames for an action's row, left to right. Cached.
    func frames(_ action: PetAction) -> [CGImage] {
        let row = SpriteContract.row(for: action)
        if let cached = actionFrames[row] { return cached }
        guard let image = image, cw > 0, ch > 0 else { return [] }
        var result: [CGImage] = []
        let y = row * ch
        for c in 0..<SpriteContract.columns {
            let rect = CGRect(x: c * cw, y: y, width: cw, height: ch)
            guard let cell = image.cropping(to: rect) else { continue }
            if !isTransparent(cell) { result.append(cell) }
        }
        if result.isEmpty, let whole = image.cropping(to: CGRect(x: 0, y: y, width: cw, height: ch)) {
            result = [whole]
        }
        actionFrames[row] = result
        return result
    }

    var cellSize: CGSize { CGSize(width: cw, height: ch) }

    /// Cheap transparency probe: sample alpha across a sparse grid.
    private func isTransparent(_ cg: CGImage) -> Bool {
        guard let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return true }
        let bpp = cg.bitsPerPixel / 8
        guard bpp >= 4 else { return false } // no alpha channel → assume opaque
        let bpr = cg.bytesPerRow
        let alphaInfo = cg.alphaInfo
        // Alpha byte offset for common 8-bit RGBA/BGRA/ARGB layouts.
        let alphaFirst = (alphaInfo == .premultipliedFirst || alphaInfo == .first)
        let stepX = max(1, cg.width / 12)
        let stepY = max(1, cg.height / 12)
        var y = 0
        while y < cg.height {
            var x = 0
            while x < cg.width {
                let off = y * bpr + x * bpp + (alphaFirst ? 0 : bpp - 1)
                if Int(ptr[off]) > 8 { return false }
                x += stepX
            }
            y += stepY
        }
        return true
    }
}
