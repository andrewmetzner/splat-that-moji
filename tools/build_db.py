#!/usr/bin/env python3
"""Build the bundled kaomoji database from several open kaomoji datasets.

    python3 tools/build_db.py            # fetch (cached) sources, write Resources/
    python3 tools/build_db.py --stats    # also print a quality report

Outputs
  Resources/kaomoji.tsv        one kaomoji per line:
                               <kaomoji> TAB <tag, tag, ...> TAB <category,ids> TAB <popularity>
                               (the first two columns are the same format Splatmoji uses)
  Resources/kaomoji-meta.json  sources, browse categories, and query synonyms

Sources are pinned to commits so a rebuild is reproducible. Downloads are cached in
.cache/sources/.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import unicodedata
import urllib.request
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Order matters: earlier sources are more curated, so their tags are listed first and
# their entries sort first among equally popular kaomoji.
SOURCES = [
    dict(
        key="curated",
        name="hand-picked classics (tools/curated.tsv)",
        repo=None,
        path="tools/curated.tsv",
        license="MIT",
        weight=6,
    ),
    dict(
        key="w33ble",
        name="emoticon-data (the set Splatmoji & rofimoji ship)",
        repo="w33ble/emoticon-data",
        commit="92b6211ec2a93e14052e0e572d697d4d06c71868",
        path="emoticons.json",
        license="MIT",
        weight=4,
    ),
    dict(
        key="asciilib",
        name="asciilib",
        repo="iansinnott/asciilib",
        commit="52b034b55a684251b4f0c4974d707b9de4d198f4",
        path="lib.json",
        license="MIT",
        weight=3,
    ),
    dict(
        key="kaomojiya",
        name="kaomoji-collection (kaomojiya.org)",
        repo="kaomojiya-collection/kaomoji-collection",
        commit="2ca1b394345a437bbec9e9b9445d1dd75ae3f7d4",
        path="kaomoji.json",
        license="MIT",
        weight=2,
    ),
    dict(
        key="ekohrt",
        name="emoticon_kaomoji_dataset",
        repo="ekohrt/emoticon_kaomoji_dataset",
        commit="7d00fbba249adc1770025bcca56c74b42ad69ac1",
        path="emoticon_dict.json",
        license="none stated (scraped from public kaomoji sites)",
        weight=2,
    ),
]

MAX_LEN = 60          # code points; longer entries are multi-line art or spam
MAX_TAGS = 32

# Tags that carry no meaning for search.
STOP_TAGS = {
    "popular", "most used", "other", "others", "misc", "miscellaneous", "japanese",
    "kaomoji", "emoticon", "emoticons", "text faces", "text face", "unassigned", "new",
    "random", "face", "faces", "emoji", "symbols and other", "various", "people",
    "objects", "nature", "uncategorized", "special", "classic",
}

# ekohrt's hand-labelled tags use underscores and a few compound names.
EKOHRT_TAG_FIX = {
    "hello_message": ["hello"],
    "goodbye_message": ["goodbye"],
    "thanks_message": ["thanks"],
    "morning_night_evening_message": ["good morning", "good night"],
    "salute_wave": ["salute", "wave"],
    "bats_vampires": ["bat", "vampire"],
    "table_flip": ["table flip"],
    "table_upright": ["table unflip", "put table back"],
    "lying_down": ["lying down"],
    "ping_pong": ["ping pong"],
    "middle finger": ["middle finger"],
}

# Synonym groups: the first word is the canonical tag. Entries tagged with any member get
# the canonical tag added at build time; the app maps query words to canonicals too, so
# searching "glad" finds everything tagged "joy" or "happy".
SYNONYMS = [
    ["happy", "joy", "joyful", "glad", "delighted", "cheerful", "yay", "happiness", "elated"],
    ["laugh", "laughing", "lol", "lmao", "haha", "rofl", "giggle", "giggling", "chuckle", "cackle", "laughter"],
    ["cry", "crying", "tears", "sob", "sobbing", "weep", "weeping", "teary", "bawling", "wailing", "cries"],
    ["sad", "unhappy", "depressed", "sorrow", "gloomy", "dejected", "sadness", "melancholy", "downcast", "crestfallen"],
    ["angry", "anger", "mad", "rage", "furious", "fuming", "pissed", "irate", "enraged"],
    ["annoyed", "irritated", "irked", "annoying", "frustrated", "irritating"],
    ["love", "loving", "in love", "adore", "lovestruck", "smitten", "infatuated"],
    ["heart", "hearts"],
    ["kiss", "kissing", "smooch", "kisses", "kissy"],
    ["cute", "kawaii", "adorable", "cutie"],
    ["surprised", "surprise", "shock", "shocked", "astonished", "amazed", "gasp", "omg", "startled"],
    ["scared", "afraid", "fear", "frightened", "terrified", "scary", "horror", "spooked"],
    ["nervous", "anxious", "worried", "uneasy", "sweating", "sweat", "anxiety"],
    ["confused", "puzzled", "perplexed", "bewildered", "huh", "question", "confusion"],
    ["tired", "exhausted", "sleepy", "drowsy", "weary", "worn out", "fatigue"],
    ["sleep", "sleeping", "asleep", "zzz", "nap", "napping", "snore", "snoring"],
    ["shy", "blush", "blushing", "embarrassed", "bashful", "flustered", "timid"],
    ["smug", "smirk", "smirking", "proud", "sly", "pride"],
    ["hello", "hi", "hey", "greeting", "greetings", "howdy", "hiya", "yo"],
    ["bye", "goodbye", "farewell", "see you", "cya", "sayonara", "later"],
    ["wave", "waving"],
    ["thanks", "thank you", "thx", "grateful", "gratitude", "arigato", "arigatou", "thankful"],
    ["sorry", "apologize", "apology", "apologies", "my bad", "apologetic"],
    ["please", "beg", "begging", "plead", "pleading"],
    ["hug", "hugs", "hugging", "cuddle", "cuddling", "embrace", "snuggle"],
    ["dance", "dancing", "dancer", "groove"],
    ["music", "song", "sing", "singing", "karaoke", "singer"],
    ["run", "running", "runner", "dash", "sprint", "flee", "fleeing"],
    ["fight", "fighting", "punch", "punching", "attack", "kick", "kicking", "beat up", "brawl", "violence", "boxing"],
    ["strong", "flex", "flexing", "muscles", "muscle", "buff", "power", "strength"],
    ["dead", "death", "die", "dying", "rip", "deceased", "died"],
    ["cat", "cats", "kitty", "kitten", "kitties", "neko", "meow", "nya", "nyaa", "kitteh"],
    ["dog", "dogs", "puppy", "doggy", "doggo", "pup", "inu", "woof", "doggie", "puppies"],
    ["bear", "bears", "kuma", "teddy", "teddy bear"],
    ["rabbit", "bunny", "bunnies", "usagi", "rabbits"],
    ["bird", "birds", "birdie", "tori"],
    ["pig", "piggy", "buta", "oink", "pigs"],
    ["food", "eat", "eating", "meal", "hungry", "yummy", "delicious", "tasty", "munching", "nom"],
    ["drink", "drinking", "cheers", "toast", "beer", "booze", "drinks"],
    ["coffee", "cafe", "latte"],
    ["shrug", "whatever", "idk", "dunno", "shrugging"],
    ["unimpressed", "meh", "bored", "disapproval", "disapprove", "deadpan", "not amused"],
    ["tableflip", "table flip", "flip table", "flipping table", "flip the table", "chabudaigaeshi", "flipping tables"],
    ["wink", "winking"],
    ["excited", "exciting", "hype", "hyped", "thrilled", "eager", "pumped", "excitement"],
    ["celebrate", "celebration", "party", "congratulations", "congrats", "hooray", "hurray", "woohoo", "partying"],
    ["evil", "devil", "devilish", "villain", "sinister", "wicked"],
    ["magic", "magical", "wizard", "witch", "wand", "spell"],
    ["sparkle", "sparkles", "sparkly", "glitter", "sparkling", "shiny"],
    ["sunglasses", "shades", "deal with it"],
    ["cool", "awesome"],
    ["lenny", "le lenny face", "lenny face"],
    ["donger", "dongers", "raise your dongers"],
    ["write", "writing", "note", "notes", "memo", "taking notes"],
    ["computer", "pc", "laptop", "typing", "keyboard"],
    ["money", "cash", "rich", "dollar", "dollars"],
    ["gun", "guns", "shoot", "shooting", "pistol", "rifle"],
    ["sword", "swords", "katana", "blade"],
    ["ghost", "spooky", "ghosts"],
    ["hide", "hiding", "hidden"],
    ["peek", "peeking", "peep", "peeping", "peekaboo", "glance"],
    ["think", "thinking", "ponder", "pondering", "hmm", "wonder", "wondering", "thoughtful"],
    ["point", "pointing"],
    ["thumbs up", "good job", "well done", "approve", "thumbsup"],
    ["ok", "okay"],
    ["yes", "yeah", "yep", "agree", "nodding"],
    ["no", "nope", "nah"],
    ["flower", "flowers", "blossom", "rose", "roses"],
    ["star", "stars", "starry"],
    ["rain", "rainy", "raining", "umbrella"],
    ["snow", "snowy", "snowing", "snowman"],
    ["sun", "sunny", "sunshine"],
    ["christmas", "xmas", "santa"],
    ["halloween", "pumpkin", "jack o lantern"],
    ["birthday", "bday", "happy birthday"],
    ["fish", "fishing", "fishy"],
    ["frog", "froggy", "toad"],
    ["monkey", "ape", "monkeys"],
    ["mouse", "mice", "rat"],
    ["sick", "ill", "unwell", "vomit", "puke", "throw up", "vomiting"],
    ["salute", "saluting"],
    ["clap", "clapping", "applause"],
    ["shout", "shouting", "yell", "yelling", "scream", "screaming"],
    ["creepy", "creep", "pervert", "pervy"],
]

# Browse categories shown as chips in the picker: (id, name, icon kaomoji, triggers).
# An entry joins a category when any trigger equals one of its tags or tag words.
CATEGORIES = [
    ("happy", "Happy", "(≧▽≦)", ["happy", "smile", "smiling", "grin", "fun", "upbeat", "cheerful", "relief", "glad"]),
    ("excited", "Excited", "ヽ(°〇°)ﾉ", ["excited", "hyper", "squee", "squeal", "kyaa", "yahoo", "wheee", "upbeat", "anticipation", "can't wait"]),
    ("love", "Love", "(♡˙︶˙♡)", ["love", "kiss", "crush", "valentine", "heart flutter", "lovey dovey", "couple", "flirting", "flirty", "affectionate", "heart shot", "romance", "romantic"]),
    ("cute", "Cute", "(◕‿◕✿)", ["cute", "fluffy", "dreamy", "sparkle eyes", "moe", "squishy", "tiny", "uwu", "owo"]),
    ("laugh", "Laughing", "(≧∇≦)ﾉ", ["laugh", "snicker", "pfft", "laugh hard", "tears of joy", "laughing while crying", "funny"]),
    ("smug", "Smug", "(￣ー￣)", ["smug", "lenny", "boastful", "scheming laugh", "satisfied grin", "creepy smile", "taunt", "mocking", "teasing"]),
    ("shy", "Shy", "(⁄ ⁄•⁄ω⁄•⁄ ⁄)", ["shy", "fidgeting", "coy", "embarrassed laugh"]),
    ("sad", "Sad", "(´；ω；`)", ["sad", "lonely", "disappointed", "sulking", "sulk", "pout", "pouting", "hurt", "heartbroken", "regret", "letdown", "dejected", "depressed", "down"]),
    ("cry", "Crying", "(╥﹏╥)", ["cry", "pleading", "about to cry", "teary eyes", "handkerchief", "burst into tears", "crying hard"]),
    ("angry", "Angry", "(╬ Ò﹏Ó)", ["angry", "annoyed", "grumpy", "hmph", "scowl", "frown", "menacing", "threaten", "glare", "furious", "huffy", "tsk"]),
    ("surprised", "Surprised", "Σ(°ロ°)", ["surprised", "wow", "dumbfounded", "mouth agape", "stunned", "what"]),
    ("scared", "Scared", "(((ﾟДﾟ;)))", ["scared", "nervous", "panic", "trembling", "shaking", "cowering", "help", "help me", "flustered", "danger"]),
    ("confused", "Confused", "(・・ ) ?", ["confused", "head tilt", "dizzy", "don't know", "don't understand", "question mark", "dazed"]),
    ("sleepy", "Sleepy", "(－_－) zzZ", ["tired", "sleep", "yawn", "good night", "bed", "futon", "lying down", "lazing around"]),
    ("meh", "Meh", "(￢_￢)", ["unimpressed", "stare", "straight face", "blank stare", "side eye", "exasperated", "can't be bothered", "dead inside", "faraway look", "disgust", "gross", "cringe", "sigh", "creeped out", "suspicious"]),
    ("shrug", "Shrug", "¯\\_(ツ)_/¯", ["shrug", "good grief"]),
    ("tableflip", "Table Flip", "(╯°□°)╯︵ ┻━┻", ["tableflip", "table unflip", "unflip", "put table back"]),
    ("greeting", "Hello & Bye", "(^_^)/", ["hello", "bye", "wave", "welcome back", "welcome home", "good morning", "good evening", "good night", "i'm home", "heading out", "nice to meet you", "see you"]),
    ("thanks", "Thanks & Sorry", "m(_ _)m", ["thanks", "sorry", "bow", "kowtow", "please", "pray", "thanks for the meal", "excuse me", "grovel"]),
    ("hug", "Hugs & Pats", "(づ｡◕‿‿◕｡)づ", ["hug", "nuzzle", "pat", "head pat", "there there", "good boy", "petting", "cling"]),
    ("celebrate", "Celebrate", "＼(＾▽＾)／", ["celebrate", "banzai", "birthday", "clap", "fireworks", "festival", "cheer", "cheerleading", "victory", "guts pose", "new year", "party popper", "high five", "success", "did it"]),
    ("dance", "Dance & Music", "┏(・o･)┛♪", ["dance", "music", "whistle", "whistling", "humming", "groove"]),
    ("run", "Running", "ε=ε=┌( >_<)┘", ["run", "walk", "walking", "fly", "flying", "zoom", "slide", "scurry", "rushing", "toddling", "trudging", "swoosh", "jump", "run away", "escape"]),
    ("fight", "Fighting", "(ง'̀-'́)ง", ["fight", "strong", "gun", "sword", "slap", "hit", "smack", "explosion", "beam", "laser", "shuriken", "weapon", "knife", "bomb", "archery", "ora ora", "beatdown", "threaten"]),
    ("dead", "Dead & Defeated", "(x_x)", ["dead", "defeated", "orz", "despair", "faint", "fall down", "grave", "dying", "it's over", "give up", "surrender", "melting", "disappear", "half dead", "near death", "faceplant"]),
    ("hide", "Hiding & Peeking", "|･ω･)", ["hide", "peek", "sneaky", "sneaking", "whisper", "secret", "wall", "looking around", "stealthy"]),
    ("think", "Thinking", "(￣～￣;)", ["think", "idea", "i see", "understood", "speech bubble", "thought bubble", "troubled", "uncertain", "deliberating", "search", "curious"]),
    ("gesture", "Gestures", "(☞ﾟヮﾟ)☞", ["point", "thumbs up", "ok", "peace", "peace sign", "v sign", "salute", "middle finger", "raise hand", "fist pump", "fist", "come here", "here you go", "give", "offer", "hand over", "hands up", "pointing and laughing", "beckon"]),
    ("food", "Food & Drink", "(っ˘ڡ˘ς)", ["food", "drink", "coffee", "tea", "drool", "ramen", "rice", "takoyaki", "cake", "fruit", "banana", "vegetable", "itadakimasu", "popcorn", "thanks for the meal", "chewing", "slurp", "gulp", "noodles", "pizza", "bread", "candy", "cookie"]),
    ("cat", "Cats", "(=^･ω･^=)", ["cat", "paw", "paw pads", "cat paw"]),
    ("dog", "Dogs", "U・ᴥ・U", ["dog"]),
    ("bear", "Bears", "ʕ•ᴥ•ʔ", ["bear", "panda", "koala"]),
    ("bunny", "Bunnies", "(/•ᴥ•\\)", ["rabbit"]),
    ("animals", "Animals", "(・θ・)", [
        "animal", "animals", "bird", "pig", "fish", "frog", "monkey", "mouse", "hamster", "seal",
        "fox", "crab", "octopus", "squid", "penguin", "duck", "chick", "horse", "sheep", "spider",
        "bug", "cockroach", "snake", "owl", "whale", "shark", "dolphin", "lion", "tiger", "tanuki",
        "raccoon dog", "jellyfish", "butterfly", "turtle", "cow", "eel", "axolotl", "flying squirrel",
        "seagull", "crow", "bat", "deer", "squirrel", "wolf", "dragon", "unicorn", "sloth", "otter",
        "bee", "ant", "snail", "worm", "crocodile", "alligator", "elephant", "giraffe", "camel",
        "goat", "chicken", "rooster", "hedgehog", "porcupine", "shisa", "gorilla", "baby bird", "lion dog",
    ]),
    ("magic", "Magic & Sparkles", "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧", ["magic", "star", "sparkle", "shooting star", "wish", "angel", "halo", "wings", "fairy", "gleam", "dazzling"]),
    ("evil", "Evil & Spooky", "ψ(｀∇´)ψ", ["evil", "ghost", "halloween", "zombie", "vampire", "curse", "cursed", "monster", "creepy", "evil laugh", "yandere", "demon", "ogre", "skull", "roar", "rawr", "evil face", "spooky"]),
    ("weather", "Weather & Seasons", "☀(ˊᗜˋ)", ["rain", "snow", "sun", "hot", "cold", "summer", "autumn", "spring", "winter", "christmas", "moon", "wind", "cherry blossom", "beach", "sea", "ocean", "freezing"]),
    ("work", "Work & Hobbies", "φ(．．)", ["write", "computer", "study", "phone", "camera", "letter", "book", "reading", "check", "clicking", "movie", "baseball", "sport", "soccer", "football", "basketball", "tennis", "chess", "game", "gaming", "camping", "laundry", "money", "bowling", "ping pong"]),
    ("characters", "Characters & Memes", "( ͡° ͜ʖ ͡°)", ["lenny", "donger", "character", "kirby", "doraemon", "anpanman", "baymax", "chiikawa", "my melody", "miffy", "pokemon", "meme", "homoo", "it's here", "columbia", "kenmomen", "eirin", "sanrio", "robot", "clown"]),
]

# --------------------------------------------------------------------------------------
# Text cleanup


def is_pictograph(cp: int) -> bool:
    return 0x1F000 <= cp <= 0x1FAFF


IGNORABLE = {0xFE0F, 0xFE0E, 0x200D, 0x20E3, 0x200B, 0x2060}
# Invisible characters that only cause duplicates: zero-width space, bidi controls, BOM.
STRIP_CHARS = set("​‎‏‪‫‬‭‮﻿⁦⁧⁨⁩")
WESTERN = re.compile(r"^[:;=8xXB%][\-o^'`]?[)(DPpOo3\]\[|/\\*>$<@{}]{1,2}$|^<3+$|^[)(\]\[DPpO|/\\][\-o^'`]?[:;=8]$")
# A sideways face anywhere in a short ASCII string: ",:-|", ">:(", "D:<".
SIDEWAYS = re.compile(r"[:;=8%][\-o^'`]?[)(\]\[|/\\DPpOo3*>$<@{}lLSs]|[)(\]\[|/\\DPp3*<>@{}][\-o^'`]?[:;=8]")


def visible_len(s: str) -> int:
    """Length ignoring combining marks, which some kaomoji stack by the dozen."""
    return sum(1 for ch in s if not unicodedata.combining(ch) and unicodedata.category(ch) not in ("Mn", "Me"))


def clean_kaomoji(raw: str) -> str | None:
    s = html.unescape(raw).replace("\t", " ")
    s = "".join(ch for ch in s if ch not in STRIP_CHARS)
    s = s.strip()
    if not s or "\n" in s or "\r" in s:
        return None  # multi-line ASCII art can't be typed into a single line
    if any(unicodedata.category(ch) == "Cc" for ch in s):
        return None
    if visible_len(s) > MAX_LEN:
        return None
    if s.isascii():
        compact = s.replace(" ", "")
        if WESTERN.match(compact):
            return None  # :) ;-P <3 and friends are emoticons, not kaomoji
        if len(compact) <= 6 and SIDEWAYS.search(compact) and not any(c in compact for c in "^_"):
            return None  # ...but keep (^_^;) and (;_;)

    emoji = 0
    core = 0
    for i, ch in enumerate(s):
        cp = ord(ch)
        if cp in IGNORABLE or 0xE0020 <= cp <= 0xE007F or ch.isspace():
            continue
        nxt = s[i + 1] if i + 1 < len(s) else ""
        if is_pictograph(cp) or (nxt == "\ufe0f" and cp >= 0x2000):
            emoji += 1
        else:
            core += 1
    if core < 2:
        return None  # a bare emoji (or emoji sequence), not a kaomoji
    if emoji and core < 3:
        return None  # an emoji in brackets, e.g. "(🤩)"
    if emoji >= 3 and emoji > core:
        return None  # mostly emoji: the AI-generated spam ekohrt's README warns about
    return s


def dedupe_key(s: str) -> str:
    return unicodedata.normalize("NFC", s)


TAG_JUNK = re.compile(r"#\s*\d+|[^\w\s'&+\-]", re.UNICODE)


def clean_tag(raw: str) -> str | None:
    t = html.unescape(raw).lower().replace("_", " ").replace("-", " ").replace("’", "'")
    t = TAG_JUNK.sub(" ", t)
    t = re.sub(r"\s+", " ", t).strip(" '&+")
    t = re.sub(r"(?<=[a-z]) \d+$", "", t)  # "angry 2", "in love 7": numbered section headers
    if not t or t in STOP_TAGS or t.isdigit() or len(t) > 48:
        return None
    if not t.isascii():
        return None  # the app searches with an English/romaji vocabulary
    return t


# --------------------------------------------------------------------------------------
# Loading


@dataclass
class Entry:
    text: str
    order: int
    tags: list[str] = field(default_factory=list)
    sources: set[str] = field(default_factory=set)
    bonus: int = 0

    def add_tags(self, tags):
        for t in tags:
            if t and t not in self.tags:
                self.tags.append(t)


class Collector:
    def __init__(self):
        self.entries: dict[str, Entry] = {}
        self.dropped = Counter()
        self.contributed = Counter()  # source -> entries it introduced

    def add(self, source: str, raw: str, tags, bonus: int = 0):
        text = clean_kaomoji(raw)
        if text is None:
            self.dropped[source] += 1
            return
        key = dedupe_key(text)
        entry = self.entries.get(key)
        if entry is None:
            entry = self.entries[key] = Entry(text=text, order=len(self.entries))
            self.contributed[source] += 1
        entry.sources.add(source)
        entry.bonus += bonus
        entry.add_tags(clean_tag(t) for t in tags)


def fetch(source: dict, cache: Path) -> Path:
    if source["repo"] is None:
        return ROOT / source["path"]
    dest = cache / f"{source['key']}-{source['commit'][:12]}-{Path(source['path']).name}"
    if not dest.exists():
        url = f"https://raw.githubusercontent.com/{source['repo']}/{source['commit']}/{source['path']}"
        print(f"  downloading {url}", file=sys.stderr)
        cache.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(url, timeout=120) as r:
            data = r.read()
        tmp = dest.with_suffix(".part")
        tmp.write_bytes(data)
        tmp.replace(dest)
    return dest


def load_w33ble(c: Collector, path: Path):
    for item in json.loads(path.read_text("utf-8"))["emoticons"]:
        c.add("w33ble", item["string"], item.get("tags", []))


def load_asciilib(c: Collector, path: Path):
    for item in json.loads(path.read_text("utf-8")).values():
        tags = [item.get("name", "")] + item.get("keywords", [])
        if item.get("category") not in (None, "UNASSIGNED"):
            tags.append(item["category"])
        c.add("asciilib", item["entry"], tags)


def load_kaomojiya(c: Collector, path: Path):
    english = {}
    for line in (ROOT / "tools" / "kaomojiya_categories.tsv").read_text("utf-8").splitlines():
        if line and not line.startswith("#"):
            slug, kws = line.split("\t")
            english[slug] = [k.strip() for k in kws.split(",") if k.strip()]
    data = json.loads(path.read_text("utf-8"))
    missing = sorted(set(data) - set(english))
    if missing:
        print(f"  warning: no English keywords for kaomojiya categories: {missing}", file=sys.stderr)
    for slug, items in data.items():
        tags = english.get(slug, []) + [slug.replace("-", " ")]
        for i, raw in enumerate(items):
            c.add("kaomojiya", raw, tags, bonus=1 if i < 12 else 0)


def load_ekohrt(c: Collector, path: Path):
    for raw, info in json.loads(path.read_text("utf-8")).items():
        orig = info.get("original_tags", [])
        tags = []
        for t in info.get("new_tags", []):
            tags.extend(EKOHRT_TAG_FIX.get(t, [t]))
        tags.extend(orig)
        popular = any(t.lower() in ("popular", "most used") for t in orig)
        c.add("ekohrt", raw, tags, bonus=3 if popular else 0)


def load_curated(c: Collector, path: Path):
    for line in path.read_text("utf-8").splitlines():
        if line and not line.startswith("# "):
            text, tags = line.split("\t")
            c.add("curated", text, tags.split(","))


LOADERS = {"curated": load_curated, "w33ble": load_w33ble, "asciilib": load_asciilib, "kaomojiya": load_kaomojiya, "ekohrt": load_ekohrt}

# --------------------------------------------------------------------------------------
# Enrichment


def build_synonym_map() -> dict[str, list[str]]:
    m: dict[str, list[str]] = defaultdict(list)
    for group in SYNONYMS:
        canon = group[0]
        for w in group[1:]:
            if canon not in m[w]:
                m[w].append(canon)
    return dict(m)


def words_of(tags) -> set[str]:
    out = set()
    for t in tags:
        out.add(t)
        out.update(t.split())
    return out


def enrich(entry: Entry, synonyms: dict[str, list[str]]):
    extra = []
    for term in words_of(entry.tags):
        for canon in synonyms.get(term, ()):
            if canon not in entry.tags and canon not in extra:
                extra.append(canon)
    entry.tags = entry.tags[:MAX_TAGS] + extra


def categorize(entry: Entry) -> list[str]:
    terms = words_of(entry.tags)
    return [cid for cid, _, _, triggers in CATEGORIES if any(t in terms for t in triggers)]


def popularity(entry: Entry, weights: dict[str, int]) -> int:
    score = sum(weights[s] for s in entry.sources) + entry.bonus
    n = len(entry.text)
    if n > 25:
        score -= 1
    if n > 40:
        score -= 2
    return max(0, min(score, 30))


# --------------------------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", type=Path, default=ROOT / ".cache" / "sources")
    ap.add_argument("--out", type=Path, default=ROOT / "Resources")
    ap.add_argument("--stats", action="store_true", help="print a quality report")
    args = ap.parse_args()

    collector = Collector()
    for src in SOURCES:
        path = fetch(src, args.cache)
        before = len(collector.entries)
        LOADERS[src["key"]](collector, path)
        print(f"  {src['key']:<10} +{len(collector.entries) - before:>6} new  "
              f"({collector.dropped[src['key']]} filtered)", file=sys.stderr)

    synonyms = build_synonym_map()
    weights = {s["key"]: s["weight"] for s in SOURCES}
    rows = []
    cat_counts = Counter()
    for e in collector.entries.values():
        enrich(e, synonyms)
        cats = categorize(e)
        cat_counts.update(cats)
        rows.append((popularity(e, weights), e, cats))
    rows.sort(key=lambda r: (-r[0], r[1].order))

    args.out.mkdir(parents=True, exist_ok=True)
    with open(args.out / "kaomoji.tsv", "w", encoding="utf-8", newline="\n") as f:
        for score, e, cats in rows:
            f.write(f"{e.text}\t{', '.join(e.tags)}\t{','.join(cats)}\t{score}\n")

    meta = {
        "version": 1,
        "generated": date.today().isoformat(),
        "count": len(rows),
        "sources": [
            {
                "name": s["name"],
                "url": f"https://github.com/{s['repo']}" if s["repo"] else "",
                "commit": s.get("commit", ""),
                "license": s["license"],
                "unique": collector.contributed[s["key"]],
            }
            for s in SOURCES
        ],
        "categories": [
            {"id": cid, "name": name, "icon": icon, "count": cat_counts[cid]}
            for cid, name, icon, _ in CATEGORIES
        ],
        "synonyms": synonyms,
    }
    (args.out / "kaomoji-meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n", "utf-8")

    untagged = sum(1 for _, e, _ in rows if not e.tags)
    uncategorized = sum(1 for _, _, c in rows if not c)
    print(f"wrote {len(rows)} kaomoji ({untagged} untagged, {uncategorized} outside browse categories)", file=sys.stderr)

    if args.stats:
        print("\ncategory sizes:", file=sys.stderr)
        for cid, name, _, _ in CATEGORIES:
            print(f"  {name:<20} {cat_counts[cid]:>6}", file=sys.stderr)
        print("\ntop 30:", " ".join(e.text for _, e, _ in rows[:30]), file=sys.stderr)


if __name__ == "__main__":
    main()
