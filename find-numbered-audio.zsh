#!/bin/zsh
#
# find-numbered-audio.zsh — Find (and optionally rename) sequentially numbered audio.
#
# Rename mode moves the track number to the front of the filename:
#   - Arabic: zero-padded (min 2 digits, or wider when the series requires it)
#   - Roman: never zero-padded (I, II, IV, …)
#
# Usage:
#   find-numbered-audio.zsh [directory]
#   find-numbered-audio.zsh --rename [directory]
#   find-numbered-audio.zsh --rename --apply [directory]
#
# Compatible with zsh 5.8+ on macOS and Linux.
#
# Linux notes (usually no script edits required):
#   - Shebang: macOS uses /bin/zsh; many Linux distros install zsh as /usr/bin/zsh.
#     If ./find-numbered-audio.zsh fails with "bad interpreter", either:
#       (a) change line 1 to  #!/usr/bin/zsh
#       (b) run explicitly:  zsh find-numbered-audio.zsh [options] [directory]
#   - Do not run with bash or sh; this file uses zsh-only syntax.
#   - find-numbered-audio-test.zsh sets ZSH=/bin/zsh; on Linux, set
#     ZSH=/usr/bin/zsh (or export ZSH=$(command -v zsh)) before running tests.
#   - Requires standard POSIX find, sort, mv, and grep (GNU or BSD toolchains).
#
# OpenAudible / multi-file join compatibility:
#   OpenAudible joins chapters in strict alphabetical filename order (see
#   openaudible.org/documentation, "Join Audio Files"). After --rename --apply,
#   Arabic-numbered audiobooks are shaped for that: zero-padded track prefixes
#   at the front (e.g. 001 Title.mp3, 002 Title.mp3) so 11 sorts after 02.
#   Put one book per directory; verify with:  ls -1 /path/to/book | sort
#   Caveats:
#     - --rename alone is a dry run; files are not changed until --apply is used.
#     - Roman prefixes (I, II, III…) are not zero-padded and do not sort in
#       numeric order alphabetically; prefer Arabic numbering for OpenAudible joins.
#     - Unparsed tracks in the folder are left unchanged and may sort into the
#       wrong position if mixed with renamed chapters.
#     - Directories with exactly one audio file are still renamed when the name
#       parses (e.g. whole-book .m4b with a trailing track number, or
#       Chapter NN - title). Unparsed single files (no numerals/structure) are
#       skipped. Multi-file folders still need 2+ matching tracks per album.
#     - Opening Credits / End Credits (same album title) are auto-numbered 00
#       and last+1 when a numbered album series is renamed in the same folder.
#     - .m3u playlists in the same folder are updated to reference new filenames
#       when --rename --apply runs (dry-run shows planned playlist line changes).
#     - Leading/trailing spaces in basenames are trimmed before parsing; renames
#       drop those spaces from the new filename.
#     - Ordinals at the title start (20th, 1st) are not treated as track numbers.
#     - End-primary albums with a shared title prefix or suffix (e.g. Book … 01,
#       Book … 02) are grouped and renamed using the trailing track number.

emulate -L zsh -o extendedglob

typeset -a AUDIO_EXTS=(mp3 wav flac aac ogg m4a m4b opus)
typeset -a PARSE_RESULT
typeset -ga PLAN_REPLY

strip_edge_seps() {
  local s=$1
  while [[ -n $s && $s[1] == [._\ -] ]]; do s=${s#?}; done
  while [[ -n $s && $s[-1] == [._\ -] ]]; do s=${s[1,-2]}; done
  print -rn -- "$s"
}

# Remove leading/trailing whitespace from a basename before parsing or playlist matching.
trim_edge_spaces() {
  local s=$1
  while [[ -n $s && $s[1] == [[:space:]] ]]; do s=${s#?}; done
  while [[ -n $s && $s[-1] == [[:space:]] ]]; do s=${s[1,-2]}; done
  print -rn -- "$s"
}

# Basename without extension; edge spaces trimmed so begin/end numerals are detected.
audio_basename() {
  local fname=$1 base
  base=${fname%.*}
  [[ $fname == *.* ]] || base=$fname
  trim_edge_spaces "$base"
}

is_valid_roman() {
  local r=${(U)1}
  [[ -n $r && $r =~ '^[IVXLCDM]+$' ]] || return 1
  [[ $r != *IIII* && $r != *VV* && $r != *LL* && $r != *DD* ]] || return 1
}

roman_to_int() {
  local r=${(U)1} i c val=0 next
  is_valid_roman "$r" || return 1
  for (( i = 1; i <= ${#r}; i++ )); do
    c=${r[i]}
    case $c in
      I) val=$(( val + 1 )) ;;
      V) val=$(( val + 5 )) ;;
      X) val=$(( val + 10 )) ;;
      L) val=$(( val + 50 )) ;;
      C) val=$(( val + 100 )) ;;
      D) val=$(( val + 500 )) ;;
      M) val=$(( val + 1000 )) ;;
      *) return 1 ;;
    esac
    if (( i < ${#r} )); then
      next=${r[i+1]}
      case $c in
        I) [[ $next == [VX] ]] && val=$(( val - 2 )) ;;
        X) [[ $next == [LC] ]] && val=$(( val - 20 )) ;;
        C) [[ $next == [DM] ]] && val=$(( val - 200 )) ;;
      esac
    fi
  done
  (( val > 0 )) || return 1
  print -rn -- "$val"
}

int_to_roman() {
  local n=$1 i result=
  (( n > 0 && n < 4000 )) || return 1
  local -a vals=(1000 900 500 400 100 90 50 40 10 9 5 4 1)
  local -a syms=(M CM D CD C XC L XL X IX V IV I)
  for i in {1..13}; do
    while (( n >= vals[i] )); do
      result+=$syms[i]
      n=$(( n - vals[i] ))
    done
  done
  print -rn -- "$result"
}

# Prints: volume<TAB>book<TAB>part<TAB>chapter<TAB>section<TAB>album_prefix
extract_album_structure() {
  local base=$1 word
  local stripped=$base
  local volume_num=0 book_num=0 part_num=0 chapter_num=0 section_num=0 album_prefix=
  if [[ $base =~ '(^|[^[:alpha:]])[Vv][Oo][Ll][Uu][Mm][Ee][._ -]*([0-9]+)' ]]; then
    volume_num=$(( 10#${match[2]} ))
  fi
  if [[ $base =~ '(^|[^[:alpha:]])[Bb][Oo][Oo][Kk][._ -]*([0-9]+)' ]]; then
    book_num=$(( 10#${match[2]} ))
  fi
  if [[ $base =~ '([Pp][Aa][Rr][Tt])([._ -]*)([0-9]+)' ]]; then
    part_num=$(( 10#${match[3]} ))
  fi
  if [[ $base =~ '([Cc][Hh][Aa][Pp][Tt][Ee][Rr])([._ -]*)([0-9]+)' ]]; then
    chapter_num=$(( 10#${match[3]} ))
  fi
  if [[ $base =~ '([Ss][Ee][Cc][Tt][Ii][Oo][Nn])([._ -]*)([0-9]+)' ]]; then
    section_num=$(( 10#${match[3]} ))
  fi
  while [[ $stripped =~ '(.*)(^|[^[:alpha:]])[Vv][Oo][Ll][Uu][Mm][Ee][._ -]*([0-9]+)(.*)' ]]; do
    stripped="${match[1]}${match[4]}"
  done
  while [[ $stripped =~ '(.*)(^|[^[:alpha:]])[Bb][Oo][Oo][Kk][._ -]*([0-9]+)(.*)' ]]; do
    stripped="${match[1]}${match[4]}"
  done
  for word in Part Chapter Section; do
    while [[ $stripped =~ '(.*)'${word}'([._ -]*)([0-9]+)(.*)' ]]; do
      local _prefix=${match[1]} _suffix=${match[4]}
      stripped="${_prefix}${_suffix}"
    done
  done
  album_prefix=$stripped
  if [[ -n $album_prefix ]]; then
    album_prefix=$(strip_edge_seps "$album_prefix")
  fi
  [[ -z $album_prefix ]] && album_prefix=$base
  if [[ -z $album_prefix || $album_prefix == $base ]] && \
     (( volume_num || book_num || part_num || chapter_num || section_num )); then
    album_prefix=''
  fi
  print -rn -- "${volume_num}"$'\t'"${book_num}"$'\t'"${part_num}"$'\t'"${chapter_num}"$'\t'"${section_num}"$'\t'"${album_prefix}"
}

# Collapse duplicate " - " separators left after removing mid-title structure labels.
collapse_title_separators() {
  local s=$1
  while [[ $s == *' -  - '* || $s == *' - - '* ]]; do
    s=${s// -  - / - }
    s=${s// - - / - }
  done
  s=$(strip_edge_seps "$s")
  print -r -- "$s"
}

# Remove mid-title Part/Chapter/Section segments for album grouping keys.
remove_embedded_structure_segments() {
  local stem=$1 word
  for word in Chapter Part Section; do
    while [[ $stem =~ '(.*)'${word}'[._ -]*([0-9]+)[._ -]+(.*)' ]]; do
      stem="${match[1]}${match[3]}"
      stem=$(collapse_title_separators "$stem")
    done
  done
  print -r -- "$stem"
}

# True when a structure label sits in the title body, not as the trailing track index.
is_embedded_structure_label() {
  local key=$1 label=$2 num=$3
  local lb=${(L)key}
  (( num )) || return 1
  [[ $lb == *${label}* ]] || return 1
  [[ $lb =~ '(^|[^[:alpha:]])'${label}'[._ -]*'${num}'$' ]] && return 1
  [[ $lb =~ '(^|[^[:alpha:]])'${label}'[._ -]*'${num}'[._ -]+' ]]
}

has_embedded_structure_labels() {
  local key=$1 chapter_num=$2 part_num=$3 section_num=$4
  is_embedded_structure_label "$key" chapter "$chapter_num" && return 0
  is_embedded_structure_label "$key" part "$part_num" && return 0
  is_embedded_structure_label "$key" section "$section_num" && return 0
  return 1
}

typeset -ga STRUCT_FIELDS
load_structure_fields() {
  STRUCT_FIELDS=("${(@ps:\t:)${1}}")
}

strip_trailing_structure_index() {
  local key=$1 e_num=$2
  local lb=${(L)key} keep
  [[ $lb =~ '(.*)(^|[^[:alpha:]])(volume|book|part|chapter|section)[._ -]*'${e_num}'$' ]] || return 1
  keep=${#match[1]}
  key=${key[1,$keep]}
  key=$(strip_edge_seps "$key")
  print -rn -- "$key"
}

is_structure_derived_end() {
  local base=$1 e_num=$2
  local lb=${(L)base}
  # Arabic structure labels only; trailing Roman (e.g. Chapter III) is a track index.
  [[ $e_num == <-> ]] && [[ $lb =~ '(^|[^[:alpha:]])(volume|book|part|chapter|section)[._ -]*'${e_num}'$' ]]
}

# True when begin/end numerals are a track index (e.g. -01), not Part/Chapter/Section labels.
is_true_edge_track() {
  local base=$1 b_num=$2 e_num=$3
  [[ $base =~ '[-_][0-9]+$' ]] && return 0
  if [[ -n $b_num && $base =~ '^[0-9]+[._ -]' && $base != [Pp]art* ]]; then
    return 0
  fi
  if [[ -n $e_num ]] && ! is_structure_derived_end "$base" "$e_num"; then
    return 0
  fi
  return 1
}

# True when leading digits are an ordinal (20th, 1st), not a track index.
is_ordinal_begin_rest() {
  local rest=$1
  [[ ${(L)rest} == th* || ${(L)rest} == st* || ${(L)rest} == nd* || ${(L)rest} == rd* ]]
}

reverse_string() {
  local s=$1 i result=
  for (( i = ${#s}; i >= 1; i-- )); do result+=${s[i]}; done
  print -rn -- "$result"
}

longest_common_prefix() {
  local -a strs=("$@")
  local first=$strs[1]
  local -i li=1
  local c common=
  (( ${#strs} >= 2 )) || { [[ -n $first ]] && print -rn -- "$first"; return 0 }
  while (( li <= ${#first} )); do
    c=${first[li]}
    for s in "${strs[@]}"; do
      [[ ${#s} -ge li && ${s[li]} == $c ]] || { print -rn -- "$common"; return 0 }
    done
    common+=$c
    (( li++ ))
  done
  print -rn -- "$common"
}

longest_common_suffix() {
  local -a strs=("$@") rev_strs=() s rev first
  local -i li=1
  local c common=
  for s in "${strs[@]}"; do
    rev_strs+=("$(reverse_string "$s")")
  done
  first=${rev_strs[1]}
  (( ${#rev_strs} >= 2 )) || { [[ -n $first ]] && print -rn -- "$(reverse_string "$first")"; return 0 }
  while (( li <= ${#first} )); do
    c=${first[li]}
    for s in "${rev_strs[@]}"; do
      [[ ${#s} -ge li && ${s[li]} == $c ]] || {
        print -rn -- "$(reverse_string "$common")"
        return 0
      }
    done
    common+=$c
    (( li++ ))
  done
  print -rn -- "$(reverse_string "$common")"
}

# True when trailing digits are catalog/metadata (e.g. 012345678), not the per-file track index.
is_catalog_end_numeral() {
  local b_val=$1 e_val=$2 e_num=$3
  (( b_val != e_val )) || return 1
  (( e_val > 199 || ${#e_num} >= 4 ))
}

# True when leading digits are catalog/metadata (e.g. 2001), not the per-file track index.
is_catalog_begin_numeral() {
  local b_val=$1 e_val=$2 b_num=$3
  (( b_val != e_val )) || return 1
  (( b_val > 199 || ${#b_num} >= 4 ))
}

# Album group keys must include letters; pure digit suffixes are not used for grouping.
shared_album_key_usable() {
  local key=$1
  [[ -n $key && $key != __bare__ && $key != *[[:alpha:]]* ]] && return 1
  return 0
}

# When all stems end with the same text after " - ", return that suffix.
literal_shared_suffix() {
  local -a stems=("$@")
  local s suffix candidate=
  (( ${#stems} >= 2 )) || return 1
  for s in "${stems[@]}"; do
    [[ $s == *' - '* ]] || return 1
    candidate=${s##* - }
    [[ -n $candidate ]] || return 1
    if [[ -z $suffix ]]; then suffix=$candidate
    elif [[ $suffix != $candidate ]]; then return 1
    fi
  done
  print -rn -- "$suffix"
}

typeset -gi SHARED_TITLE_MIN_LEN=8

trim_shared_title_key() {
  local s=$1
  s=$(trim_edge_spaces "$s")
  while [[ -n $s && $s[-1] == [-_.[:space:]] ]]; do s=${s[1,-2]}; done
  print -rn -- "$s"
}

# Pick the longer qualifying shared prefix or suffix for album grouping.
choose_shared_album_key() {
  local -a stems=("$@")
  local lcp lcs lit prefix_key suffix_key min=$SHARED_TITLE_MIN_LEN
  (( ${#stems} >= 2 )) || return 1
  lcp=$(trim_shared_title_key "$(longest_common_prefix "${stems[@]}")")
  lcs=$(trim_shared_title_key "$(longest_common_suffix "${stems[@]}")")
  lit=$(literal_shared_suffix "${stems[@]}") || lit=
  if [[ -n $lit ]]; then
    suffix_key=$(trim_shared_title_key "$lit")
    if shared_album_key_usable "$suffix_key" && (( ${#suffix_key} >= min )); then
      print -rn -- "$suffix_key"
      return 0
    fi
    prefix_key=$(trim_shared_title_key "${lcp% - ${lit}}")
    if [[ -n $prefix_key ]] && shared_album_key_usable "$prefix_key" && (( ${#prefix_key} >= min )); then
      print -rn -- "$prefix_key"
      return 0
    fi
  fi
  if shared_album_key_usable "$lcp" && (( ${#lcp} >= min && ${#lcp} >= ${#lcs} )); then
    print -rn -- "$lcp"
    return 0
  fi
  if shared_album_key_usable "$lcs" && (( ${#lcs} >= min )); then
    print -rn -- "$lcs"
    return 0
  fi
  return 1
}

# Merge end-primary tracks that share a title prefix or suffix (e.g. Book … 01, Book … 02).
scan_entry_line() {
  local -a fields=("$@")
  print -rn -- "${fields[1]}"$'\t'"${fields[2]}"$'\t'"${fields[3]}"$'\t'"${fields[4]}"$'\t'"${fields[5]}"$'\t'"${fields[6]}"$'\t'"${fields[7]}"$'\t'"${fields[8]}"$'\t'"${fields[9]}"$'\t'"${fields[10]}"
}

append_scan_entry() {
  local gkey=$1
  shift
  local -a fields=("$@")
  SCAN_GROUPS[$gkey]+="$(scan_entry_line "${fields[@]}")"$'\n'
}

regroup_end_primary_lines() {
  local kind=$1
  shift
  local -a sorted=() run_lines=() run_stems=()
  local line track_val stem_line fields stem val prev=-999 shared_key new_gkey

  (( $# )) || return 0
  sorted=("${(@f)$(printf '%s\n' "$@" | LC_ALL=C sort -t '	' -k1,1n)}")

  flush_one_run() {
    local stem_line gkey_restore
    if (( ${#run_lines} < 2 )); then
      for stem_line in "${run_lines[@]}"; do
        fields=("${(@ps:\t:)stem_line}")
        gkey_restore="end|${kind}|${fields[9]}"
        append_scan_entry "$gkey_restore" "${fields[@]}"
      done
      run_lines=(); run_stems=(); prev=-999
      return
    fi
    shared_key=$(choose_shared_album_key "${run_stems[@]}") || {
      for stem_line in "${run_lines[@]}"; do
        fields=("${(@ps:\t:)stem_line}")
        gkey_restore="end|${kind}|${fields[9]}"
        append_scan_entry "$gkey_restore" "${fields[@]}"
      done
      run_lines=(); run_stems=(); prev=-999
      return
    }
    new_gkey="end|${kind}|${shared_key}"
    for stem_line in "${run_lines[@]}"; do
      fields=("${(@ps:\t:)stem_line}")
      fields[9]=$shared_key
      append_scan_entry "$new_gkey" "${fields[@]}"
    done
    run_lines=(); run_stems=(); prev=-999
  }

  for line in "${sorted[@]}"; do
    track_val=${line%%$'\t'*}
    stem_line=${line#*$'\t'}
    val=$(( 10#$track_val ))
    fields=("${(@ps:\t:)stem_line}")
    stem=${fields[9]}
    if (( ${#run_lines} && val != prev + 1 )); then
      flush_one_run
    fi
    run_lines+=("$stem_line")
    run_stems+=("$stem")
    prev=$val
  done
  flush_one_run
}

regroup_shared_title_albums() {
  local -A keep_groups
  local -a arabic_pool=() roman_pool=()
  local gkey entries pos line fields

  for gkey entries in ${(kv)SCAN_GROUPS}; do
    pos=${gkey%%|*}
    if [[ $pos == end ]]; then
      for line in ${(f)entries}; do
        [[ -z $line ]] && continue
        fields=("${(@ps:\t:)line}")
        if [[ ${${gkey#*|}%%|*} == arabic ]]; then
          arabic_pool+=("${fields[2]}"$'\t'"$line")
        else
          roman_pool+=("${fields[2]}"$'\t'"$line")
        fi
      done
    else
      keep_groups[$gkey]=$entries
    fi
  done

  SCAN_GROUPS=()
  for gkey entries in ${(kv)keep_groups}; do
    SCAN_GROUPS[$gkey]=$entries
  done
  regroup_end_primary_lines arabic "${arabic_pool[@]}"
  regroup_end_primary_lines roman "${roman_pool[@]}"
}

structure_part_label() {
  local volume_num=$1 book_num=$2 part_num=$3 chapter_num=$4 section_num=$5
  local -a labels=()
  (( volume_num )) && labels+=("Volume $volume_num")
  (( book_num )) && labels+=("Book $book_num")
  (( part_num )) && labels+=("Part $part_num")
  (( chapter_num )) && labels+=("Chapter $chapter_num")
  (( section_num )) && labels+=("Section $section_num")
  [[ ${#labels} -gt 0 ]] && print -r -- "${(j: :)labels}"
}

# Arabic → zero-padded; Roman → canonical (no leading zeros).
format_leading_numeral() {
  local kind=$1 val=$2 pad_width=$3
  if [[ $kind == arabic ]]; then
    printf '%0*d' "$pad_width" "$val"
  else
    int_to_roman "$val"
  fi
}

# PARSE_RESULT: pos kind val key display_num album_key album_prefix volume book part chapter section true_edge title_key
parse_audio_name() {
  local base=$1
  local b_num= b_kind= b_val= e_num= e_kind= e_val=
  local roman_candidate key album_key album_prefix title_key
  local volume_num=0 book_num=0 part_num=0 chapter_num=0 section_num=0 true_edge=0 embedded_structure=0 struct_data
  local pos use_kind use_val use_num part_label

  if [[ $base =~ '^([0-9]+)(.*)' ]]; then
    if is_ordinal_begin_rest "$match[2]"; then
      b_num=; b_kind=; b_val=
    else
      b_num=$match[1]; b_kind=arabic; b_val=$(( 10#$match[1] ))
    fi
  elif [[ $base =~ '^([IiVvXxLlCcDdMm]+)([._ -].*|$)' ]]; then
    roman_candidate=${(U)match[1]}
    if is_valid_roman "$roman_candidate" && b_val=$(roman_to_int "$roman_candidate"); then
      b_num=$match[1]; b_kind=roman; b_val=$(( b_val ))
    fi
  fi

  if [[ $base =~ '(^|[^0-9])([0-9]+)$' ]]; then
    e_num=$match[2]; e_kind=arabic; e_val=$(( 10#$e_num ))
  elif [[ $base =~ '(^|[._ -])([IiVvXxLlCcDdMm]+)$' ]]; then
    roman_candidate=${(U)match[2]}
    if is_valid_roman "$roman_candidate" && e_val=$(roman_to_int "$roman_candidate"); then
      e_num=$match[2]; e_kind=roman; e_val=$(( e_val ))
    fi
  fi

  if [[ -n $b_num && -n $e_num ]]; then pos=both
  elif [[ -n $b_num ]]; then pos=begin
  elif [[ -n $e_num ]]; then pos=end
  else pos=none
  fi

  if [[ $pos == none ]]; then
    struct_data=$(extract_album_structure "$base")
    load_structure_fields "$struct_data"
    volume_num=$STRUCT_FIELDS[1]
    book_num=$STRUCT_FIELDS[2]
    part_num=$STRUCT_FIELDS[3]
    chapter_num=$STRUCT_FIELDS[4]
    section_num=$STRUCT_FIELDS[5]
    album_prefix=$STRUCT_FIELDS[6]
    (( volume_num || book_num || part_num || chapter_num || section_num )) || return 1
    pos=structure
    use_kind=arabic; use_val=0; use_num=''
    true_edge=0
    key=$album_prefix
  else
    if is_true_edge_track "$base" "$b_num" "$e_num"; then
      true_edge=1
      local catalog_end=0 catalog_begin=0 structure_end=0
      if [[ $pos == both ]] && is_structure_derived_end "$base" "$e_num"; then
        structure_end=1
        use_kind=$b_kind; use_val=$b_val; use_num=$b_num
        pos=begin
      elif [[ $pos == both ]] && is_catalog_end_numeral "$b_val" "$e_val" "$e_num"; then
        catalog_end=1
        use_kind=$b_kind; use_val=$b_val; use_num=$b_num
        pos=begin
      elif [[ $pos == both ]] && is_catalog_begin_numeral "$b_val" "$e_val" "$b_num"; then
        catalog_begin=1
        use_kind=$e_kind; use_val=$e_val; use_num=$e_num
        pos=end
      elif [[ $pos == end || $pos == both ]]; then
        use_kind=$e_kind; use_val=$e_val; use_num=$e_num
      else
        use_kind=$b_kind; use_val=$b_val; use_num=$b_num
      fi
      key=$base
      local structure_book_num=0 structure_volume_num=0
      if [[ -n $b_num ]] && (( ! catalog_begin )); then key=${key#"$b_num"}; key=$(strip_edge_seps "$key"); fi
      if (( structure_end )); then
        local lb=${(L)key}
        if [[ $lb =~ '(^|[^[:alpha:]])(book)[._ -]*'${e_num}'$' ]]; then
          structure_book_num=$(( 10#$e_num ))
          key=$(strip_trailing_structure_index "$key" "$e_num")
        elif [[ $lb =~ '(^|[^[:alpha:]])(volume)[._ -]*'${e_num}'$' ]]; then
          structure_volume_num=$(( 10#$e_num ))
          key=$(strip_trailing_structure_index "$key" "$e_num")
        else
          key=${key%"$e_num"}
          key=$(strip_edge_seps "$key")
        fi
      elif [[ -n $e_num ]] && (( ! catalog_end )); then
        key=${key%"$e_num"}
        key=$(strip_edge_seps "$key")
      fi
      [[ -n $key ]] || key='__bare__'
      struct_data=$(extract_album_structure "$key")
      load_structure_fields "$struct_data"
      volume_num=$STRUCT_FIELDS[1]
      book_num=$STRUCT_FIELDS[2]
      part_num=$STRUCT_FIELDS[3]
      chapter_num=$STRUCT_FIELDS[4]
      section_num=$STRUCT_FIELDS[5]
      album_prefix=$STRUCT_FIELDS[6]
      (( structure_volume_num )) && volume_num=$structure_volume_num
      (( structure_book_num )) && book_num=$structure_book_num
      if has_embedded_structure_labels "$key" "$chapter_num" "$part_num" "$section_num"; then
        embedded_structure=1
        album_prefix=$(remove_embedded_structure_segments "$key")
        album_prefix=$(collapse_title_separators "$album_prefix")
      fi
    else
      true_edge=0
      use_kind=arabic; use_val=0; use_num=''
      pos=structure
      struct_data=$(extract_album_structure "$base")
      load_structure_fields "$struct_data"
      volume_num=$STRUCT_FIELDS[1]
      book_num=$STRUCT_FIELDS[2]
      part_num=$STRUCT_FIELDS[3]
      chapter_num=$STRUCT_FIELDS[4]
      section_num=$STRUCT_FIELDS[5]
      album_prefix=$STRUCT_FIELDS[6]
      key=$album_prefix
    fi
  fi

  [[ -z $album_prefix ]] && album_prefix=$key
  album_key=$album_prefix
  [[ -n $album_key ]] || album_key='__bare__'

  if (( embedded_structure )); then
    title_key=$key
  else
    part_label=$(structure_part_label "$volume_num" "$book_num" "$part_num" "$chapter_num" "$section_num")
    album_title=$(clean_album_title_prefix "$album_prefix")
    if [[ -n $part_label && -n $album_title ]]; then
      title_key="${album_title} ${part_label}"
    elif [[ -n $part_label ]]; then
      title_key=$part_label
    elif [[ -n $album_title ]]; then
      title_key=$album_title
    else
      title_key=$album_prefix
    fi
  fi
  [[ -n $title_key ]] || title_key=$key
  [[ -n $title_key ]] || title_key='__bare__'

  PARSE_RESULT=("$pos" "$use_kind" "$use_val" "$key" "$use_num" "$album_key" "$album_prefix" "$volume_num" "$book_num" "$part_num" "$chapter_num" "$section_num" "$true_edge" "$title_key")
}

compute_renamed_path() {
  local filepath=$1 pad_width=$2 prefix_val=$3 title_key=$4
  local fname dir base ext kind prefix newbase
  fname=${filepath:t}
  dir=${filepath:h}
  base=$(audio_basename "$fname")
  ext=${fname##*.}
  [[ $fname == *.* ]] || ext=

  if parse_audio_name "$base"; then
    kind=$PARSE_RESULT[2]
    [[ -z $title_key ]] && title_key=$PARSE_RESULT[14]
    [[ -z $title_key || $title_key == __bare__ ]] && title_key=$PARSE_RESULT[4]
  elif [[ -n $title_key && $title_key != __bare__ ]]; then
    kind=arabic
  else
    return 1
  fi
  prefix=$(format_leading_numeral "$kind" "$prefix_val" "$pad_width") || return 1

  if [[ $title_key == __bare__ ]]; then newbase=$prefix
  else newbase="${prefix} ${title_key}"; fi
  if [[ -n $ext ]]; then
    print -r -- "${dir}/${newbase}.${ext}"
  else
    print -r -- "${dir}/${newbase}"
  fi
}

arabic_pad_width() {
  local max_val=$1
  local w=${#max_val}
  (( w < 2 )) && w=2
  print -rn -- "$w"
}

print_series_block() {
  local kind=$1 key=$2 block=$3 kind_label line path rest num_disp
  [[ $kind == arabic ]] && kind_label=Arabic || kind_label=Roman
  print "Series (${kind_label}): ${key//__bare__/"(no title text)"}"
  for line in ${(f)block}; do
    [[ -z $line ]] && continue
    path=${line%%$'\t'*}
    num_disp=${line#*$'\t'}; num_disp=${num_disp#*$'\t'}
    printf '  [%s] %s\n' "$num_disp" "$path"
  done
  print ''
}

print_section_from_assoc() {
  local title=$1; local -A section; shift; section=("$@")
  print ''; print "=== $title ==="
  (( ${#section} )) || { print '  (none)'; return 0; }
  print ''
  local gkey block kind key one_run run_text
  for gkey block in ${(kv)section}; do
    kind=${${gkey#*|}%%|*}; key=${gkey#*|}; key=${key#*|}
    run_text=$block
    while [[ -n $run_text ]]; do
      one_run=${run_text%%$'\n\n'*}
      [[ $one_run == "$run_text" ]] && run_text='' || run_text=${run_text#*$'\n\n'}
      [[ -z ${one_run//[$'\t\n ']/} ]] && continue
      print_series_block "$kind" "$key" "$one_run"
    done
  done
}

# Process each consecutive run in a group. Callback receives:
#   save_series_run <pos> <kind> <block_text>
#   collect_rename <pos> <kind> <pad_width> <entry> ...
clean_album_title_prefix() {
  local p=$1 ext
  for ext in "${AUDIO_EXTS[@]}"; do
    if [[ $p == *[_\ -]${ext} ]]; then
      p=${p%[_\ -]${ext}}
    fi
  done
  print -r -- "$p"
}

resolve_title_key() {
  local album_prefix=$1 volume_num=$2 book_num=$3 part_num=$4 chapter_num=$5 section_num=$6
  local synth_titles=${7:-0} title_stem=${8:-}
  local label= album_title=
  if [[ -n $title_stem && $title_stem != __bare__ ]]; then
    print -r -- "$title_stem"
    return 0
  fi
  album_title=$(clean_album_title_prefix "$album_prefix")
  if (( synth_titles || SYNTH_SEQUENCE_MODE )); then
    [[ -n $album_title ]] && print -r -- "$album_title" || print -r -- '__bare__'
    return 0
  fi
  label=$(structure_part_label "$volume_num" "$book_num" "$part_num" "$chapter_num" "$section_num")
  if [[ -n $label && -n $album_title ]]; then
    print -r -- "${album_title} ${label}"
  elif [[ -n $label ]]; then
    print -r -- "$label"
  elif [[ -n $album_title ]]; then
    print -r -- "$album_title"
  else
    print -r -- '__bare__'
  fi
}

# End/begin numerals with offset when a new Part restarts suffix numbering.
album_prefix_plan() {
  local -a run=("$@")
  local -a fields prefix_vals=()
  local entry offset=0 prev_part='' max_in_part=0
  local part_num track_val prefix_val

  for entry in "${run[@]}"; do
    fields=("${(@ps:\t:)entry}")
    part_num=$fields[6]
    track_val=$fields[2]
    if [[ -n $prev_part && $part_num != $prev_part ]]; then
      if (( track_val <= max_in_part )); then
        offset=$(( offset + max_in_part ))
      fi
      max_in_part=0
    fi
    prefix_val=$(( offset + track_val ))
    prefix_vals+=("$prefix_val")
    (( track_val > max_in_part )) && max_in_part=$track_val
    prev_part=$part_num
  done
  PLAN_REPLY=("${prefix_vals[@]}")
}

# True when multiple Part/Chapter/Section levels appear in one album run.
structure_levels_mixed() {
  local -a run=("$@") fields entry
  local -i has_volume=0 has_book=0 has_part=0 has_chapter=0 has_section=0
  for entry in "${run[@]}"; do
    fields=("${(@ps:\t:)entry}")
    (( fields[4] )) && has_volume=1
    (( fields[5] )) && has_book=1
    (( fields[6] )) && has_part=1
    (( fields[7] )) && has_chapter=1
    (( fields[8] )) && has_section=1
  done
  (( (has_volume + has_book + has_part + has_chapter + has_section) > 1 ))
}

# No overall track numerals: single structure level uses its number (Chapter 100 → 100);
# mixed Part+Section (etc.) assigns global 1..N in sort order.
synth_prefix_plan() {
  local -a run=("$@")
  local -a prefix_vals=() fields
  local entry part_num chapter_num section_num seq_val i=1

  if structure_levels_mixed "${run[@]}"; then
    for entry in "${run[@]}"; do
      prefix_vals+=("$i")
      (( i++ ))
    done
  else
    for entry in "${run[@]}"; do
      fields=("${(@ps:\t:)entry}")
      part_num=$fields[6]
      chapter_num=$fields[7]
      section_num=$fields[8]
      if (( chapter_num )); then seq_val=$chapter_num
      elif (( section_num )); then seq_val=$section_num
      elif (( part_num )); then seq_val=$part_num
      else seq_val=$i
      fi
      prefix_vals+=("$seq_val")
      (( i++ ))
    done
  fi
  PLAN_REPLY=("${prefix_vals[@]}")
}

# True when the directory contains exactly one audio file (any extension we scan).
is_single_audio_dir() {
  local dir=$1
  (( ${SCAN_DIR_AUDIO_COUNT[$dir]:-0} == 1 ))
}

# Album runs normally need 2+ files; a lone parseable file in a one-audio folder is OK.
run_eligible_for_processing() {
  local -a run=("$@")
  local filepath
  (( ${#run} >= 2 )) && return 0
  (( ${#run} == 1 )) || return 1
  filepath=${run[1]%%$'\t'*}
  is_single_audio_dir "${filepath:h}"
}

# Structure-only names use Part/Chapter/Section for prefix; edge numerals use track values.
use_synth_prefix_plan() {
  local pos=$1
  (( SYNTH_SEQUENCE_MODE )) && return 0
  [[ $pos == structure ]]
}

flush_run_for_report() {
  local pos=$1 kind=$2 gkey=$3
  shift 3
  local -a run=("$@") out=() prefix_vals
  local entry pad_width display idx=1 title_key
  local -a fields
  run_eligible_for_processing "${run[@]}" || return 0
  if use_synth_prefix_plan "$pos"; then
    synth_prefix_plan "${run[@]}"
  else
    album_prefix_plan "${run[@]}"
  fi
  prefix_vals=("${PLAN_REPLY[@]}")
  if [[ $kind == arabic ]]; then
    pad_width=$(arabic_pad_width "${prefix_vals[-1]}")
  else
    pad_width=0
  fi
  for entry in "${run[@]}"; do
    fields=("${(@ps:\t:)entry}")
    display=$(format_leading_numeral "$kind" "${prefix_vals[idx]}" "$pad_width")
    out+=("${fields[1]}"$'\t'"${prefix_vals[idx]}"$'\t'"$display")
    (( idx++ ))
  done
  local album_key=${${gkey#*|}#*|}
  if (( ${#SCAN_CREDITS} )); then
    out+=("${(@f)$(credits_report_lines "$kind" "$pad_width" "${prefix_vals[-1]}" "$album_key")}")
    out=("${(@f)$(printf '%s\n' "${out[@]}" | LC_ALL=C sort -t '	' -k2,2n)}")
  fi
  save_series_run "$pos" "$kind" "$gkey" "$(printf '%s\n' "${out[@]}")"
}

flush_run_for_rename() {
  local kind=$1 pos=$2
  shift 2
  local -a run=("$@") prefix_vals
  local entry pad_width idx=1 title_key
  local -a fields
  run_eligible_for_processing "${run[@]}" || return 0
  if use_synth_prefix_plan "$pos"; then
    synth_prefix_plan "${run[@]}"
  else
    album_prefix_plan "${run[@]}"
  fi
  prefix_vals=("${PLAN_REPLY[@]}")
  if [[ $kind == arabic ]]; then
    pad_width=$(arabic_pad_width "${prefix_vals[-1]}")
  else
    pad_width=0
  fi
  fields=("${(@ps:\t:)run[1]}")
  local album_key=${fields[9]} synth_titles=0
  use_synth_prefix_plan "$pos" && synth_titles=1
  for entry in "${run[@]}"; do
    fields=("${(@ps:\t:)entry}")
    if [[ $pos == end && -n ${fields[10]} && ${fields[10]} != __bare__ && ${fields[10]} != ${fields[9]} ]]; then
      title_key=${fields[10]}
    elif [[ $pos == begin && -n ${fields[10]} && ${fields[10]} != __bare__ ]]; then
      title_key=${fields[10]}
    else
      title_key=$(resolve_title_key "${fields[9]}" "${fields[4]}" "${fields[5]}" "${fields[6]}" "${fields[7]}" "${fields[8]}" $synth_titles)
    fi
    collect_rename_entry "$pad_width" "${prefix_vals[idx]}" "${fields[1]}" "$title_key"
    (( idx++ ))
  done
  plan_credits_renames "$kind" "$pad_width" "${prefix_vals[-1]}" "$album_key"
}

handle_group_runs() {
  local mode=$1 gkey=$2 entries=$3
  local pos=${gkey%%|*} kind=${${gkey#*|}%%|*}
  local -a lines sort_cmd

  lines=("${(@f)entries}")
  lines=(${lines:#''})
  run_eligible_for_processing "${lines[@]}" || return 0
  if (( SYNTH_SEQUENCE_MODE || pos == structure )); then
    sort_cmd=(sort -t '	' -k4,4n -k5,5n -k6,6n -k7,7n -k8,8n)
  else
    sort_cmd=(sort -t '	' -k4,4n -k5,5n -k6,6n -k7,7n -k8,8n -k2,2n)
  fi
  lines=("${(@f)$(printf '%s\n' "${lines[@]}" | LC_ALL=C "${sort_cmd[@]}")}")

  if [[ $mode == do_rename ]]; then
    flush_run_for_rename "$kind" "$pos" "${lines[@]}"
  else
    flush_run_for_report "$pos" "$kind" "$gkey" "${lines[@]}"
  fi
}

# Sets CREDITS_PARSE_ROLE (opening|end) and CREDITS_PARSE_TITLE; returns 0 when matched.
parse_credits_file() {
  local base=$1
  CREDITS_PARSE_ROLE=; CREDITS_PARSE_TITLE=
  if [[ $base =~ '(^|.*[[:space:]_-])[Oo]pening[ _.-]*[Cc]redits?[ _.-]+(.+)' ]]; then
    CREDITS_PARSE_ROLE=opening
    CREDITS_PARSE_TITLE=$(strip_edge_seps "$match[2]")
  elif [[ $base =~ '(^|.*[[:space:]_-])[Ee]nd[ _.-]*[Cc]redits?[ _.-]+(.+)' ]]; then
    CREDITS_PARSE_ROLE=end
    CREDITS_PARSE_TITLE=$(strip_edge_seps "$match[2]")
  elif [[ $base =~ '(^|.*[[:space:]_-])[Cc]losing[ _.-]*[Cc]redits?[ _.-]+(.+)' ]]; then
    CREDITS_PARSE_ROLE=end
    CREDITS_PARSE_TITLE=$(strip_edge_seps "$match[2]")
  elif [[ $base =~ '^[Oo]pening[ _.-]*[Cc]redits?[ _.-]*(.*)' ]]; then
    CREDITS_PARSE_ROLE=opening
    CREDITS_PARSE_TITLE=$(strip_edge_seps "$match[1]")
  elif [[ $base =~ '^[Ee]nd[ _.-]*[Cc]redits?[ _.-]*(.*)' ]]; then
    CREDITS_PARSE_ROLE=end
    CREDITS_PARSE_TITLE=$(strip_edge_seps "$match[1]")
  elif [[ $base =~ '^[Cc]losing[ _.-]*[Cc]redits?[ _.-]*(.*)' ]]; then
    CREDITS_PARSE_ROLE=end
    CREDITS_PARSE_TITLE=$(strip_edge_seps "$match[1]")
  else
    return 1
  fi
  [[ -n $CREDITS_PARSE_TITLE ]] || return 1
  return 0
}

credits_album_matches() {
  local credits_title=$1 album_key=$2
  local lc=${(L)credits_title} lk=${(L)album_key}
  [[ $lc == $lk ]] && return 0
  [[ $lk == *$lc ]] && return 0
  [[ $lc == *$lk ]] && return 0
  return 1
}

# Title body for a credits rename: leading credits label strips to suffix only;
# mid-title credits (album - Opening Credits - …) keep the full stem after the track numeral.
credits_file_title_key() {
  local base=$1 stem=$base
  if [[ $base =~ '^([0-9]+)[._ -]+(.+)' ]]; then
    stem=$match[2]
  fi
  if [[ $stem =~ '^[Oo]pening[ _.-]*[Cc]redits?[ _.-]+(.+)' ]] ||
     [[ $stem =~ '^[Ee]nd[ _.-]*[Cc]redits?[ _.-]+(.+)' ]] ||
     [[ $stem =~ '^[Cc]losing[ _.-]*[Cc]redits?[ _.-]+(.+)' ]]; then
    print -r -- "$(strip_edge_seps "$match[1]")"
  else
    print -r -- "$stem"
  fi
}

# Append opening (00) and end (max+1) credit renames for a planned album run.
plan_credits_renames() {
  local kind=$1 pad_width=$2 max_prefix=$3 album_key=$4
  local entry filepath role title prefix_val title_key base
  typeset -gA CREDITS_PLANNED

  for entry in "${SCAN_CREDITS[@]}"; do
    filepath=${entry%%$'\t'*}
    role=${${entry#*$'\t'}%%$'\t'*}
    title=${entry#*$'\t'}; title=${title#*$'\t'}
    [[ -n ${CREDITS_PLANNED[$filepath]:-} ]] && continue
    credits_album_matches "$title" "$album_key" || continue
    if [[ $role == opening ]]; then prefix_val=0
    else prefix_val=$(( max_prefix + 1 ))
    fi
    base=$(audio_basename "${filepath:t}")
    title_key=$(credits_file_title_key "$base")
    collect_rename_entry "$pad_width" "$prefix_val" "$filepath" "$title_key"
    CREDITS_PLANNED[$filepath]=1
  done
}

# Report lines: path<TAB>prefix_val<TAB>display (sorted with chapter lines by prefix_val).
credits_report_lines() {
  local kind=$1 pad_width=$2 max_prefix=$3 album_key=$4
  local entry filepath role title prefix_val display
  local -a lines=()

  for entry in "${SCAN_CREDITS[@]}"; do
    filepath=${entry%%$'\t'*}
    role=${${entry#*$'\t'}%%$'\t'*}
    title=${entry#*$'\t'}; title=${title#*$'\t'}
    credits_album_matches "$title" "$album_key" || continue
    if [[ $role == opening ]]; then prefix_val=0
    else prefix_val=$(( max_prefix + 1 ))
    fi
    display=$(format_leading_numeral "$kind" "$prefix_val" "$pad_width")
    lines+=("${filepath}"$'\t'"${prefix_val}"$'\t'"$display")
  done
  if (( ${#lines} )); then
    printf '%s\n' "${lines[@]}"
  fi
}

typeset -gA SCAN_GROUPS
typeset -gA SCAN_DIR_AUDIO_COUNT
typeset -gi SYNTH_SEQUENCE_MODE=0

scan_directory() {
  local target_dir=$1
  local find_args=(-type f '(') ext filepath fname base
  typeset -gA SCAN_GROUPS
  typeset -gA SCAN_DIR_AUDIO_COUNT
  typeset -gi SYNTH_SEQUENCE_MODE=0
  typeset -ga SCAN_CREDITS
  local -i scan_total=0 scan_true_edge=0 scan_structure=0
  SCAN_GROUPS=()
  SCAN_DIR_AUDIO_COUNT=()
  SCAN_CREDITS=()
  find_args=(-type f '(')
  for ext in "${AUDIO_EXTS[@]}"; do
    (( ${#find_args} > 3 )) && find_args+=(-o)
    find_args+=(-iname "*.${ext}")
  done
  find_args+=(')' -print0)
  while IFS= read -r -d '' filepath; do
    (( SCAN_DIR_AUDIO_COUNT[$filepath:h]++ ))
    fname=${filepath:t}
    base=$(audio_basename "$fname")
    local credits_probe=$base
    if [[ $base =~ '^([0-9]+)[._ -]+(.+)' ]]; then
      credits_probe=$match[2]
    fi
    if parse_credits_file "$credits_probe" || parse_credits_file "$base"; then
      SCAN_CREDITS+=("${filepath}"$'\t'"${CREDITS_PARSE_ROLE}"$'\t'"${CREDITS_PARSE_TITLE}")
      continue
    fi
    if ! parse_audio_name "$base"; then
      continue
    fi
    (( scan_total++ ))
    (( PARSE_RESULT[13] )) && (( scan_true_edge++ ))
    (( PARSE_RESULT[8] || PARSE_RESULT[9] || PARSE_RESULT[10] || PARSE_RESULT[11] || PARSE_RESULT[12] )) && (( scan_structure++ ))
    gkey="${PARSE_RESULT[1]}|${PARSE_RESULT[2]}|${PARSE_RESULT[6]}"
    append_scan_entry "$gkey" \
      "$filepath" "${PARSE_RESULT[3]}" "${PARSE_RESULT[5]}" \
      "${PARSE_RESULT[8]}" "${PARSE_RESULT[9]}" "${PARSE_RESULT[10]}" \
      "${PARSE_RESULT[11]}" "${PARSE_RESULT[12]}" \
      "${PARSE_RESULT[7]}" "${PARSE_RESULT[14]}"
  done < <(command find "$target_dir" "${find_args[@]}" 2>/dev/null)
  regroup_shared_title_albums
  if (( scan_total >= 2 && scan_true_edge == 0 && scan_structure == scan_total )); then
    SYNTH_SEQUENCE_MODE=1
  fi
}

typeset -A REPORT_BEGIN REPORT_END REPORT_BOTH

save_series_run() {
  local pos=$1 kind=$2 gkey=$3 block=$4
  case $pos in
    begin) REPORT_BEGIN[$gkey]+="${block}"$'\n' ;;
    end|structure) REPORT_END[$gkey]+="${block}"$'\n' ;;
    both)  REPORT_BOTH[$gkey]+="${block}"$'\n' ;;
  esac
}

typeset -ga PLANNED_RENAMES

collect_rename_entry() {
  local pad_width=$1 prefix_val=$2 oldpath=$3 title_key=$4 newpath
  newpath=$(compute_renamed_path "$oldpath" "$pad_width" "$prefix_val" "$title_key") || return 0
  [[ "$oldpath" == "$newpath" ]] && return 0
  PLANNED_RENAMES+=("${oldpath}"$'\t'"${newpath}")
}

build_m3u_basename_map() {
  typeset -gA M3U_BASENAME_MAP
  local entry oldpath newpath
  M3U_BASENAME_MAP=()
  for entry in "${PLANNED_RENAMES[@]}"; do
    oldpath=${entry%%$'\t'*}
    newpath=${entry#*$'\t'}
    M3U_BASENAME_MAP[$(trim_edge_spaces ${oldpath:t})]=${newpath:t}
  done
}

# Rewrite one playlist path line; print unchanged non-path lines as-is.
m3u_transform_line() {
  local line=$1 stripped trimmed filebase newbase dirpart
  stripped=${line%%$'\r'}
  trimmed=$stripped
  if [[ -z ${trimmed//[[:space:]]/} || ${trimmed[1]} == '#' ]]; then
    print -r -- "$stripped"
    return 0
  fi
  filebase=$(trim_edge_spaces ${trimmed:t})
  newbase=${M3U_BASENAME_MAP[$filebase]}
  if [[ -z $newbase ]]; then
    print -r -- "$stripped"
    return 0
  fi
  if [[ $trimmed == */* ]]; then
    dirpart=${trimmed:h}
    print -r -- "${dirpart}/${newbase}"
  else
    print -r -- "$newbase"
  fi
}

# mode: plan (print changes) or apply (write files). Returns number of lines changed.
update_m3u_playlists() {
  local target_dir=$1 mode=$2
  local m3u filepath tmpfile line new_line changes=0
  local -a m3u_files

  build_m3u_basename_map
  (( ${#M3U_BASENAME_MAP} )) || return 0
  m3u_files=("$target_dir"/*.m3u(N))
  (( ${#m3u_files} )) || return 0

  for m3u in "${m3u_files[@]}"; do
    changes=0
    if [[ $mode == plan ]]; then
      print -r "$m3u"
      while IFS= read -r line || [[ -n $line ]]; do
        new_line=$(m3u_transform_line "$line")
        if [[ $new_line != "${line%%$'\r'}" ]]; then
          print -r "  ${line%%$'\r'}"
          print -r "  -> $new_line"
          (( changes++ ))
        fi
      done < "$m3u"
      (( changes )) || print -r '  (no filename lines matched planned renames)'
    else
      tmpfile="${m3u}.renumber-tmp"
      while IFS= read -r line || [[ -n $line ]]; do
        new_line=$(m3u_transform_line "$line")
        [[ $new_line != "${line%%$'\r'}" ]] && (( changes++ ))
        print -r -- "$new_line"
      done < "$m3u" > "$tmpfile" || return 1
      if (( changes )); then
        mv -- "$tmpfile" "$m3u" || return 1
        print -r "Updated playlist ($changes lines): $m3u"
      else
        rm -f -- "$tmpfile"
      fi
    fi
  done
  return 0
}

print_report() {
  local target_dir=$1 gkey entries
  REPORT_BEGIN=(); REPORT_END=(); REPORT_BOTH=()
  scan_directory "$target_dir"
  for gkey entries in ${(kv)SCAN_GROUPS}; do
    handle_group_runs report "$gkey" "$entries"
  done
  print -r "Numbered audio sequences in: $target_dir"
  print -r "Extensions: ${(j:, :)AUDIO_EXTS}"
  if (( SYNTH_SEQUENCE_MODE )); then
    print -r "(No overall track numerals; sequence synthesized from Part/Chapter/Section order; 2+ files per album, or 1 file when that is the only audio in its folder)"
    (( ${#SCAN_CREDITS} )) && print -r "(Opening/End Credits in the same album folder are numbered 00 and last+1)"
  else
    print -r "(End/begin numerals set track order; Part/Chapter restarts continue the album sequence; 2+ files per album, or 1 file when that is the only audio in its folder; end-primary files with shared title prefix/suffix are grouped)"
  fi
  print_section_from_assoc "Begin with numerals" ${(kv)REPORT_BEGIN}
  print_section_from_assoc "End with numerals" ${(kv)REPORT_END}
  print_section_from_assoc "Both begin and end with numerals" ${(kv)REPORT_BOTH}
  if (( ! ${#REPORT_BEGIN} && ! ${#REPORT_END} && ! ${#REPORT_BOTH} )); then
    print -r 'No sequential numbered audio series found.'
  fi
}

# Apply renames with mv (exact paths; zmv treats () and other glob chars in names as patterns).
# Resolve source path when stored path differs slightly (e.g. edge-space normalization).
resolve_apply_source_path() {
  local oldpath=$1 olddir=$2
  local want_base f actual_base

  [[ -e "$oldpath" ]] && { print -r -- "$oldpath"; return 0 }
  want_base=$(audio_basename "${oldpath:t}")
  for f in "$olddir"/*(N); do
    [[ -f "$f" ]] || continue
    actual_base=$(audio_basename "${f:t}")
    [[ "$actual_base" == "$want_base" ]] && { print -r -- "$f"; return 0 }
  done
  return 1
}

apply_planned_renames() {
  local -a planned=("${@}")
  local -a phase2=()
  local entry oldpath newpath olddir resolved tmppath i
  local -i applied=0 skipped=0

  # Phase 1: source → unique temp name in the same directory.
  i=0
  for entry in "${planned[@]}"; do
    oldpath=${entry%%$'\t'*}
    newpath=${entry#*$'\t'}
    olddir=${oldpath:h}
    resolved=$(resolve_apply_source_path "$oldpath" "$olddir") || {
      print -u2 "SKIP (missing): $oldpath"
      (( skipped++ ))
      continue
    }
    oldpath=$resolved
    tmppath="${olddir}/.renumber-tmp-${i}"
    if [[ -e "$tmppath" ]]; then
      print -u2 "SKIP (temp exists): $tmppath"
      (( skipped++ ))
      continue
    fi
    mv -- "$oldpath" "$tmppath" || return 1
    phase2+=("${tmppath}"$'\t'"${newpath}")
    (( i++ ))
  done

  # Phase 2: temp → final destination.
  for entry in "${phase2[@]}"; do
    oldpath=${entry%%$'\t'*}
    newpath=${entry#*$'\t'}
    [[ -e "$oldpath" ]] || continue
    if [[ -e "$newpath" && "$oldpath" != "$newpath" ]]; then
      print -u2 "SKIP (target exists): $newpath"
      (( skipped++ ))
      continue
    fi
    mv -- "$oldpath" "$newpath" || return 1
    (( applied++ ))
  done
  if (( skipped )); then
    print -u2 "Renamed ${applied} file(s); skipped ${skipped} (see messages above)."
  fi
  return 0
}

run_renames() {
  local target_dir=$1 apply=$2 entry oldpath newpath
  typeset -ga PLANNED_RENAMES
  typeset -gA CREDITS_PLANNED
  PLANNED_RENAMES=()
  CREDITS_PLANNED=()
  scan_directory "$target_dir"
  for gkey entries in ${(kv)SCAN_GROUPS}; do
    handle_group_runs do_rename "$gkey" "$entries"
  done
  if (( ! ${#PLANNED_RENAMES} )); then
    print -r "No renames planned under: $target_dir"
    return 0
  fi
  print -r "Planned renames (${#PLANNED_RENAMES}) under: $target_dir"
  print -r "(Arabic → zero-padded prefix; Roman → no leading zeros)"
  print ''
  for entry in "${PLANNED_RENAMES[@]}"; do
    oldpath=${entry%%$'\t'*}; newpath=${entry#*$'\t'}
    print -r "$oldpath"; print -r "  -> $newpath"
  done
  if (( ${#PLANNED_RENAMES} )); then
    local -a m3u_check=("$target_dir"/*.m3u(N))
    if (( ${#m3u_check} )); then
      print ''
      print -r 'Planned playlist updates:'
      update_m3u_playlists "$target_dir" plan
    fi
  fi
  if [[ -z $apply ]]; then
    print ''
    print -r 'Dry run only. Pass --apply to rename files.'
    return 0
  fi
  print ''
  print -r 'Applying renames...'
  apply_planned_renames "${PLANNED_RENAMES[@]}" || {
    print -u2 'Rename failed (partial changes may remain as .renumber-tmp-* files).'
    return 1
  }
  update_m3u_playlists "$target_dir" apply || {
    print -u2 'Audio files renamed, but playlist update failed.'
    return 1
  }
  print -r 'Done.'
}

usage() {
  print -u2 "Usage: ${0:t} [--rename] [--apply] [directory]"
  exit 2
}

main() {
  local rename= apply= target_dir=$PWD arg
  for arg in "$@"; do
    case $arg in
      --rename) rename=1 ;;
      --apply)  apply=1 ;;
      -h|--help) usage ;;
      *)
        if [[ -d $arg ]]; then target_dir=$arg
        else print -u2 "Not a directory: $arg"; return 1; fi ;;
    esac
  done
  target_dir=${target_dir:a}
  if [[ -n $rename ]]; then run_renames "$target_dir" "$apply"
  else print_report "$target_dir"; fi
}

# Run only when executed directly, not when sourced (funcfiletrace is set while sourcing).
if [[ ${0:t} == find-numbered-audio.zsh && -z ${funcfiletrace[1]} ]]; then
  main "$@"
fi
