#!/usr/bin/env python3
"""Download OpenMoji 618x618 PNGs for words that have a clear visual emoji."""
import os, json, urllib.request, urllib.error

BASE = "https://raw.githubusercontent.com/hfg-gmuend/openmoji/master/color/618x618"
OUT  = "Sources/Assets.xcassets/WordImages"

# word → emoji (pick the most child-friendly, unambiguous image)
WORDS = {
    # 2-letter
    "go": "🚦", "hi": "👋", "me": "🙋",
    "no": "🚫", "up": "⬆️", "we": "👥",
    # 3-letter
    "ant": "🐜", "ape": "🦍", "arm": "💪", "art": "🎨",
    "bag": "👜", "bat": "🦇", "bed": "🛏️", "box": "📦",
    "boy": "👦", "bug": "🐛", "bus": "🚌",
    "cap": "🧢", "car": "🚗", "cat": "🐱", "cow": "🐄",
    "cup": "☕", "cut": "✂️",
    "day": "☀️", "dig": "⛏️", "dog": "🐶",
    "ear": "👂", "eat": "🍴", "egg": "🥚", "eye": "👁️",
    "fan": "🌀", "fly": "🪰", "fog": "🌫️", "fox": "🦊", "fun": "🎉",
    "hat": "🎩", "hay": "🌾", "hen": "🐔", "hop": "🐰",
    "hot": "🌶️", "hug": "🤗",
    "ice": "🧊",
    "jam": "🍓", "jet": "✈️", "joy": "😊",
    "key": "🗝️", "kid": "🧒",
    "lip": "👄", "log": "🪵",
    "mad": "😠", "man": "👨", "map": "🗺️", "mom": "👩", "mug": "☕",
    "nap": "😴", "net": "🥅", "new": "✨",
    "nut": "🥜",
    "oak": "🌳",
    "pan": "🍳", "paw": "🐾", "pen": "🖊️", "pie": "🥧",
    "pig": "🐷", "pin": "📌", "pot": "🫕",
    "ran": "🏃", "rat": "🐀", "red": "🔴", "rod": "🎣", "row": "🚣", "run": "🏃",
    "sad": "😢", "saw": "🪚", "say": "💬", "sea": "🌊",
    "sip": "🧃", "six": "6️⃣", "sky": "🌤️", "sob": "😭",
    "son": "👦", "sub": "🥖", "sun": "☀️",
    "can": "🥫", "dot": "🔴",
    "hut": "🛖",
    "jar": "🫙", "jaw": "🦷", "jug": "🍶",
    "kit": "🧰",
    "leg": "🦵", "lid": "🫙",
    "pad": "📝", "pea": "🫛", "pop": "🍾",
    "rib": "🍖",
    "toe": "🦶", "tug": "🛥️",
    "zip": "🤐",
    "tap": "🚿", "ten": "🔟", "tie": "👔", "tin": "🥫",
    "toy": "🧸", "tub": "🛁", "two": "2️⃣",
    "van": "🚐",
    "web": "🕸️", "wed": "💍", "wet": "💧", "win": "🏆", "won": "🥇", "wow": "🤩",
    "yam": "🍠", "yes": "✅",
    "zap": "⚡", "zoo": "🦁",
}

def emoji_to_openmoji_name(emoji: str) -> str:
    """Convert emoji string to OpenMoji filename (e.g. '1F431.png')."""
    codepoints = [f"{ord(c):04X}" for c in emoji]
    return "-".join(codepoints) + ".png"

def try_download(url: str, dest: str) -> bool:
    try:
        urllib.request.urlretrieve(url, dest)
        # Sanity check: real PNG starts with \x89PNG
        with open(dest, "rb") as f:
            header = f.read(4)
        if header != b"\x89PNG":
            os.remove(dest)
            return False
        return True
    except Exception:
        return False

os.makedirs(OUT, exist_ok=True)
ok, fail = [], []

for word, emoji in sorted(WORDS.items()):
    iset_dir = f"{OUT}/{word}.imageset"
    os.makedirs(iset_dir, exist_ok=True)
    dest = f"{iset_dir}/{word}.png"

    # Try full sequence (with variation selectors), then without FE0F
    name_full = emoji_to_openmoji_name(emoji)
    name_no_vs = "-".join(f"{ord(c):04X}" for c in emoji if ord(c) != 0xFE0F) + ".png"

    success = False
    for name in dict.fromkeys([name_full, name_no_vs]):  # deduplicate, preserve order
        if try_download(f"{BASE}/{name}", dest):
            success = True
            break

    if success:
        # Declare at @3x so the 618px image maps to ~206pt logical size
        contents = {
            "images": [
                {"idiom": "universal", "scale": "1x"},
                {"idiom": "universal", "scale": "2x"},
                {"idiom": "universal", "scale": "3x", "filename": f"{word}.png"},
            ],
            "info": {"author": "xcode", "version": 1},
        }
        with open(f"{iset_dir}/Contents.json", "w") as f:
            json.dump(contents, f, indent=2)
        ok.append(word)
        print(f"  ✓  {word:6s}  {emoji}  →  {name_full}")
    else:
        os.rmdir(iset_dir)
        fail.append(word)
        print(f"  ✗  {word:6s}  {emoji}  →  NOT FOUND")

print(f"\n{'='*40}")
print(f"Downloaded: {len(ok)}   Failed: {len(fail)}")
if fail:
    print(f"Missing:    {', '.join(fail)}")
