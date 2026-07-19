// BlackjackLocalizedStrings.swift
// =====================================================================
// A localizer backed by the SHIPPED it.lproj file on disk.
//
// Under `swift test` there is no app bundle, so `uiLocalized` falls back to
// returning the key. That is fine for logic tests, but it makes any
// measurement of what the player HEARS worthless — it would be measuring the
// length of identifiers. So the load measurement renders through the real
// Italian strings, read straight off disk, the same way `PhoneticsTests`
// reads them.

import Foundation

enum BlackjackLocalizedStrings {

    /// key → format string, parsed from the shipped Italian file.
    static let italian: [String: String] = load()

    /// A `Localizer` that renders the real Italian text.
    static func localizer() -> (String, [CVarArg]) -> String {
        { key, args in
            guard let format = italian[key] else { return key }
            return args.isEmpty ? format : String(format: format, arguments: args)
        }
    }

    private static func load() -> [String: String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let url = root.appendingPathComponent("Resources/it.lproj/Localizable.strings")
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [:] }

        var result: [String: String] = [:]
        let pattern = #""([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let range = NSRange(contents.startIndex..., in: contents)
        for match in regex.matches(in: contents, range: range) {
            guard let k = Range(match.range(at: 1), in: contents),
                  let v = Range(match.range(at: 2), in: contents) else { continue }
            result[String(contents[k])] = String(contents[v])
        }
        return result
    }
}
