# find-numbered-audio

[![Tests](https://github.com/heckraiser2/find-numbered-audio/actions/workflows/test.yml/badge.svg)](https://github.com/heckraiser2/find-numbered-audio/actions/workflows/test.yml)

Zsh script to find sequentially numbered audio files (audiobook chapters, album tracks, etc.) and optionally rename them so the track number is a zero-padded prefix at the front of the filename.

## Requirements

- zsh 5.8+
- Standard Unix tools: `find`, `sort`, `mv`, `grep`

## Install

```bash
git clone https://github.com/heckraiser2/find-numbered-audio.git
chmod +x find-numbered-audio.zsh find-numbered-audio-test.zsh
```

Or copy `find-numbered-audio.zsh` anywhere on your `PATH`.

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

## Tests

```bash
./find-numbered-audio-test.zsh
```

On Linux, if zsh is not `/bin/zsh`:

```bash
ZSH=/usr/bin/zsh ./find-numbered-audio-test.zsh
```

## OpenAudible

After `--rename --apply`, Arabic-numbered chapters sort correctly for OpenAudible’s “Join Audio Files” feature (`001 Title.mp3`, `002 Title.mp3`, …). Use one book per directory.
