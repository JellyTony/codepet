import Foundation

/// One pet listed in the Petdex gallery (petdex.crafter.run).
struct PetdexPet {
    let slug: String            // friendly slug, e.g. "boba", "aurelion-sol"
    let displayName: String     // human label, e.g. "Aurelion Sol"
    let spritesheetURL: URL     // the 8×9 sheet on assets.petdex.dev
}

/// In-app client for the Petdex gallery: lists pets and installs them natively,
/// with **no terminal, no npx, no extra tooling**. Installing writes the same
/// `pet.json` + `spritesheet.webp` layout `petdex install` produces, into
/// `~/.petdex/pets/<slug>/`, which `PetCatalog` discovers automatically.
///
/// Why scrape the gallery page rather than call an API: the resolve endpoint is
/// gated behind the CLI's auth flow, but every pet's spritesheet is public on
/// `assets.petdex.dev`. The gallery page embeds those URLs, and each hashed
/// asset slug is `<friendly-slug>-<12 hex>`, so one fetch yields the whole
/// featured list plus a direct, dependency-free download URL per pet.
enum PetdexGallery {
    static let pageURL = URL(string: "https://petdex.crafter.run/zh")!
    private static let assetHost = "https://assets.petdex.dev"

    /// Fetch the featured pets shown on the gallery home page.
    static func fetchFeatured(completion: @escaping ([PetdexPet]) -> Void) {
        var req = URLRequest(url: pageURL)
        req.setValue("Mozilla/5.0 (Macintosh) CodePet", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let pets = data.flatMap { String(data: $0, encoding: .utf8) }.map(parse) ?? []
            DispatchQueue.main.async { completion(pets) }
        }.resume()
    }

    /// Resolve a single pet by its friendly slug (e.g. "naiwa") via its gallery
    /// page `/zh/pets/<slug>`, which embeds the public spritesheet URL. Lets the
    /// user install **any** pet by name, not just the featured ones. Completion
    /// runs on the main thread; nil means the slug wasn't found.
    static func resolve(slug: String, completion: @escaping (PetdexPet?) -> Void) {
        let clean = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty,
              let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://petdex.crafter.run/zh/pets/\(encoded)") else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh) CodePet", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let pets = data.flatMap { String(data: $0, encoding: .utf8) }.map(parse) ?? []
            let pet = pets.first { $0.slug == clean } ?? pets.first
            DispatchQueue.main.async { completion(pet) }
        }.resume()
    }

    /// Extract `{slug, displayName, spritesheetURL}` from gallery HTML by reading
    /// the public `…/pets/<friendly>-<hash>/sprite.webp` asset URLs.
    static func parse(_ html: String) -> [PetdexPet] {
        // Hashed asset slug = friendly slug + "-" + 12 hex chars.
        let pattern = #"assets\.petdex\.dev/pets/([a-z0-9][a-z0-9-]*-[0-9a-f]{12})/sprite\.webp"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = html as NSString
        var seen = Set<String>()
        var pets: [PetdexPet] = []
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let hashed = ns.substring(with: m.range(at: 1))
            // Strip the trailing "-<12 hex>" to recover the friendly slug.
            let friendly = hashed.replacingOccurrences(
                of: #"-[0-9a-f]{12}$"#, with: "", options: .regularExpression)
            guard !friendly.isEmpty, !seen.contains(friendly) else { continue }
            seen.insert(friendly)
            guard let url = URL(string: "\(assetHost)/pets/\(hashed)/sprite.webp") else { continue }
            pets.append(PetdexPet(slug: friendly, displayName: prettyName(friendly), spritesheetURL: url))
        }
        return pets.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    /// "aurelion-sol" → "Aurelion Sol", "02" → "02".
    static func prettyName(_ slug: String) -> String {
        slug.split(separator: "-")
            .map { $0.count <= 1 ? String($0) : $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Download `pet.spritesheetURL` and write the pet into `~/.petdex/pets/<slug>/`
    /// (pet.json + spritesheet.webp). Completion runs on the main thread; the
    /// success value is the selection key, e.g. "petdex:boba".
    static func install(_ pet: PetdexPet, completion: @escaping (Result<String, Error>) -> Void) {
        var req = URLRequest(url: pet.spritesheetURL)
        req.setValue("Mozilla/5.0 (Macintosh) CodePet", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 30
        URLSession.shared.dataTask(with: req) { data, response, error in
            let finish: (Result<String, Error>) -> Void = { r in
                DispatchQueue.main.async { completion(r) }
            }
            if let error = error { return finish(.failure(error)) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = data, data.count > 1024 else {
                return finish(.failure(installError("Download failed for \(pet.slug)")))
            }
            do {
                let dir = Paths.home
                    .appendingPathComponent(".petdex/pets/\(pet.slug)", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: dir.appendingPathComponent("spritesheet.webp"))
                let manifest: [String: String] = [
                    "id": pet.slug,
                    "displayName": pet.displayName,
                    "spritesheetPath": "spritesheet.webp",
                ]
                let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted])
                try json.write(to: dir.appendingPathComponent("pet.json"))
                finish(.success("petdex:\(pet.slug)"))
            } catch {
                finish(.failure(error))
            }
        }.resume()
    }

    private static func installError(_ message: String) -> NSError {
        NSError(domain: "CodePet.Petdex", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
