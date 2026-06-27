import AppKit
import SwiftUI

/// Generates the README promo images by rendering the **real** SwiftUI views
/// (SessionCard / CardBackground / VectorPet) onto a clean gradient — so the
/// docs always match the actual UI, pixel for pixel. Run with:
///
///   CODEPET_DOCSHOT=1 ./build/CodePet.app/Contents/MacOS/CodePet
///
/// (from the repo root, so `docs/` resolves). The app short-circuits to this
/// before any window setup and writes docs/hero.png, then exits.
enum DocShot {
    @MainActor
    static func renderAll() {
        L.language = .en   // promo images read in English
        let docs = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs")
        renderHero(to: docs.appendingPathComponent("hero.png"))
    }

    @MainActor
    private static func renderHero(to url: URL) {
        let now = 1_700_000_000.0
        let sessions = [
            mock(cwd: "/Users/dev/codepet", state: .running,
                 title: "Add inline quick-reply to cards",
                 detail: "Edit: SessionsPanel.swift", summary: nil,
                 tools: 42, startedAgo: 180),
            mock(cwd: "/Users/dev/api", state: .waiting,
                 title: "Approve the database migration plan?",
                 detail: nil, summary: "needs your confirmation",
                 tools: 9, startedAgo: 60),
            mock(cwd: "/Users/dev/web", state: .ready,
                 title: "Fix the OAuth redirect bug", detail: nil,
                 summary: "All tests pass — the redirect now keeps the return URL. Ready for review.",
                 tools: 31, startedAgo: 300),
        ]
        save(HeroShot(sessions: sessions, now: now), scale: 2, to: url)
    }

    /// A throwaway Session for the mockup. ProjectResolver turns the cwd's last
    /// component into the project chip ("codepet" / "api" / "web").
    private static func mock(cwd: String, state: PetActivity, title: String,
                             detail: String?, summary: String?,
                             tools: Int, startedAgo: Double) -> Session {
        let now = 1_700_000_000.0
        return Session(
            sessionId: UUID().uuidString, state: state, detail: detail, cwd: cwd,
            prompt: nil, title: title, summary: summary, lastTool: nil,
            recentTools: nil, toolCount: tools, startedAt: now - startedAgo,
            updatedAt: now, transcriptPath: nil, termProgram: nil, termSession: nil)
    }

    @MainActor
    private static func save<V: View>(_ view: V, scale: CGFloat, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = true
        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write(Data("docshot: render failed\n".utf8)); return
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        do {
            try data.write(to: url)
            print("✓ \(url.path)  (\(cg.width)×\(cg.height))")
        } catch {
            FileHandle.standardError.write(Data("docshot: write failed: \(error)\n".utf8))
        }
    }
}

/// The hero shot: the white task-card stack floating above the corner pet, on a
/// soft pastel gradient — the same layout the app draws, composed for the README.
private struct HeroShot: View {
    let sessions: [Session]
    let now: Double

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.914, green: 0.933, blue: 0.992),
                    Color(red: 0.866, green: 0.960, blue: 0.972)]),
                startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(spacing: 26) {
                VStack(spacing: 10) {
                    ForEach(sessions) { session in
                        SessionCard(session: session, now: now)
                    }
                }
                .frame(width: SessionsView.cardWidth)

                Canvas { ctx, size in
                    VectorPet.draw(ctx: &ctx, size: size, t: 0.0, activity: .running,
                                   species: .blob, baseColor: PetSpecies.blob.identityColor,
                                   gaze: .zero)
                }
                .frame(width: 132, height: 138)
            }
            .padding(.horizontal, 26)
        }
        .frame(width: 480, height: 680)
    }
}
