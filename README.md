# Margin

A tiny native Markdown editor for macOS, inspired by
[Omawrite](https://github.com/omacom/omawrite).

One centered page in IBM Plex Mono. Plain Markdown on disk, styled as you type.
Markers like `**`, `_`, `~~` and `[](…)` hide until your cursor is on them.
Light, dark, or follow the system (View → Appearance). Autosaves, and reloads when git or another editor
changes the file.

**~530 KB.** No dependencies, no network, no permission prompts.

## Install

**Download:** get `Margin.dmg` from
[Releases](https://github.com/CaptainDiego/margin/releases/latest), open it and
drag Margin into Applications. Margin isn't notarized, so on first launch macOS
blocks it. Go to System Settings → Privacy & Security and click **Open Anyway**.
To make it your Markdown app, choose Margin → Make Margin the Default for Markdown.

**From source** (macOS 14+, Xcode command line tools):

```sh
git clone https://github.com/CaptainDiego/margin && cd margin
./bin/install   # builds, copies to ~/Applications, makes it the default for .md
```

## Benchmark

Cold open of a file (app not running) until its window is on screen, Apple
Silicon, median of 6–8 runs:

| File | Margin | Sublime Text 4 |
|---|---|---|
| 15 KB note | 335 ms | 351 ms |
| 1 MB file | 376 ms | 378 ms |
| App size | 0.5 MB | 112 MB |

## Local only

- App Sandbox with no network entitlement: macOS blocks every connection.
- Reads and writes only the files you open or save yourself.
- ⌘-click opens `http`, `https` and `mailto` links only.
- No telemetry, analytics, updates or accounts.

## Shortcuts

⌘B / ⌘I / ⇧⌘X bold, italic, strikethrough · ⌘K link · ⌘F find ·
⌘= / ⌘- text size · ⌃⌘F full screen · ⌘P print

## License

MIT. IBM Plex Mono is bundled under the SIL Open Font License 1.1, subset to
Latin, punctuation and symbols.
