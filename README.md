# Splat That Moji (◕‿◕)

A kaomoji picker for macOS, in the spirit of [Splatmoji](https://github.com/cspeterson/splatmoji):
hit a hotkey, type a few letters, press Return, and the kaomoji lands in whatever app you were
typing in.

- **94,562 kaomoji**, merged and de-duplicated from five open datasets, with English keywords
  (plus romaji) and 39 browse categories.
- **Fast search**: tag-word prefixes, synonyms (`glad` finds *happy*, `kitten` finds *cat*), typo
  tolerance (`hapyy`), and searching inside the kaomoji itself (`ω`, `ツ`, `^_^`, `┻━┻`). All
  words must match; popular classics rank first; your favorites and frequently used kaomoji float up.
- **Three insert modes** (like Splatmoji's `copypaste` / `type` / `copy`): paste and then
  restore your clipboard, type the characters directly, or just copy.
- Recents, favorites, Markdown escaping (so `¯\_(ツ)_/¯` keeps its arm in Discord and GitHub),
  your own kaomoji in Splatmoji-format TSV files, launch at login, and a menu bar item.

## Install

Needs macOS 14+ and Xcode (or the Swift toolchain).

```sh
scripts/build_app.sh --install   # builds, signs, copies to /Applications, launches
```

The first time you insert a kaomoji, macOS asks for **Accessibility** access (System Settings →
Privacy & Security → Accessibility). Paste and Type modes need it to send keystrokes. Without it,
the kaomoji is still copied so you can ⌘V it yourself.

The script signs with your Apple Development certificate if you have one, so the permission
survives rebuilds. With ad-hoc signing you'd have to re-grant it after every build.

## Using it

Press **⌃⌘K** (change it in Settings; the system emoji picker is ⌃⌘Space). Then:

| Key | Action |
| --- | --- |
| type | search |
| ← → ↑ ↓, PgUp/PgDn | move the selection |
| ↩ | insert (default mode) |
| ⌘↩ | copy only |
| ⌥↩ | insert Markdown-escaped |
| ⌘1 … ⌘9 | insert the 1st to 9th result |
| ⌘D | add or remove from favorites |
| ⇥ / ⇧⇥ | next / previous category |
| ⎋ | clear the search, then close |
| ⌘, | settings |

Click a kaomoji to insert it. Right-click for more options. The menu bar item (ツ) has your
recent and favorite kaomoji one click away.

From a terminal: `"/Applications/Splat That Moji.app/Contents/MacOS/SplatThatMoji" --search table flip`

### Your own kaomoji

Settings → Library → **Open Custom Folder** (`~/Library/Application Support/Splat That Moji/`).
Every `.tsv` file there is merged in, one kaomoji per line, in Splatmoji's format:

```
(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧<TAB>sparkles, magic, my favorite
```

Lines starting with `# ` are comments. Custom kaomoji lead search results and get their own **Mine**
category.

## The database

`tools/build_db.py` builds `Resources/kaomoji.tsv` and `Resources/kaomoji-meta.json` from these sources:

| Source | License | Notes |
| --- | --- | --- |
| [`tools/curated.tsv`](tools/curated.tsv) | MIT | About 110 classics with the names people search for ("look of disapproval", "finger guns", "deal with it") |
| [w33ble/emoticon-data](https://github.com/w33ble/emoticon-data) | MIT | The set Splatmoji and rofimoji ship (1.5k, English tags) |
| [iansinnott/asciilib](https://github.com/iansinnott/asciilib) | MIT | Named ASCII faces |
| [kaomojiya-collection/kaomoji-collection](https://github.com/kaomojiya-collection/kaomoji-collection) | MIT | 41k kaomoji in 535 Japanese categories, each given English keywords in [`tools/kaomojiya_categories.tsv`](tools/kaomojiya_categories.tsv) |
| [ekohrt/emoticon_kaomoji_dataset](https://github.com/ekohrt/emoticon_kaomoji_dataset) | **none stated** | 62k scraped from public kaomoji sites, with hand-labelled tags |

The build:
- decodes HTML entities and strips invisible characters;
- drops multi-line art, bare emoji, emoji spam, and Western `:-)` emoticons;
- de-duplicates by Unicode normalization;
- adds synonym tags;
- assigns browse categories;
- scores popularity by how many sources contain each kaomoji.

Sources are pinned to commits and cached in `.cache/`.

```sh
python3 tools/build_db.py --stats   # rebuild the database and print category sizes
swift test                          # search-quality tests against the real database
```

> The ekohrt dataset has no license file. That's fine for personal use, but if you plan to
> distribute the app, check with its author or remove that source from `SOURCES` in
> `tools/build_db.py` and rebuild.

## Layout

```
Sources/KaomojiKit/      database loading + search engine (no AppKit; unit-tested)
Sources/SplatThatMoji/   menu bar app: hotkey, picker panel, insertion, settings
tools/                   database build pipeline and keyword tables
scripts/                 app bundle build and icon generator
Resources/               generated database, Info.plist, icon
```
