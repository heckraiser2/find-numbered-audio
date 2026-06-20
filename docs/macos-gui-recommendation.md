# macOS GUI recommendation (find-numbered-audio)

Saved for future implementation. Full context from planning discussion (June 2026).

## Verdict

**Build a small SwiftUI macOS app that wraps the existing zsh script** — do not reimplement parsing/rename logic in Swift. Target audiobook/OpenAudible users who need folder pick, preview, and confirm-before-apply.

## Architecture

```
SwiftUI app (folder picker, preview table, Apply/Cancel)
        │
        ▼  Process: /bin/zsh find-numbered-audio.zsh …
find-numbered-audio.zsh  ← source of truth; keep tested logic here
```

**First script change for GUI:** add machine-readable output:

```bash
find-numbered-audio.zsh --json-report [dir]
find-numbered-audio.zsh --json-rename [dir]   # planned renames only (dry run)
find-numbered-audio.zsh --rename --apply [dir]  # unchanged
```

## MVP (v1)

1. **Home** — Choose folder (or drag-and-drop); one-line value prop
2. **Scan results** — Series grouped with track numbers `[01]`, `[02]`, …
3. **Rename preview** — Current → New table; M3U change note; **Apply** / **Cancel**
4. **Done** — Summary + Reveal in Finder

## UX rules

- Default = preview only (same as `--rename` without `--apply`)
- Apply always requires explicit confirmation
- Never rename without showing full planned list
- Disable Apply when `No renames planned`
- Show stderr in a collapsible Details panel on failure

## Technology

| Option | Use |
|--------|-----|
| **SwiftUI + bundled script** | Recommended — real app, App Store or direct download |
| Platypus / thin wrapper | Quick personal MVP only |
| Automator / Shortcuts | Too limited for preview UI |
| Rewrite in Swift | Avoid — duplicates 97 tests |

Bundle script at `MyApp.app/Contents/Resources/find-numbered-audio.zsh`. Invoke via `Process` with quoted paths.

## macOS gotchas

- Folder access via `NSOpenPanel` (sandbox-friendly)
- Bundle script + invoke `/bin/zsh` explicitly
- Version bundled engine in About (e.g. Engine v1.0.0)
- Document Full Disk Access only if truly needed

## Roadmap

1. **Phase 1** — `--json-report` / `--json-rename` in zsh script
2. **Phase 2** — SwiftUI MVP (picker, preview, apply)
3. **Phase 3** — Drag-and-drop, help panel (OpenAudible workflow), Sparkle updates
4. **Phase 4** — Finder Quick Action / Services menu (optional)

## Naming & distribution

- App name ideas: *Numbered Audio*, *Audiobook Renumber*
- MIT license; link to https://github.com/heckraiser2/find-numbered-audio
- Monorepo option: `mac/` folder in same repo

## Do not

- Port parsing rules to Swift
- Ship v1 without dry-run preview
- Hide failures from the user
