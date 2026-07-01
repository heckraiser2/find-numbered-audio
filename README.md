# find-numbered-audio

[![Tests](https://github.com/heckraiser2/find-numbered-audio/actions/workflows/test.yml/badge.svg)](https://github.com/heckraiser2/find-numbered-audio/actions/workflows/test.yml)

**Rename numbered audiobook chapters and audio tracks to sortable, zero-padded filenames** — a zsh CLI for macOS and Linux.

Finds sequentially numbered audio in a directory tree, reports series (Arabic or Roman), and optionally renames files so the track number is a prefix at the front. Designed for audiobook workflows, especially [OpenAudible](https://openaudible.org/) chapter joins.

## What it does

- Detects **begin**, **end**, and **both** edge numerals (`01 Title.mp3`, `Song 1.wav`, `2001 A Space Odyssey - 01.mp3`)
- Groups **shared title prefix/suffix** albums (`20th Century Ghosts … 01.mp3`)
- Synthesizes order from **Part / Chapter / Section** labels when there is no edge track number
- Renames **single-audio folders** (one `.m4b` or chapter file per directory)
- Updates **`.m3u` playlists** when files are renamed
- Dry-run by default; `--apply` performs renames

## Examples

| Before | After (`--rename --apply`) |
|--------|----------------------------|
| `Song 1.wav` | `01 Song.wav` |
| `Chapter III.flac` | `III Chapter.flac` |
| `2001 A Space Odyssey - 01.mp3` | `01 2001 A Space Odyssey.mp3` |
| `20th Century Ghosts - Intro 01.mp3` | `01 20th Century Ghosts - Intro.mp3` |
| `01 title - 012345678.mp3` | *(no change — already correct)* |

```bash
# See what would change
./find-numbered-audio.zsh --rename ~/Audiobooks/MyBook

# Apply renames + update playlists
./find-numbered-audio.zsh --rename --apply ~/Audiobooks/MyBook
```

## Requirements

- zsh 5.8+
- Standard Unix tools: `find`, `sort`, `mv`, `grep`

## Install

```bash
git clone https://github.com/heckraiser2/find-numbered-audio.git
cd find-numbered-audio
chmod +x find-numbered-audio.zsh find-numbered-audio-test.zsh
```

Or copy `find-numbered-audio.zsh` anywhere on your `PATH`.

**Stable release:** see [Releases](https://github.com/heckraiser2/find-numbered-audio/releases) for tagged versions.

## Usage

```bash
# Report numbered series under a directory
./find-numbered-audio.zsh [directory]

# Dry-run renames
./find-numbered-audio.zsh --rename [directory]

# Apply renames (also updates .m3u playlists in the tree)
./find-numbered-audio.zsh --rename --apply [directory]
```

## Rename rules

- **Arabic numerals** → zero-padded prefix (minimum 2 digits; wider when the series requires it)
- **Roman numerals** → canonical prefix with no leading zeros (`I`, `II`, `IV`, …)
- **End numerals** (`Song 1.wav`) → moved to front (`01 Song.wav`)
- **Structure-only** (Part/Chapter/Section labels, no edge track number) → synthetic global sequence
- **Single-audio folders** → lone parseable files are still eligible
- **Shared title prefix/suffix** → end-primary tracks grouped (e.g. `20th Century Ghosts … 01.mp3`)
- **Catalog numbers** → long or mismatched begin/end values kept in the title (e.g. `2001 A Space Odyssey - 01.mp3`, `01 title - 012345678.mp3`)
- **Global track + Chapter/Question** → leading track index kept; trailing structure kept in title (e.g. `08 Katha Upanishad_ Chapter 1.m4b`, `52 Prasna Upanishad_ Question 1.m4b` — no renames when already correct)

## Tests

```bash
./find-numbered-audio-test.zsh
```

On Linux, if zsh is not `/bin/zsh`:

```bash
ZSH=/usr/bin/zsh ./find-numbered-audio-test.zsh
```

CI runs the full suite on Ubuntu and macOS on every push.

## OpenAudible

[OpenAudible’s “Join Audio Files”](https://openaudible.org/docs) command joins files in **plain alphabetical (lexicographic) order by full filename**. It does not parse track numbers or prefer numerals at the beginning vs end of the name — whatever makes the entire string sort A→Z is what determines join order. Unpadded names like `Song 1.mp3` … `Song 10.mp3` sort as 1, 10, 11, 2 (the docs warn that `Chapter 11` sorts before `Chapter 2` for the same reason).

After `--rename --apply`, this tool moves the track index to a **zero-padded leading prefix** (`01 Title.mp3`, `02 Title.mp3`, …), which is the most reliable layout for OpenAudible join. Put **one book per directory** and verify order with:

```bash
ls -1 /path/to/book | sort
```

Dry-run and report output include an **OpenAudible join preview**: lexicographic sort vs intended track order, plus a recommendation on whether `--apply` is needed before joining.

## Keywords

audiobook · audiobooks · numbered chapters · batch rename · file renaming · zsh · shell script · CLI · mp3 · m4b · OpenAudible · Roman numerals · playlist m3u · macOS · Linux

## License

[MIT](LICENSE)
