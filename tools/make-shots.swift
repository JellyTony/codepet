// Renders promo images for the README from the app's own SwiftUI views (with
// sample data — no real sessions). Outputs docs/hero.png, docs/cards.png,
// docs/states.png.  Run:  xcrun swift tools/make-shots.swift <repo-root>
import SwiftUI
import AppKit

private let demoNow = 1_782_000_000.0

private func mk(_ id: String, _ state: PetActivity, project cwd: String, _ title: String,
                detail: String? = nil, summary: String? = nil, tools: Int = 0,
                startedAgo: Double = 0) -> Session {
    // termProgram nil → the inline reply TextField (which won't render in an
    // offscreen ImageRenderer) stays hidden for these stills.
    Session(sessionId: id, state: state, detail: detail, cwd: cwd, prompt: title,
            title: title, summary: summary, lastTool: nil, recentTools: nil,
            toolCount: tools, startedAt: demoNow - startedAgo, updatedAt: demoNow,
            transcriptPath: nil, termProgram: nil, termSession: nil)
}

private struct PetSnap: View {
    let activity: PetActivity; var t: Double; var species: PetSpecies = .blob
    var body: some View {
        Canvas { ctx, size in
            VectorPet.draw(ctx: &ctx, size: size, t: t, activity: activity,
                           species: species, baseColor: species.identityColor, gaze: .zero)
        }
    }
}

@MainActor private func save<V: View>(_ view: V, _ path: String) {
    let r = ImageRenderer(content: view)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("✗ render failed: \(path)"); return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("✓ \(path)  \(Int(img.size.width))×\(Int(img.size.height))")
}

@main enum Shots {
    @MainActor static func main() {
        L.language = .en   // English promo images
        let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
                                                   : FileManager.default.currentDirectoryPath
        let docs = (root as NSString).appendingPathComponent("docs")
        try? FileManager.default.createDirectory(atPath: docs, withIntermediateDirectories: true)
        func out(_ n: String) -> String { (docs as NSString).appendingPathComponent(n) }

        let sessions = [
            mk("a", .running, project: "/Users/you/code/codepet", "Add inline quick-reply to cards",
               detail: "Edit: SessionsPanel.swift", tools: 42, startedAgo: 184),
            mk("b", .waiting, project: "/Users/you/code/api", "Approve the database migration plan?",
               detail: "needs your confirmation", tools: 9, startedAgo: 95),
            mk("c", .ready, project: "/Users/you/code/web", "Fix the OAuth redirect bug",
               summary: "All tests pass — the redirect now keeps the return URL. Ready for review.",
               tools: 31, startedAgo: 320),
        ]
        let bg = LinearGradient(colors: [Color(red: 0.95, green: 0.96, blue: 1.0),
                                         Color(red: 0.87, green: 0.97, blue: 0.97)],
                                startPoint: .topLeading, endPoint: .bottomTrailing)

        let cardStack = VStack(spacing: 9) {
            ForEach(sessions) { s in SessionCard(session: s, now: demoNow) }
        }
        .frame(width: SessionsView.cardWidth)
        .padding(.horizontal, 18).padding(.top, 16)

        let hero = ZStack {
            bg
            VStack(spacing: 0) {
                cardStack
                PetSnap(activity: .running, t: 3.2).frame(width: 150, height: 140)
            }
            .padding(34)
        }
        .frame(width: 680, height: 720)

        let states: [(PetActivity, String, Double)] = [
            (.running, "working…", 3.2), (.waiting, "needs you", 0.5),
            (.ready, "ready", 0.9), (.failed, "failed", 0.4), (.idle, "idle", 0.6),
        ]
        let statesRow = HStack(spacing: 4) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, s in
                VStack(spacing: 2) {
                    PetSnap(activity: s.0, t: s.2).frame(width: 118, height: 110)
                    Text(s.1).font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.62))
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
        .background(bg)
        .frame(width: 660, height: 180)

        let cardsOnly = cardStack.padding(.bottom, 16).background(bg).frame(width: 304)

        let forms = PetSpecies.allCases.map { ($0, PetSpecies.displayName[$0] ?? $0.rawValue) }
        let formsRow = HStack(spacing: 6) {
            ForEach(Array(forms.enumerated()), id: \.offset) { _, f in
                VStack(spacing: 2) {
                    PetSnap(activity: .idle, t: 3.0, species: f.0).frame(width: 120, height: 116)
                    Text(f.1).font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.62))
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(bg)
        .frame(width: 900, height: 178)

        save(hero, out("hero.png"))
        save(statesRow, out("states.png"))
        save(cardsOnly, out("cards.png"))
        save(formsRow, out("forms.png"))
    }
}
