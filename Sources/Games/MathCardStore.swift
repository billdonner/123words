import Foundation

struct MathCard: Codable {
    let kind: String       // "add" or "sub"
    let q: String          // "1 + 3 = ?\n🔵 🔴🔴🔴"
    let a: String          // "1 + 3 = 4\n🔵🔴🔴🔴"
}

enum MathCardStore {
    static let all: [MathCard] = {
        guard let url = Bundle.main.url(forResource: "math_cards", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let cards = try? JSONDecoder().decode([MathCard].self, from: data)
        else { return [] }
        return cards
    }()

    static func filtered(allowAdd: Bool, allowSub: Bool) -> [MathCard] {
        let allow: [String] = {
            switch (allowAdd, allowSub) {
            case (true, true):   return ["add", "sub"]
            case (true, false):  return ["add"]
            case (false, true):  return ["sub"]
            case (false, false): return ["add", "sub"]  // fall back, never empty
            }
        }()
        return all.filter { allow.contains($0.kind) }
    }

    // Parse "1 + 3 = 4\n…" → 4
    static func answerNumber(from card: MathCard) -> Int? {
        let firstLine = card.a.split(separator: "\n", maxSplits: 1).first ?? Substring(card.a)
        if let eq = firstLine.range(of: "=") {
            let after = firstLine[eq.upperBound...].trimmingCharacters(in: .whitespaces)
            return Int(after)
        }
        return nil
    }

    // Spoken form: "1 + 3 = ?" → "one plus three"
    static func spokenPrompt(from card: MathCard) -> String {
        let firstLine = String(card.q.split(separator: "\n").first ?? "")
        // Drop the "= ?"
        let lhs = firstLine.replacingOccurrences(of: "= ?", with: "")
            .replacingOccurrences(of: "=?", with: "")
            .trimmingCharacters(in: .whitespaces)
        return lhs
            .replacingOccurrences(of: "+", with: " plus ")
            .replacingOccurrences(of: "-", with: " minus ")
            .replacingOccurrences(of: "  ", with: " ")
    }
}
