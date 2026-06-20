#!/bin/zsh
#
# Automated tests for find-numbered-audio.zsh (macOS /bin/zsh).
#
# Usage: find-numbered-audio-test.zsh

emulate -L zsh

SCRIPT=${0:a:h}/find-numbered-audio.zsh
FIXTURES=${FIXTURES:-${HOME}/Downloads/test_data_for_scripts2/find-numbered-audio-fixtures}
ZSH=${ZSH:-/bin/zsh}

if [[ ! -f $SCRIPT ]]; then
  print -u2 "Missing script: $SCRIPT"
  exit 1
fi

typeset -i PASS=0 FAIL=0

assert_contains() {
  local desc=$1 needle=$2 haystack=$3
  if print -r -- "$haystack" | grep -Fq -- "$needle"; then
    print -r "  PASS: $desc"
    (( PASS++ ))
  else
    print -u2 "  FAIL: $desc"
    print -u2 "    need substring: $needle"
    (( FAIL++ ))
  fi
}

assert_not_contains() {
  local desc=$1 needle=$2 haystack=$3
  if print -r -- "$haystack" | grep -Fq -- "$needle"; then
    print -u2 "  FAIL: $desc (unexpected: $needle)"
    (( FAIL++ ))
  else
    print -r "  PASS: $desc"
    (( PASS++ ))
  fi
}

setup_fixtures() {
  rm -rf "$FIXTURES"
  mkdir -p "$FIXTURES"/{01-begin-arabic,02-end-arabic,03-end-roman,04-begin-roman,05-both-arabic,06-no-series,07-false-positive,08-gap,09-lost-symbol-part,10-inferno-sections,11-chapter-mid,12-chapter-credits,13-single-end,14-single-chapter,15-single-subdirs,16-lonely-in-multi,17-edge-spaces-begin,18-edge-spaces-end,19-inferno-spaced,20-shared-prefix,21-shared-suffix,22-shared-suffix-numeric,23-shared-prefix-year}

  for i in 1 2 3; do
    touch "$FIXTURES/01-begin-arabic/${i} Track.mp3"
  done

  touch "$FIXTURES/02-end-arabic/Song 1.wav" "$FIXTURES/02-end-arabic/Song 2.wav" "$FIXTURES/02-end-arabic/Song 3.wav"
  touch "$FIXTURES/03-end-roman/Chapter I.flac" "$FIXTURES/03-end-roman/Chapter II.flac" "$FIXTURES/03-end-roman/Chapter III.flac"
  touch "$FIXTURES/04-begin-roman/I - Intro.mp3" "$FIXTURES/04-begin-roman/II - Intro.mp3" "$FIXTURES/04-begin-roman/III - Intro.mp3"
  touch "$FIXTURES/05-both-arabic/1 Part 1.m4a" "$FIXTURES/05-both-arabic/2 Part 2.m4a"
  touch "$FIXTURES/06-no-series/Lonely 99.opus"
  touch "$FIXTURES/07-false-positive/Album.m4b"
  touch "$FIXTURES/08-gap/01 Gap.mp3" "$FIXTURES/08-gap/02 Gap.mp3" "$FIXTURES/08-gap/04 Gap.mp3"

  # End suffix is global track; Part N is title-only (not the sequence number).
  touch "$FIXTURES/09-lost-symbol-part/TheLostSymbolUnabridgedPart1_mp3-01.mp3"
  touch "$FIXTURES/09-lost-symbol-part/TheLostSymbolUnabridgedPart1_mp3-02.mp3"
  touch "$FIXTURES/09-lost-symbol-part/TheLostSymbolUnabridgedPart2_mp3-03.mp3"
  touch "$FIXTURES/09-lost-symbol-part/TheLostSymbolUnabridgedPart2_mp3-04.mp3"

  # No overall track numerals; only Part + Section labels.
  touch "$FIXTURES/10-inferno-sections/Inferno Part 1  Section 1.mp3"
  touch "$FIXTURES/10-inferno-sections/Inferno Part 1  Section 2.mp3"
  touch "$FIXTURES/10-inferno-sections/Inferno Part 2  Section 1.mp3"
  touch "$FIXTURES/10-inferno-sections/Inferno Part 2  Section 2.mp3"

  # Chapter number after the word Chapter, not at begin/end of basename.
  touch "$FIXTURES/11-chapter-mid/Chapter 01 - filename.mp3"
  touch "$FIXTURES/11-chapter-mid/Chapter 02 - filename.mp3"
  touch "$FIXTURES/11-chapter-mid/Chapter 100 - filename.mp3"

  touch "$FIXTURES/12-chapter-credits/Chapter 01 - filename.mp3"
  touch "$FIXTURES/12-chapter-credits/Chapter 02 - filename.mp3"
  touch "$FIXTURES/12-chapter-credits/Opening Credits - filename.mp3"
  touch "$FIXTURES/12-chapter-credits/End Credits - filename.mp3"
  mkdir -p "$FIXTURES/13-single-end" "$FIXTURES/14-single-chapter" "$FIXTURES/15-single-subdirs/book-a" "$FIXTURES/15-single-subdirs/book-b" "$FIXTURES/16-lonely-in-multi"
  touch "$FIXTURES/13-single-end/Book Title 3.m4b"
  touch "$FIXTURES/14-single-chapter/Chapter 01 - Book Title.m4b"
  touch "$FIXTURES/15-single-subdirs/book-a/Title A 1.m4b"
  touch "$FIXTURES/15-single-subdirs/book-b/Chapter 02 - Title B.m4b"
  touch "$FIXTURES/16-lonely-in-multi/01 Song.mp3" "$FIXTURES/16-lonely-in-multi/Album.m4b"
  mkdir -p "$FIXTURES/17-edge-spaces-begin" "$FIXTURES/18-edge-spaces-end"
  touch "$FIXTURES/17-edge-spaces-begin/  01 Alpha  .mp3" "$FIXTURES/17-edge-spaces-begin/  02 Alpha  .mp3"
  touch "$FIXTURES/18-edge-spaces-end/Song 1  .wav" "$FIXTURES/18-edge-spaces-end/Song 2  .wav"
  mkdir -p "$FIXTURES/19-inferno-spaced"
  touch "$FIXTURES/19-inferno-spaced/  01 Inferno .mp3" "$FIXTURES/19-inferno-spaced/ 02 Inferno.mp3"
  touch "$FIXTURES/19-inferno-spaced/  03 Inferno .mp3" "$FIXTURES/19-inferno-spaced/ 04 Inferno .mp3"
  touch "$FIXTURES/19-inferno-spaced/  05 Inferno. .mp3" "$FIXTURES/19-inferno-spaced/08 Inferno.mp3"
  mkdir -p "$FIXTURES/20-shared-prefix" "$FIXTURES/21-shared-suffix"
  touch "$FIXTURES/20-shared-prefix/20th Century Ghosts - Intro 01.mp3"
  touch "$FIXTURES/20-shared-prefix/20th Century Ghosts - Part Two 02.mp3"
  touch "$FIXTURES/20-shared-prefix/20th Century Ghosts_The End 03.mp3"
  touch "$FIXTURES/21-shared-suffix/Intro - Shared Audiobook 01.mp3"
  touch "$FIXTURES/21-shared-suffix/Outro - Shared Audiobook 02.mp3"
  mkdir -p "$FIXTURES/22-shared-suffix-numeric"
  touch "$FIXTURES/22-shared-suffix-numeric/01 title - 012345678.mp3"
  touch "$FIXTURES/22-shared-suffix-numeric/02 title - 012345678.mp3"
  touch "$FIXTURES/22-shared-suffix-numeric/03 title - 012345678.mp3"
  mkdir -p "$FIXTURES/23-shared-prefix-year"
  touch "$FIXTURES/23-shared-prefix-year/2001 A Space Odyssey - 01.mp3"
  touch "$FIXTURES/23-shared-prefix-year/2001 A Space Odyssey - 02.mp3"
  touch "$FIXTURES/23-shared-prefix-year/2001 A Space Odyssey - 03.mp3"
  cat > "$FIXTURES/12-chapter-credits/playlist.m3u" <<'EOF'
#EXTM3U
#EXTINF:28, Opening Credits
Opening Credits - filename.mp3
#EXTINF:100, Chapter 1
Chapter 01 - filename.mp3
#EXTINF:100, Chapter 2
Chapter 02 - filename.mp3
#EXTINF:38, End Credits
End Credits - filename.mp3
EOF
}

run_report() { $ZSH "$SCRIPT" "$1" 2>&1 }
run_rename_dry() { $ZSH "$SCRIPT" --rename "$1" 2>&1 }

test_syntax() {
  print -r "\n== Syntax =="
  if $ZSH -n "$SCRIPT"; then print -r "  PASS: zsh -n script"; (( PASS++ ))
  else print -u2 "  FAIL: zsh -n script"; (( FAIL++ )); fi
}

test_begin_arabic_report() {
  print -r "\n== 01 begin Arabic report =="
  local out=$(run_report "$FIXTURES/01-begin-arabic")
  assert_contains "finds begin series" 'Series (Arabic): Track' "$out"
  assert_contains "lists track 1" '1 Track.mp3' "$out"
}

test_end_roman_report() {
  print -r "\n== 03 end Roman report =="
  local out=$(run_report "$FIXTURES/03-end-roman")
  assert_contains "finds end roman series" 'Series (Roman): Chapter' "$out"
  assert_contains "lists III" 'Chapter III.flac' "$out"
}

test_false_positive() {
  print -r "\n== 07 false positive =="
  local out=$(run_report "$FIXTURES/07-false-positive")
  assert_contains "no series message" 'No sequential numbered audio series found' "$out"
}

test_rename_arabic_padding() {
  print -r "\n== Rename: Arabic zero-pad =="
  local tmp=$(mktemp -d)
  cp "$FIXTURES/01-begin-arabic/"*.mp3 "$tmp/"
  local out=$(run_rename_dry "$tmp")
  assert_contains "plans 01 prefix" '01 Track.mp3' "$out"
  assert_contains "plans 02 prefix" '02 Track.mp3' "$out"
  assert_not_contains "no 0I roman prefix" '-> */0I ' "$out"
  rm -rf "$tmp"
}

test_rename_roman_no_zero() {
  print -r "\n== Rename: Roman no zero prefix =="
  local tmp=$(mktemp -d)
  cp "$FIXTURES/03-end-roman/"*.flac "$tmp/"
  local out=$(run_rename_dry "$tmp")
  assert_contains "plans I prefix" 'I Chapter.flac' "$out"
  assert_contains "plans III prefix" 'III Chapter.flac' "$out"
  assert_not_contains "no 0I roman prefix" '0I Chapter' "$out"
  assert_not_contains "no 01 roman for chapter I" '01 Chapter.flac' "$out"
  rm -rf "$tmp"
}

test_rename_end_arabic() {
  print -r "\n== Rename: end Arabic to front =="
  local tmp=$(mktemp -d)
  cp "$FIXTURES/02-end-arabic/"*.wav "$tmp/"
  local out=$(run_rename_dry "$tmp")
  assert_contains "Song 3 becomes 03 Song" '03 Song.wav' "$out"
  rm -rf "$tmp"
}

test_single_file_end_numeral() {
  print -r "\n== 13 Single file: end numeral in lone-audio folder =="
  local out=$(run_rename_dry "$FIXTURES/13-single-end")
  assert_contains "plans 03 prefix" '03 Book Title.m4b' "$out"
}

test_single_file_chapter_structure() {
  print -r "\n== 14 Single file: Chapter NN in lone-audio folder =="
  local out=$(run_rename_dry "$FIXTURES/14-single-chapter")
  assert_contains "plans 01 prefix" '01 Book Title.m4b' "$out"
}

test_single_file_subdirs() {
  print -r "\n== 15 Single file: one audio per nested book folder =="
  local out=$(run_rename_dry "$FIXTURES/15-single-subdirs")
  assert_contains "book-a end numeral" '01 Title A.m4b' "$out"
  assert_contains "book-b chapter mid" '02 Title B.m4b' "$out"
}

test_lonely_in_multi_audio_dir() {
  print -r "\n== 16 Single parseable file with another audio present =="
  local out=$(run_rename_dry "$FIXTURES/16-lonely-in-multi")
  assert_contains "no plans without pair" 'No renames planned' "$out"
}

test_no_rename_unparsed_single() {
  print -r "\n== 07 false positive: unparsed single file =="
  local out=$(run_rename_dry "$FIXTURES/07-false-positive")
  assert_contains "no plans" 'No renames planned' "$out"
}

test_rename_lonely_single() {
  print -r "\n== 06 single file: trailing numeral in lone-audio folder =="
  local out=$(run_rename_dry "$FIXTURES/06-no-series")
  assert_contains "plans 99 prefix" '99 Lonely.opus' "$out"
}

test_apply_roundtrip() {
  print -r "\n== Apply rename roundtrip =="
  local tmp=$(mktemp -d)
  cp "$FIXTURES/05-both-arabic/"*.m4a "$tmp/"
  $ZSH "$SCRIPT" --rename --apply "$tmp" >/dev/null
  if [[ -f "$tmp/01 Part.m4a" ]]; then print -r "  PASS: 01 Part.m4a exists"; (( PASS++ ))
  else print -u2 "  FAIL: 01 Part.m4a exists"; (( FAIL++ )); fi
  if [[ -f "$tmp/02 Part.m4a" ]]; then print -r "  PASS: 02 Part.m4a exists"; (( PASS++ ))
  else print -u2 "  FAIL: 02 Part.m4a exists"; (( FAIL++ )); fi
  local listing=$(ls "$tmp")
  assert_not_contains "trailing duplicate removed" 'Part 1' "$listing"
  rm -rf "$tmp"
}

test_lost_symbol_album_sequence() {
  print -r "\n== 09 Lost Symbol: album sequence across parts =="
  local out=$(run_report "$FIXTURES/09-lost-symbol-part")
  assert_contains "merged album series" 'Series (Arabic): TheLostSymbolUnabridged_mp3' "$out"
  assert_not_contains "no separate part1 header" 'Series (Arabic): TheLostSymbolUnabridgedPart1_mp3' "$out"
  assert_contains "global 01" '[01]' "$out"
  assert_contains "global 04" '[04]' "$out"
}

test_lost_symbol_rename() {
  print -r "\n== 09 Lost Symbol: suffix continues across parts =="
  local out=$(run_rename_dry "$FIXTURES/09-lost-symbol-part")
  assert_contains "part1 suffix 01" '01 TheLostSymbolUnabridged Part 1.mp3' "$out"
  assert_contains "part1 suffix 02" '02 TheLostSymbolUnabridged Part 1.mp3' "$out"
  assert_contains "part2 suffix 03 continues" '03 TheLostSymbolUnabridged Part 2.mp3' "$out"
  assert_contains "part2 suffix 04 continues" '04 TheLostSymbolUnabridged Part 2.mp3' "$out"
  assert_not_contains "no duplicate 02 from restart" $'02 TheLostSymbolUnabridged Part 2.mp3' "$out"
}

test_inferno_synth_sequence() {
  print -r "\n== 10 Inferno: synth sequence from sections =="
  local out=$(run_report "$FIXTURES/10-inferno-sections")
  assert_contains "merged album series" 'Series (Arabic): Inferno' "$out"
  assert_contains "synth mode message" 'sequence synthesized from Part/Chapter/Section' "$out"
  assert_contains "global 01" '[01]' "$out"
  assert_contains "global 04" '[04]' "$out"
}

test_inferno_synth_rename() {
  print -r "\n== 10 Inferno: synth rename =="
  local out=$(run_rename_dry "$FIXTURES/10-inferno-sections")
  assert_contains "section 1 global 01" '01 Inferno.mp3' "$out"
  assert_contains "section 2 global 02" '02 Inferno.mp3' "$out"
  assert_contains "part2 section1 global 03" '03 Inferno.mp3' "$out"
  assert_contains "part2 section2 global 04" '04 Inferno.mp3' "$out"
  assert_not_contains "no part label in new name" '.mp3 Inferno Part' "$out"
}

test_chapter_mid_synth_sequence() {
  print -r "\n== 11 Chapter mid: synth from Chapter NN - title =="
  local out=$(run_report "$FIXTURES/11-chapter-mid")
  assert_contains "finds chapter mid series" 'Series (Arabic): filename' "$out"
  assert_contains "synth mode message" 'sequence synthesized from Part/Chapter/Section' "$out"
  assert_contains "chapter 1 global 001" '[001]' "$out"
  assert_contains "chapter 100 global 100" '[100]' "$out"
}

test_chapter_mid_synth_rename() {
  print -r "\n== 11 Chapter mid: synth rename =="
  local out=$(run_rename_dry "$FIXTURES/11-chapter-mid")
  assert_contains "ch01 becomes 001" '001 filename.mp3' "$out"
  assert_contains "ch02 becomes 002" '002 filename.mp3' "$out"
  assert_contains "ch100 becomes 100" '100 filename.mp3' "$out"
  assert_not_contains "no Chapter label in new name" 'filename Chapter' "$out"
}

test_chapter_credits_rename() {
  print -r "\n== 12 Chapter + credits: opening 00 and end last+1 =="
  local out=$(run_rename_dry "$FIXTURES/12-chapter-credits")
  assert_contains "opening credits 00" '00 filename.mp3' "$out"
  assert_contains "chapter 01" '01 filename.mp3' "$out"
  assert_contains "chapter 02" '02 filename.mp3' "$out"
  assert_contains "end credits 03" '03 filename.mp3' "$out"
  assert_not_contains "no credits label in target" '00 Opening Credits' "$out"
  assert_not_contains "no end credits label in target" '58 End Credits' "$out"
}

test_m3u_playlist_update() {
  print -r "\n== 12 M3U: playlist tracks planned renames =="
  local out=$(run_rename_dry "$FIXTURES/12-chapter-credits")
  assert_contains "plans m3u section" 'Planned playlist updates:' "$out"
  assert_contains "m3u opening line" $'Opening Credits - filename.mp3\n  -> 00 filename.mp3' "$out"
  assert_contains "m3u chapter 02 line" $'Chapter 02 - filename.mp3\n  -> 02 filename.mp3' "$out"
  assert_contains "m3u end line" $'End Credits - filename.mp3\n  -> 03 filename.mp3' "$out"
}

test_m3u_apply_roundtrip() {
  print -r "\n== 12 M3U: apply updates playlist file =="
  local tmp=$(mktemp -d)
  cp -R "$FIXTURES/12-chapter-credits/." "$tmp/"
  $ZSH "$SCRIPT" --rename --apply "$tmp" >/dev/null
  local m3u="$tmp/playlist.m3u"
  grep -Fq '00 filename.mp3' "$m3u" && print -r "  PASS: m3u has 00 opening" && (( PASS++ )) || {
    print -u2 "  FAIL: m3u missing 00 opening"; (( FAIL++ ))
  }
  grep -Fq '02 filename.mp3' "$m3u" && print -r "  PASS: m3u has 02 chapter" && (( PASS++ )) || {
    print -u2 "  FAIL: m3u missing 02 chapter"; (( FAIL++ ))
  }
  grep -Fq '03 filename.mp3' "$m3u" && print -r "  PASS: m3u has 03 end" && (( PASS++ )) || {
    print -u2 "  FAIL: m3u missing 03 end"; (( FAIL++ ))
  }
  grep -Fq 'Opening Credits - filename.mp3' "$m3u" && {
    print -u2 "  FAIL: m3u still has old opening name"; (( FAIL++ ))
  } || { print -r "  PASS: m3u dropped old opening name"; (( PASS++ )) }
  rm -rf "$tmp"
}

test_edge_spaces_begin() {
  print -r "\n== 17 Edge spaces: leading spaces before begin numeral =="
  local out=$(run_rename_dry "$FIXTURES/17-edge-spaces-begin")
  assert_contains "plans 01 Alpha" '01 Alpha.mp3' "$out"
  assert_contains "plans 02 Alpha" '02 Alpha.mp3' "$out"
}

test_edge_spaces_end() {
  print -r "\n== 18 Edge spaces: trailing spaces before extension =="
  local out=$(run_rename_dry "$FIXTURES/18-edge-spaces-end")
  assert_contains "plans 01 Song" '01 Song.wav' "$out"
  assert_contains "plans 02 Song" '02 Song.wav' "$out"
}

test_edge_spaces_apply() {
  print -r "\n== 17 Edge spaces: apply trims filename =="
  local tmp=$(mktemp -d)
  cp "$FIXTURES/17-edge-spaces-begin/"*.mp3 "$tmp/"
  $ZSH "$SCRIPT" --rename --apply "$tmp" >/dev/null
  [[ -f "$tmp/01 Alpha.mp3" ]] && print -r "  PASS: trimmed 01 Alpha.mp3 exists" && (( PASS++ )) || {
    print -u2 "  FAIL: trimmed 01 Alpha.mp3 missing"; (( FAIL++ ))
  }
  ls "$tmp" | grep -q '  01 Alpha' && {
    print -u2 "  FAIL: old spaced filename still present"; (( FAIL++ ))
  } || { print -r "  PASS: old spaced filename removed"; (( PASS++ )) }
  rm -rf "$tmp"
}

test_shared_prefix_end_numeral() {
  print -r "\n== 20 Shared prefix: ordinal title + end track numbers =="
  local out=$(run_rename_dry "$FIXTURES/20-shared-prefix")
  assert_contains "groups 20th Century Ghosts" '20th Century Ghosts - Intro' "$out"
  assert_contains "plans 01 intro" '01 20th Century Ghosts - Intro.mp3' "$out"
  assert_contains "plans 03 end" '03 20th Century Ghosts_The End.mp3' "$out"
  assert_not_contains "no th Century mangled title" '01 th Century Ghosts' "$out"
}

test_shared_suffix_numeric_catalog() {
  print -r "\n== 22 Shared numeric suffix: begin track + catalog end =="
  local out=$(run_report "$FIXTURES/22-shared-suffix-numeric")
  assert_contains "series uses title not catalog" 'Series (Arabic): title - 012345678' "$out"
  assert_contains "track 01" '[01]' "$out"
  assert_contains "track 03" '[03]' "$out"
  assert_not_contains "catalog not track index" '[12345678]' "$out"
  out=$(run_rename_dry "$FIXTURES/22-shared-suffix-numeric")
  assert_contains "no bogus rename" 'No renames planned' "$out"
  assert_not_contains "no collapse to catalog" '12345678 title.mp3' "$out"
}

test_shared_prefix_year_catalog() {
  print -r "\n== 23 Shared prefix year: begin catalog + end track numbers =="
  local out=$(run_report "$FIXTURES/23-shared-prefix-year")
  assert_contains "series keeps year in title" 'Series (Arabic): 2001 A Space Odyssey' "$out"
  assert_contains "track 01" '[01]' "$out"
  assert_contains "track 03" '[03]' "$out"
  assert_not_contains "year not track index" '[2001]' "$out"
  out=$(run_rename_dry "$FIXTURES/23-shared-prefix-year")
  assert_contains "plans 01 with year" '01 2001 A Space Odyssey.mp3' "$out"
  assert_contains "plans 03 with year" '03 2001 A Space Odyssey.mp3' "$out"
  if print -r -- "$out" | grep -Eq -- '-> .*/0[123] A Space Odyssey\.mp3$'; then
    print -u2 "  FAIL: year stripped from rename target"
    (( FAIL++ ))
  else
    print -r "  PASS: year kept in rename target"
    (( PASS++ ))
  fi
}

test_shared_suffix_end_numeral() {
  print -r "\n== 21 Shared suffix: common title suffix grouping =="
  local out=$(run_rename_dry "$FIXTURES/21-shared-suffix")
  assert_contains "plans 01 intro" '01 Intro - Shared Audiobook.mp3' "$out"
  assert_contains "plans 02 outro" '02 Outro - Shared Audiobook.mp3' "$out"
}

test_inferno_spaced_apply() {
  print -r "\n== 19 Inferno spaced: apply trims all planned leading/trailing spaces =="
  local tmp=$(mktemp -d)
  cp "$FIXTURES/19-inferno-spaced/"*.mp3 "$tmp/"
  $ZSH "$SCRIPT" --rename --apply "$tmp" >/dev/null
  [[ -f "$tmp/01 Inferno.mp3" ]] && print -r "  PASS: 01 Inferno.mp3" && (( PASS++ )) || {
    print -u2 "  FAIL: 01 Inferno.mp3"; (( FAIL++ ))
  }
  [[ -f "$tmp/02 Inferno.mp3" ]] && print -r "  PASS: 02 Inferno.mp3" && (( PASS++ )) || {
    print -u2 "  FAIL: 02 Inferno.mp3"; (( FAIL++ ))
  }
  [[ -f "$tmp/03 Inferno.mp3" ]] && print -r "  PASS: 03 Inferno.mp3" && (( PASS++ )) || {
    print -u2 "  FAIL: 03 Inferno.mp3"; (( FAIL++ ))
  }
  [[ -f "$tmp/05 Inferno.mp3" ]] && print -r "  PASS: 05 Inferno.mp3" && (( PASS++ )) || {
    print -u2 "  FAIL: 05 Inferno.mp3"; (( FAIL++ ))
  }
  ls "$tmp"/*.mp3 | grep -q '  ' && {
    print -u2 "  FAIL: spaced filename still present"; (( FAIL++ ))
  } || { print -r "  PASS: no edge-spaced filenames remain"; (( PASS++ )) }
  rm -rf "$tmp"
}

test_format_unit() {
  print -r "\n== Unit: format_leading_numeral =="
  local out
  out=$($ZSH -c '. "$1" 2>/dev/null; format_leading_numeral arabic 3 2' -- "$SCRIPT")
  if [[ $out == 03 ]]; then print -r "  PASS: arabic pad 03"; (( PASS++ ))
  else print -u2 "  FAIL: arabic pad 03 (got: $out)"; (( FAIL++ )); fi
  out=$($ZSH -c '. "$1" 2>/dev/null; format_leading_numeral roman 4 2' -- "$SCRIPT")
  if [[ $out == IV ]]; then print -r "  PASS: roman IV not 04"; (( PASS++ ))
  else print -u2 "  FAIL: roman IV not 04 (got: $out)"; (( FAIL++ )); fi
  out=$($ZSH -c '. "$1" 2>/dev/null; format_leading_numeral roman 4 0' -- "$SCRIPT")
  if [[ $out == IV ]]; then print -r "  PASS: roman pad_width 0 still IV"; (( PASS++ ))
  else print -u2 "  FAIL: roman pad_width 0 still IV (got: $out)"; (( FAIL++ )); fi
}

main() {
  print -r "find-numbered-audio tests"
  print -r "Script: $SCRIPT"
  print -r "Zsh:    $($ZSH --version 2>&1)"

  setup_fixtures
  test_syntax
  test_begin_arabic_report
  test_end_roman_report
  test_false_positive
  test_rename_arabic_padding
  test_rename_roman_no_zero
  test_rename_end_arabic
  test_rename_lonely_single
  test_single_file_end_numeral
  test_single_file_chapter_structure
  test_single_file_subdirs
  test_lonely_in_multi_audio_dir
  test_no_rename_unparsed_single
  test_apply_roundtrip
  test_lost_symbol_album_sequence
  test_lost_symbol_rename
  test_inferno_synth_sequence
  test_inferno_synth_rename
  test_chapter_mid_synth_sequence
  test_chapter_mid_synth_rename
  test_chapter_credits_rename
  test_m3u_playlist_update
  test_m3u_apply_roundtrip
  test_edge_spaces_begin
  test_edge_spaces_end
  test_edge_spaces_apply
  test_inferno_spaced_apply
  test_shared_prefix_end_numeral
  test_shared_suffix_end_numeral
  test_shared_suffix_numeric_catalog
  test_shared_prefix_year_catalog
  test_format_unit

  print -r "\n== Summary =="
  print -r "PASS: $PASS  FAIL: $FAIL"
  (( FAIL == 0 )) || exit 1
  print -r "All tests passed."
}

main
