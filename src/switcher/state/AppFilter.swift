import Foundation

struct AppFilterChoice: Equatable {
    var pid: pid_t
    var title: String
}

enum AppFilterRow: Equatable {
    case all
    case app(AppFilterChoice)

    var pid: pid_t? {
        switch self {
        case .all: return nil
        case .app(let choice): return choice.pid
        }
    }
}

/// Which app the switcher's app picker is narrowed to, and the rows that picker shows.
/// A nil selection matches every window. Text search is a separate filter and combines with this one.
enum AppFilter {
    static func matches(windowPid: pid_t, selectedPid: pid_t?) -> Bool {
        guard let selectedPid else { return true }
        return windowPid == selectedPid
    }

    /// One row per pid, sorted by name. A repeated name gets a " (2)" suffix so a popup can tell the
    /// rows apart by title.
    static func choices(_ apps: [(pid: pid_t, name: String)], unnamed: String = "App") -> [AppFilterChoice] {
        var seen = Set<pid_t>()
        var unique = [AppFilterChoice]()
        for app in apps {
            guard seen.insert(app.pid).inserted else { continue }
            let trimmed = app.name.trimmingCharacters(in: .whitespacesAndNewlines)
            unique.append(AppFilterChoice(pid: app.pid, title: trimmed.isEmpty ? unnamed : trimmed))
        }
        unique.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        var used = Set<String>()
        return unique.map { AppFilterChoice(pid: $0.pid, title: uniqueTitle($0.title, used: &used)) }
    }

    static func resolvedSelection(_ selected: pid_t?, choices: [AppFilterChoice]) -> pid_t? {
        guard let selected else { return nil }
        return choices.contains { $0.pid == selected } ? selected : nil
    }

    /// Empty query lists every app, with All first. A query keeps the rows whose names contain it,
    /// and All only when its own title matches.
    static func rows(choices: [AppFilterChoice], query: String, allTitle: String) -> [AppFilterRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let apps = trimmed.isEmpty ? choices : choices.filter { matchesName($0.title, trimmed) }
        var rows = apps.map { AppFilterRow.app($0) }
        if trimmed.isEmpty || matchesName(allTitle, trimmed) { rows.insert(.all, at: 0) }
        return rows
    }

    static func matchesName(_ name: String, _ query: String) -> Bool {
        name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: .current) != nil
    }

    private static func uniqueTitle(_ name: String, used: inout Set<String>) -> String {
        if used.insert(name).inserted { return name }
        var n = 2
        while true {
            let candidate = "\(name) (\(n))"
            if used.insert(candidate).inserted { return candidate }
            n += 1
        }
    }
}
