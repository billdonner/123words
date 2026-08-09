import Foundation
import UIKit

/// A word plus the two facts that decide how it should be taught.
///
/// `tier` sequences the list instead of leaving it shuffled:
///   1 — core CVC, high-frequency, concrete, imageable. The default pool.
///   2 — the wider regular set, introduced once tier 1 is mastered.
///   3 — "heart words": irregular spellings (`the`, `two`, `eye`, `who`).
///       These must be learned whole. Sounding out `eye` as e-y-e teaches
///       an active falsehood, so nothing may ever ask a child to decode
///       them — hence `decodable`.
struct WordEntry {
    let text: String
    let tier: Int
    var decodable: Bool { tier != 3 }
}

/// Per-word mastery, persisted across launches.
///
/// Turning a decoded word into an instantly-recognised sight word takes
/// on the order of 4–14 *successful encounters with that same word*,
/// spread over time. The app used to sample uniformly from ~200 words,
/// excluding only the immediately-previous one, so the expected gap
/// between repeats was about 200 items — a five-minute session would
/// essentially never show a word twice. Pleasant exposure, but nothing
/// that builds reading.
///
/// This is a three-box Leitner scheduler over a small active set.
final class WordProgress {
    static let shared = WordProgress()

    /// Words in flight at any one time. Small on purpose: a child needs
    /// to keep meeting the same handful until they stick.
    static let activeSetSize = 12

    private static let boxKey = "wordBoxes"
    private static let seenKey = "wordSeenCounts"

    private var boxes: [String: Int]
    private var seen: [String: Int]

    private init() {
        boxes = UserDefaults.standard.dictionary(forKey: Self.boxKey) as? [String: Int] ?? [:]
        seen  = UserDefaults.standard.dictionary(forKey: Self.seenKey) as? [String: Int] ?? [:]
    }

    private func persist() {
        UserDefaults.standard.set(boxes, forKey: Self.boxKey)
        UserDefaults.standard.set(seen, forKey: Self.seenKey)
    }

    func box(_ word: String) -> Int { boxes[word] ?? 1 }
    func isMastered(_ word: String) -> Bool { box(word) >= 3 }
    func timesSeen(_ word: String) -> Int { seen[word] ?? 0 }

    var masteredCount: Int { boxes.values.filter { $0 >= 3 }.count }

    func recordExposure(_ word: String) {
        seen[word, default: 0] += 1
        persist()
    }

    /// Promote on a correct answer; three correct answers masters a word.
    func recordCorrect(_ word: String) {
        boxes[word] = min(3, box(word) + 1)
        seen[word, default: 0] += 1
        persist()
    }

    /// Any miss drops the word straight back to the learning box.
    func recordMiss(_ word: String) {
        boxes[word] = 1
        persist()
    }

    func reset() {
        boxes = [:]
        seen = [:]
        persist()
    }

    /// The next word to show, drawn from `pool` (already filtered for
    /// pictures/length by the caller). `pool` must be in teaching order —
    /// the active set is simply its first unmastered `activeSetSize`
    /// entries, so a new word is only introduced when an earlier one is
    /// promoted out.
    func scheduledWord(from pool: [String], excluding: String? = nil) -> String {
        guard !pool.isEmpty else { return "cat" }

        let unmastered = pool.filter { !isMastered($0) }
        let mastered   = pool.filter { isMastered($0) }
        let active     = Array(unmastered.prefix(Self.activeSetSize))

        // Mastered words still resurface occasionally so they don't rot.
        var candidates: [String]
        if !mastered.isEmpty, !active.isEmpty, Int.random(in: 0..<100) < 15 {
            candidates = mastered
        } else if !active.isEmpty {
            candidates = active
        } else {
            candidates = mastered.isEmpty ? pool : mastered
        }

        if candidates.count > 1, let excluding {
            candidates.removeAll { $0 == excluding }
        }
        guard !candidates.isEmpty else { return pool.randomElement() ?? "cat" }

        // Inside the active set, box 1 (still being learned) is drawn
        // twice as often as box 2.
        let weighted = candidates.flatMap { word -> [String] in
            Array(repeating: word, count: box(word) == 1 ? 2 : 1)
        }
        return weighted.randomElement() ?? candidates[0]
    }
}

class WordStore: ObservableObject {

    /// Words removed from the original list, and why:
    ///   • off-tone for a grandkids app — war, sin, tax, rob
    ///   • outside a 3–6 receptive vocabulary, so the picture can't
    ///     confirm the decode and the word→picture loop breaks —
    ///     cod, cot, elm, emu, urn, oar, vat, rut, sap, tar, wit, pun,
    ///     gel, lei, yew, rye, dam
    static let entries: [WordEntry] = {
        // Tier 1 — the starting pool. Concrete, high-frequency, CVC,
        // and every one of them has a picture.
        let tier1 = ["cat","dog","pig","sun","bus","hat","bed","cup","box","net",
                     "pen","bag","jar","mug","van","fox","hen","bat","pot","cow",
                     "bug","car","cap","fan","hut","log","map","mom","nut","pan",
                     "pin","rat","sub","tub","web","zip","egg","leg","lip","top"]

        // Tier 3 — heart words. Irregular; learned whole, never decoded.
        let tier3 = ["a","I","be","do","go","he","hi","me","my","no","of","or","so",
                     "to","us","we","the","she","who","why","you","are","was","two",
                     "one","eye","ice","ape","sky","day","saw","pie","few","new",
                     "sea","tea","toe","low","row","own","old","out","our","now",
                     "how","boy","joy","toy","say","jay","hay","key","try","rye",
                     "ski","yes","use","eat","ear","oak","oat","owl","art","are"]

        let cut: Set<String> = ["war","sin","tax","rob","cod","cot","elm","emu",
                                "urn","oar","vat","rut","sap","tar","wit","pun",
                                "gel","lei","yew","rye","dam"]

        let all = [
            "a", "I",
            "an", "as", "at", "be", "do", "go", "he", "hi",
            "if", "in", "is", "it", "me", "my", "no", "of",
            "on", "or", "so", "to", "up", "us", "we",
            "all", "and", "ant", "ape", "are", "arm", "art", "axe",
            "bad", "bag", "bat", "bed", "bee", "big", "bin", "bit", "box",
            "boy", "bug", "bun", "bus", "but",
            "cab", "can", "cap", "car", "cat", "cow", "cub", "cup", "cut",
            "day", "den", "did", "dig", "dog", "dot",
            "ear", "eat", "eel", "egg", "end", "eye",
            "fan", "far", "fat", "few", "fig", "fly", "fog", "for", "fox", "fun",
            "get", "got", "gum", "gym",
            "had", "ham", "has", "hat", "hay", "hen", "her", "him", "his",
            "hop", "hot", "how", "hug", "hut",
            "ice", "ivy",
            "jam", "jar", "jaw", "jay", "jet", "joy", "jug",
            "key", "kid", "kit",
            "lab", "lap", "leg", "let", "lid", "lip", "log", "lot", "low",
            "mad", "man", "map", "mat", "men", "met", "mom", "mop", "mud", "mug",
            "nap", "net", "new", "now", "nut",
            "oak", "oat", "old", "one", "our", "out", "owl", "own",
            "pad", "pan", "pat", "paw", "pea", "pen", "pet", "pie", "pig", "pin",
            "pit", "pop", "pot", "put",
            "ram", "ran", "rat", "raw", "red", "rib", "rid", "rim", "rip", "rod",
            "row", "rub", "rug", "run",
            "sad", "sat", "saw", "say", "sea", "set", "she", "sip",
            "sir", "sit", "six", "ski", "sky", "sob", "son", "sub", "sum", "sun",
            "tan", "tap", "tea", "ten", "the", "tie", "tin", "tip", "toe", "too",
            "top", "toy", "try", "tub", "tug", "two",
            "use",
            "van", "vow",
            "was", "web", "wed", "wet", "who", "why", "wig", "win", "won", "wow",
            "yak", "yam", "yes", "yet", "you", "zap", "zip", "zoo"
        ]

        let t1 = Set(tier1), t3 = Set(tier3)
        let kept = all.filter { !cut.contains($0) }
        func tier(_ w: String) -> Int { t1.contains(w) ? 1 : (t3.contains(w) ? 3 : 2) }

        // Teaching order: tier 1, then tier 2, then heart words. Built by
        // bucketing rather than `sorted(by:)` — Swift's sort is not
        // guaranteed stable, and the scheduler takes the active set as
        // "the first N unmastered words in this array", so an order that
        // shuffled between launches would quietly change which words a
        // child is working on.
        return (1...3).flatMap { t in
            kept.filter { tier($0) == t }.map { WordEntry(text: $0, tier: t) }
        }
    }()

    /// In teaching order (tier 1 → 2 → 3), which is what the Leitner
    /// scheduler relies on to introduce words gradually.
    static let words: [String] = entries.map(\.text)

    /// Alphabetical, for the parent-facing gallery and the sequential
    /// reading mode.
    static let wordsAlphabetical: [String] = words.sorted()

    static let decodableWords: Set<String> =
        Set(entries.filter(\.decodable).map(\.text))

    // Computed once at startup — words that have a bundled image asset
    static let wordsWithImages: [String] = words.filter { UIImage(named: $0) != nil }

    @Published var onlyWordsWithImages: Bool {
        didSet {
            UserDefaults.standard.set(onlyWordsWithImages, forKey: "onlyWordsWithImages")
            resetToValidWord()
        }
    }

    @Published var currentWord: String
    @Published var currentIndex: Int = 0
    @Published var isRandomMode: Bool = true

    private var lastIndex: Int = -1

    var activeWords: [String] {
        let pool = onlyWordsWithImages ? Self.wordsWithImages : Self.words
        return pool.isEmpty ? Self.words : pool
    }

    init() {
        // Default true — only show words with pictures
        let filterImages = UserDefaults.standard.object(forKey: "onlyWordsWithImages") as? Bool ?? true
        self.onlyWordsWithImages = filterImages

        let pool = filterImages && !Self.wordsWithImages.isEmpty ? Self.wordsWithImages : Self.words

        if let w = UserDefaults.standard.string(forKey: "screenshotWord"),
           let idx = pool.firstIndex(of: w) {
            self.currentIndex = idx
            self.currentWord = w
            self.lastIndex = idx
        } else {
            let w = WordProgress.shared.scheduledWord(from: pool)
            self.currentWord = w
            self.currentIndex = pool.firstIndex(of: w) ?? 0
            self.lastIndex = self.currentIndex
        }
        WordProgress.shared.recordExposure(self.currentWord)
    }

    func nextWord() {
        let pool = activeWords
        if isRandomMode {
            // Scheduled rather than uniformly random — see WordProgress.
            currentWord = WordProgress.shared.scheduledWord(from: pool, excluding: currentWord)
            currentIndex = pool.firstIndex(of: currentWord) ?? currentIndex
        } else {
            currentIndex = (currentIndex + 1) % pool.count
            currentWord = pool[currentIndex]
        }
        lastIndex = currentIndex
        WordProgress.shared.recordExposure(currentWord)
    }

    func previousWord() {
        let pool = activeWords
        if isRandomMode {
            nextWord()
        } else {
            currentIndex = (currentIndex - 1 + pool.count) % pool.count
            lastIndex = currentIndex
            currentWord = pool[currentIndex]
            WordProgress.shared.recordExposure(currentWord)
        }
    }

    private func resetToValidWord() {
        let pool = activeWords
        if !pool.contains(currentWord) {
            currentWord = WordProgress.shared.scheduledWord(from: pool)
            currentIndex = pool.firstIndex(of: currentWord) ?? 0
            lastIndex = currentIndex
        } else if let idx = pool.firstIndex(of: currentWord) {
            currentIndex = idx
            lastIndex = idx
        }
    }
}
