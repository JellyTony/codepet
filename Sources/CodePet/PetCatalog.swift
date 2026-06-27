import AppKit
import SwiftUI

/// One selectable pet — a real spritesheet pet, a CodePet vector pet defined by
/// a manifest, or a built-in vector form drawn procedurally.
struct PetEntry {
    let key: String          // selection key stored in config
    let title: String        // menu label
    let atlas: SpriteAtlas?  // non-nil for spritesheet pets
    let species: PetSpecies? // non-nil for vector pets
    let baseColor: Color     // identity colour for vector pets
    let source: String       // "codepet", "codex", or "built-in"
}

/// Discovers all installable pets — anything following the `SpriteContract`
/// loads with zero per-pet configuration:
///  • Petdex gallery pets in ~/.petdex/pets/<slug>/  (`petdex install <slug>`)
///  • spritesheet pets in ~/.codepet/pets/<name>/pet.json (+ spritesheet)
///  • CodePet vector pets in ~/.codepet/pets/<name>/pet.json (form + color)
///  • real Codex pets in ~/.codex/pets/<name>/pet.json (loaded verbatim)
///  • built-in vector forms (always available, zero install)
///
/// Petdex installs the same pet into both ~/.petdex/pets and ~/.codex/pets;
/// `seen` de-dupes by slug so it surfaces once, under its first source.
enum PetCatalog {
    /// Where installable pets live, in priority order (first source wins on slug
    /// collisions). Petdex installs into ~/.petdex; ~/.codex covers Codex pets.
    static let petDirs: [(url: URL, source: String)] = [
        (Paths.dir.appendingPathComponent("pets", isDirectory: true), "codepet"),
        (Paths.home.appendingPathComponent(".petdex/pets", isDirectory: true), "petdex"),
        (Paths.home.appendingPathComponent(".codex/pets", isDirectory: true), "codex"),
    ]

    private static var lastSignature: String?
    private static var cached: [PetEntry] = []

    /// Discover all installable pets. Cached: rebuilds only when the pet
    /// directories actually change (cheap signature check), so repeated calls —
    /// e.g. the menu re-scanning on every open — are nearly free.
    static func discover() -> [PetEntry] {
        let sig = signature()
        if sig == lastSignature, !cached.isEmpty { return cached }
        cached = build()
        lastSignature = sig
        return cached
    }

    /// Like `discover()` but returns entries only when they changed since the
    /// last call — lets callers skip republishing an unchanged catalog.
    static func discoverIfChanged() -> [PetEntry]? {
        let sig = signature()
        if sig == lastSignature, !cached.isEmpty { return nil }
        cached = build()
        lastSignature = sig
        return cached
    }

    /// A cheap fingerprint of the pet directories: each pet folder's name +
    /// modification time. Changes when a pet is added, removed, or updated —
    /// without reading or decoding any spritesheet.
    private static func signature() -> String {
        let fm = FileManager.default
        var parts: [String] = []
        for (base, source) in petDirs {
            guard let kids = try? fm.contentsOfDirectory(
                at: base, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for child in kids.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let m = (try? child.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate)?.timeIntervalSince1970 ?? 0
                parts.append("\(source)/\(child.lastPathComponent):\(Int(m))")
            }
        }
        return parts.joined(separator: "|")
    }

    private static func build() -> [PetEntry] {
        var entries: [PetEntry] = []
        var seen = Set<String>()

        for (base, source) in petDirs {
            guard let kids = try? FileManager.default.contentsOfDirectory(
                at: base, includingPropertiesForKeys: nil) else { continue }
            for child in kids.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                else { continue }
                // De-dupe by slug, not by source: Petdex installs into both
                // ~/.petdex/pets and ~/.codex/pets, so the same pet would
                // otherwise surface twice. First source listed wins.
                let slug = child.lastPathComponent
                if seen.contains(slug) { continue }
                let key = "\(source):\(slug)"

                // Prefer a real spritesheet; otherwise treat as a vector manifest.
                if let atlas = SpriteAtlas(directory: child) {
                    seen.insert(slug)
                    entries.append(PetEntry(key: key, title: atlas.manifest.displayName,
                                            atlas: atlas, species: nil,
                                            baseColor: .gray, source: source))
                } else if let m = loadManifest(child) {
                    seen.insert(slug)
                    let species = PetSpecies.from(m.form ?? "blob")
                    let color = m.color.flatMap(Color.init(hex:)) ?? species.identityColor
                    entries.append(PetEntry(key: key, title: m.displayName,
                                            atlas: nil, species: species,
                                            baseColor: color, source: source))
                }
            }
        }

        // Built-in vector forms — always present.
        for s in PetSpecies.allCases {
            entries.append(PetEntry(key: "built-in:\(s.rawValue)", title: s.title,
                                    atlas: nil, species: s,
                                    baseColor: s.identityColor, source: "built-in"))
        }
        return entries
    }

    private static func loadManifest(_ dir: URL) -> PetManifest? {
        let url = dir.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PetManifest.self, from: data)
    }

    /// Resolve the configured key, falling back to the first built-in.
    static func resolve(_ key: String, in entries: [PetEntry]) -> PetEntry {
        entries.first { $0.key == key }
            ?? entries.first { $0.species == .blob && $0.source == "built-in" }
            ?? entries[0]
    }
}

extension Color {
    /// Parse "#rrggbb" / "rrggbb".
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self = Color(red: Double((v >> 16) & 0xff) / 255,
                     green: Double((v >> 8) & 0xff) / 255,
                     blue: Double(v & 0xff) / 255)
    }
}
