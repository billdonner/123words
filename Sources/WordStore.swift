import Foundation
import UIKit

class WordStore: ObservableObject {
    static let words: [String] = [
        // 1-character
        "a", "I",
        // 2-character
        "an", "as", "at", "be", "do", "go", "he", "hi",
        "if", "in", "is", "it", "me", "my", "no", "of",
        "on", "or", "so", "to", "up", "us", "we",
        // 3-character
        "all", "and", "ant", "ape", "are", "arm", "art", "axe",
        "bad", "bag", "bat", "bed", "bee", "big", "bin", "bit", "box",
        "boy", "bug", "bun", "bus", "but",
        "cab", "can", "cap", "car", "cat", "cod", "cot", "cow", "cub", "cup", "cut",
        "dam", "day", "den", "did", "dig", "dog", "dot",
        "ear", "eat", "eel", "egg", "elm", "emu", "end", "eye",
        "fan", "far", "fat", "few", "fig", "fly", "fog", "for", "fox", "fun",
        "gel", "get", "got", "gum", "gym",
        "had", "ham", "has", "hat", "hay", "hen", "her", "him", "his",
        "hop", "hot", "how", "hug", "hut",
        "ice", "ivy",
        "jam", "jar", "jaw", "jay", "jet", "joy", "jug",
        "key", "kid", "kit",
        "lab", "lap", "leg", "lei", "let", "lid", "lip", "log", "lot", "low",
        "mad", "man", "map", "mat", "men", "met", "mom", "mop", "mud", "mug",
        "nap", "net", "new", "now", "nut",
        "oak", "oar", "oat", "old", "one", "our", "out", "owl", "own",
        "pad", "pan", "pat", "paw", "pea", "pen", "pet", "pie", "pig", "pin", "pit", "pop",
        "pot", "pun", "put",
        "ram", "ran", "rat", "raw", "red", "rib", "rid", "rim", "rip", "rob", "rod", "row",
        "rub", "rug", "run", "rut", "rye",
        "sad", "sap", "sat", "saw", "say", "sea", "set", "she", "sin", "sip",
        "sir", "sit", "six", "ski", "sky", "sob", "son", "sub", "sum", "sun",
        "tab", "tan", "tap", "tar", "tax", "tea", "ten", "the", "tie", "tin", "tip", "toe", "too",
        "top", "toy", "try", "tub", "tug", "two",
        "urn", "use",
        "van", "vat", "vow",
        "war", "was", "web", "wed", "wet", "who", "why", "wig", "win", "wit", "won", "wow",
        "yak", "yam", "yes", "yet", "yew", "you", "zap", "zip", "zoo"
    ]

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
            let idx = Int.random(in: 0..<pool.count)
            self.currentIndex = idx
            self.currentWord = pool[idx]
            self.lastIndex = idx
        }
    }

    func nextWord() {
        let pool = activeWords
        if isRandomMode {
            var newIdx: Int
            repeat { newIdx = Int.random(in: 0..<pool.count) }
            while newIdx == lastIndex && pool.count > 1
            currentIndex = newIdx
        } else {
            currentIndex = (currentIndex + 1) % pool.count
        }
        lastIndex = currentIndex
        currentWord = pool[currentIndex]
    }

    func previousWord() {
        let pool = activeWords
        if isRandomMode {
            nextWord()
        } else {
            currentIndex = (currentIndex - 1 + pool.count) % pool.count
            lastIndex = currentIndex
            currentWord = pool[currentIndex]
        }
    }

    private func resetToValidWord() {
        let pool = activeWords
        if !pool.contains(currentWord) {
            let idx = Int.random(in: 0..<pool.count)
            currentIndex = idx
            lastIndex = idx
            currentWord = pool[idx]
        } else if let idx = pool.firstIndex(of: currentWord) {
            currentIndex = idx
            lastIndex = idx
        }
    }
}
