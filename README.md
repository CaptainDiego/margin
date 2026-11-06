# Margin

A tiny native Markdown writing app for macOS, modeled on
[Omawrite](https://github.com/omacom/omawrite) (MIT): one centered page in IBM
Plex Mono, plain Markdown on disk, live styling, and markers (`**`, `_`, `~~`,
`[](…)`) that only show around the caret. Follows system light/dark.

## Build & install

```sh
./bin/build     # → build/Margin.app
./bin/install   # → ~/Applications/Margin.app, registered as the default for .md
```

Open from a terminal with `open -a Margin file.md`.

## Behaviour

- Files with a name autosave ~1s after you stop typing. Untitled drafts wait for
  ⌘S (macOS keeps them safe across quits anyway).
- If git or another editor changes the file and you have no unsaved edits, it
  reloads. If you do, macOS warns before you overwrite.
- Paste is always plain text. No auto-bullets, no smart quotes.
- Footer: file name, saved state, last-modified time · word count.

## Shortcuts

| | |
|---|---|
| ⌘N / ⌘O / ⌘S | New, open, save |
| ⇧⌘S / ⌥⇧⌘S | Duplicate, save as |
| ⌘B / ⌘I / ⇧⌘X | Toggle bold, italic, strikethrough |
| ⌘K | Insert link |
| ⌘-click | Open link |
| ⌘F / ⌥⌘F / ⌘G | Find, find & replace, next match |
| ⌘= / ⌘- / ⌘0 | Text size |
| ⌃⌘F | Full screen |
| ⌘P | Print |

## Code

- `Sources/Margin/Highlighter.swift`: incremental Markdown styling plus the
  TextKit 1 glyph hider that makes markers take no space.
- `Editor.swift`: the text view, centered 65-character column, footer.
- `Document.swift`: NSDocument (load/save, autosave, external reloads).
- `Theme.swift`: Omawrite's colours and type.

Debug: `MARGIN_SNAPSHOT=/tmp/x.png build/Margin.app/Contents/MacOS/Margin file.md`
renders the editor to a PNG (`MARGIN_LIGHT`, `MARGIN_CARET=<offset>`,
`MARGIN_TYPE=<text>` adjust it).

IBM Plex Mono is bundled under the SIL Open Font License 1.1 (`Resources/Fonts/OFL.txt`).

The bundled fonts are subset to Latin, punctuation, arrows, math and box
drawing (`pyftsubset`); anything else falls back to the system font.
