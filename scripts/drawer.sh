#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
shopt -s nullglob

pane_id=$(current_pane_id)
window_id=$(current_window_id)
input=$(input_mode) || exit 1

# The drawer shows one of two views: the cards of this window, or the saved
# cards that every window shares. It opens on the window view, and each view
# keeps its own selection and scroll while the drawer is open.
view=window
declare -A view_dir=([window]="$(window_dir "$window_id")"
  [saved]="$(saved_dir)")
declare -A view_selected=([window]=0 [saved]=0)
declare -A view_top=([window]=0 [saved]=0)
declare -A view_card=()
dir=${view_dir[window]}

cards=()
titles=()
dates=()
selected=0
top=0
window_footer=(' Enter pick   p pop   i new' ' e edit   d delete   q quit'
  ' c save   Tab saved' ' J/K move   m to window')
saved_footer=(' Enter pick   c to window' ' i new   e edit   q quit'
  ' J/K move   Tab window' ' d delete')
window_empty=(' (empty) press i to add')
saved_empty=(' (empty) press i to add' ' or c in the window view')
# Shown in place of the first footer line until the next key.
notice=

windows=()
window_labels=()
window_counts=()
pick=0
pick_top=0
picker_footer=(' Enter move   q cancel')

sanitize() {
  local text=${1//$'\t'/    }
  SANITIZED=${text//[[:cntrl:]]/}
}

# Cards in stack order, top first. Titles are the first non-blank line of
# each card.
load_cards() {
  local file line date
  cards=()
  titles=()
  dates=()
  for file in "$dir"/*; do
    line=
    while IFS= read -r line; do
      [[ $line == *[![:space:]]* ]] && break
    done < "$file"
    sanitize "$line"
    parse_card "$file"
    printf -v date '%(%m-%d %H:%M)T' $(( 10#$CARD_CREATED ))
    cards+=("$file")
    titles+=("$SANITIZED")
    dates+=("$date")
  done
  (( selected >= ${#cards[@]} )) && selected=$(( ${#cards[@]} - 1 ))
  (( selected < 0 )) && selected=0
  [[ $view == saved ]] || update_count "$window_id"
}

# A drawer on another client, or for the saved cards one on another tmux
# server, can rename or remove cards at any time. So a key that touches
# files first reloads them and finds the selected card, or card $1, again
# by <created>.<rand>, which a move keeps. Fails if the card is gone.
refresh_selected() {
  local id i
  parse_card "${1-${cards[selected]}}"
  id=$CARD_CREATED.$CARD_RAND
  load_cards
  for (( i = 0; i < ${#cards[@]}; i++ )); do
    parse_card "${cards[i]}"
    if [[ $CARD_CREATED.$CARD_RAND == "$id" ]]; then
      selected=$i
      return 0
    fi
  done
  return 1
}

# Windows of this tmux server other than $1, each listed once although it
# can be linked into several sessions. Labels are <session>:<index> <name>.
load_windows() {
  local -A seen
  local format id count label
  # No field is empty, since read would merge two tabs into one.
  format=$'#{window_id}\t#{?#{@cuecard-count},#{@cuecard-count},0}\t'
  format+='#{session_name}:#{window_index} #{window_name}'
  windows=()
  window_labels=()
  window_counts=()
  while IFS=$'\t' read -r id count label; do
    [[ $id == "$1" || -n ${seen[$id]-} ]] && continue
    seen[$id]=1
    [[ $count =~ ^[0-9]+$ ]] || count=0
    sanitize "$label"
    windows+=("$id")
    window_labels+=("$SANITIZED")
    window_counts+=("$count")
  done < <(tmux list-windows -a -F "$format")
}

# Code point ranges that terminals draw two columns wide: the East Asian
# Wide and Fullwidth characters of Unicode 15.0, which include emoji such as
# U+2705 and U+1F680, and the few emoji such as U+270C that tmux draws wide
# although Unicode does not. Counting a narrow character as wide only pads
# a row, while the reverse pushes the date off its right edge. Ranges are
# merged across unassigned code points.
wide_ranges=(
  0x1100 0x115F  0x231A 0x231B  0x2329 0x232A  0x23E9 0x23EC  0x23F0 0x23F0
  0x23F3 0x23F3  0x25FD 0x25FE  0x2614 0x2615  0x261D 0x261D  0x2648 0x2653
  0x267F 0x267F  0x2693 0x2693  0x26A1 0x26A1  0x26AA 0x26AB  0x26BD 0x26BE
  0x26C4 0x26C5  0x26CE 0x26CE  0x26D4 0x26D4  0x26EA 0x26EA  0x26F2 0x26F3
  0x26F5 0x26F5  0x26F9 0x26FA  0x26FD 0x26FD  0x2705 0x2705  0x270A 0x270D
  0x2728 0x2728  0x274C 0x274C  0x274E 0x274E  0x2753 0x2755  0x2757 0x2757
  0x2795 0x2797  0x27B0 0x27B0  0x27BF 0x27BF  0x2B1B 0x2B1C  0x2B50 0x2B50
  0x2B55 0x2B55  0x2E80 0x303E  0x3041 0x3247  0x3250 0x4DBF  0x4E00 0xA4C6
  0xA960 0xA97C  0xAC00 0xD7A3  0xF900 0xFAD9  0xFE10 0xFE19  0xFE30 0xFE6B
  0xFF01 0xFF60  0xFFE0 0xFFE6  0x16FE0 0x1B2FB  0x1F004 0x1F004
  0x1F0CF 0x1F0CF  0x1F18E 0x1F18E  0x1F191 0x1F19A  0x1F200 0x1F320
  0x1F32D 0x1F335  0x1F337 0x1F37C  0x1F37E 0x1F393  0x1F3A0 0x1F3CC
  0x1F3CF 0x1F3D3  0x1F3E0 0x1F3F0  0x1F3F4 0x1F3F4  0x1F3F8 0x1F43E
  0x1F440 0x1F440  0x1F442 0x1F4FC  0x1F4FF 0x1F53D  0x1F54B 0x1F54E
  0x1F550 0x1F567  0x1F574 0x1F575  0x1F57A 0x1F57A  0x1F590 0x1F590
  0x1F595 0x1F596  0x1F5A4 0x1F5A4  0x1F5FB 0x1F64F  0x1F680 0x1F6C5
  0x1F6CC 0x1F6CC  0x1F6D0 0x1F6D2  0x1F6D5 0x1F6DF  0x1F6EB 0x1F6EC
  0x1F6F4 0x1F6FC  0x1F7E0 0x1F7F0  0x1F90C 0x1F9FF  0x1FA70 0x1FAF8
  0x20000 0x3FFFD
)

# Succeeds when code point $1 is two columns wide. A binary search keeps
# the cost of a long table low, since fit() asks for every character.
is_wide() {
  local lo=0 hi=$(( ${#wide_ranges[@]} / 2 - 1 )) mid
  while (( lo <= hi )); do
    mid=$(( (lo + hi) / 2 ))
    if (( $1 < wide_ranges[mid * 2] )); then
      hi=$(( mid - 1 ))
    elif (( $1 > wide_ranges[mid * 2 + 1] )); then
      lo=$(( mid + 1 ))
    else
      return 0
    fi
  done
  return 1
}

# Splits $1 at the widest prefix that fits in $2 terminal columns, counting
# East Asian wide characters and emoji as two columns.
# Sets FIT, FIT_COLS and REST.
fit() {
  local text=$1 max=$2 len=${#1} i=0 used=0 code w
  while (( i < len )); do
    printf -v code '%d' "'${text:i:1}"
    # Hangul syllables skip the search, as a Korean card is mostly them.
    w=1
    if (( code >= 0xAC00 && code <= 0xD7A3 )); then
      w=2
    elif (( code >= 0x1100 )) && is_wide "$code"; then
      w=2
    fi
    (( used + w > max )) && break
    used=$(( used + w ))
    i=$(( i + 1 ))
  done
  FIT=${text:0:i}
  FIT_COLS=$used
  REST=${text:i}
}

goto() {
  out+=$'\e['"$1"';1H'
}

# Splits a drawer of $1 rows between a list of $3 items, the preview and a
# footer of $2 lines. A short drawer gives up the last footer lines before
# its only preview row, but keeps the first two as long as the list row
# still fits. A drawer of two rows or fewer has no footer, and one of no
# rows no list row either. Sets LIST_H and FOOT_H.
layout() {
  local rows=$1 max_list
  FOOT_H=$(( rows - 4 ))
  (( FOOT_H < 2 )) && FOOT_H=2
  (( FOOT_H > $2 )) && FOOT_H=$2
  (( FOOT_H > rows - 2 )) && FOOT_H=$(( rows - 2 ))
  (( FOOT_H < 0 )) && FOOT_H=0
  max_list=$(( (rows - FOOT_H - 2) / 2 ))
  LIST_H=$3
  (( LIST_H > max_list )) && LIST_H=$max_list
  (( LIST_H < 1 )) && LIST_H=1
  (( LIST_H > rows )) && LIST_H=$rows
}

# Scrolls a list of $3 items shown in $4 rows from item $1 just enough to
# show item $2. Scrolls back up when items at the bottom are gone, so no
# row is left empty while items above it are hidden. Sets TOP.
scroll() {
  TOP=$1
  (( $2 < TOP )) && TOP=$2
  (( $2 >= TOP + $4 )) && TOP=$(( $2 - $4 + 1 ))
  (( TOP > $3 - $4 )) && TOP=$(( $3 - $4 ))
  (( TOP < 0 )) && TOP=0
}

# Draws $3 at row $1 of a drawer $2 columns wide, with $4 dimmed on the
# right, in reverse video when $5 is 1. A narrow drawer leaves $4 out when
# it would cut $3 down to fewer than 11 columns. A list whose texts on the
# right differ in width passes the widest as $6, so all its rows agree.
draw_row() {
  local cols=$2 text_cols=$2 pad
  (( cols - ${6-${#4}} >= 11 )) && text_cols=$(( cols - ${#4} ))
  fit "$3" "$text_cols"
  printf -v pad '%*s' $(( text_cols - FIT_COLS )) ''
  goto "$1"
  (( $5 )) && out+=$'\e[7m'
  out+="$FIT$pad"
  (( text_cols < cols )) && out+=$'\e[2m'"$4"
  out+=$'\e[0m'
}

# Draws what goes under the first $3 rows (the list, and the tab bar above
# it if any) of a drawer of $1 rows and $2 columns: a separator, the
# preview of card $4 and, under another separator, the footer lines $5...
draw_below_list() {
  local rows=$1 cols=$2 list_h=$3 card=$4 row sep line lines preview_bottom
  shift 4
  # Rows past the bottom would land on the last row, over the list.
  (( list_h < rows )) || return
  printf -v sep '%*s' "$cols" ''
  sep=${sep// /─}

  goto $(( list_h + 1 ))
  out+=$'\e[2m'"$sep"$'\e[0m'
  row=$(( list_h + 2 ))
  preview_bottom=$(( rows - $# - 1 ))
  if [[ -n $card ]]; then
    mapfile -t lines < "$card"
    for line in "${lines[@]}"; do
      sanitize "$line"
      line=$SANITIZED
      while (( row <= preview_bottom )); do
        fit "$line" "$cols"
        goto $row
        out+=$FIT
        row=$(( row + 1 ))
        line=$REST
        [[ -z $line ]] && break
      done
      (( row > preview_bottom )) && break
    done
  fi

  row=$(( preview_bottom + 1 ))
  goto $row
  out+=$'\e[2m'"$sep"
  # The notice is not dimmed, so it stands out from the hints.
  if [[ -n $notice ]] && (( $# )); then
    shift
    row=$(( row + 1 ))
    fit " $notice" "$cols"
    goto $row
    out+=$'\e[0m'"$FIT"$'\e[2m'
  fi
  for line in "$@"; do
    row=$(( row + 1 ))
    fit "$line" "$cols"
    goto $row
    out+=$FIT
  done
  out+=$'\e[0m'
}

# Draws the tab bar on row 1: each view with its number of cards, the
# active one in bold and the other dimmed. Another drawer can change the
# cards of the hidden view, so their number is read from its directory. A
# drawer too narrow for both shows only the active one, since clipping the
# bar could cut away the very view that is open.
draw_tabs() {
  local cols=$1 other=saved files names name gap=
  local -A label
  [[ $view == saved ]] && other=window
  files=("${view_dir[$other]}"/*)
  label[$view]=" $view ${#cards[@]}"
  label[$other]=" $other ${#files[@]}"
  names=(window saved)
  # The labels are ASCII, so their length is their width.
  (( ${#label[window]} + 2 + ${#label[saved]} > cols )) && names=("$view")
  goto 1
  for name in "${names[@]}"; do
    if [[ $name == "$view" ]]; then
      out+=$'\e[1m'
    else
      out+=$'\e[2m'
    fi
    fit "$gap${label[$name]}" "$cols"
    out+=$FIT$'\e[0m'
    cols=$(( cols - FIT_COLS ))
    gap='  '
  done
}

draw() {
  local rows cols count row i footer empty
  read -r rows cols < <(stty size)
  count=${#cards[@]}
  if [[ $view == saved ]]; then
    footer=("${saved_footer[@]}")
    empty=("${saved_empty[@]}")
  else
    footer=("${window_footer[@]}")
    empty=("${window_empty[@]}")
  fi
  # The tab bar keeps the first row even in a short drawer, as it is all
  # that tells the views apart, and the rest is laid out under it.
  layout $(( rows - 1 )) ${#footer[@]} $(( count ? count : ${#empty[@]} ))
  scroll "$top" "$selected" "$count" "$LIST_H"
  top=$TOP

  out=$'\e[H\e[2J'
  draw_tabs "$cols"
  if (( count == 0 )); then
    for (( row = 0; row < LIST_H && row < ${#empty[@]}; row++ )); do
      fit "${empty[row]}" "$cols"
      goto $(( row + 2 ))
      out+=$'\e[2m'"$FIT"$'\e[0m'
    done
  fi
  for (( row = 0; row < LIST_H && top + row < count; row++ )); do
    i=$(( top + row ))
    draw_row $(( row + 2 )) "$cols" " ${titles[i]}" " ${dates[i]} " \
      $(( i == selected ))
  done
  draw_below_list "$rows" "$cols" $(( LIST_H + 1 )) "${cards[selected]-}" \
    "${footer[@]:0:FOOT_H}"
  # A drawer too short for a footer shows the notice on its last row
  # instead, since d in the saved view waits for an answer to it.
  if [[ -n $notice ]] && (( FOOT_H == 0 )); then
    draw_row "$rows" "$cols" " $notice" '' 0
  fi
  printf '%s' "$out"
}

# Draws the window picker with card $1 in the preview. A drawer with room
# for a single list row shows the selected window there instead of the
# heading.
draw_picker() {
  local card=$1 rows cols count head row i sides wide=0
  read -r rows cols < <(stty size)
  count=${#windows[@]}
  layout "$rows" ${#picker_footer[@]} $(( count + 1 ))
  head=1
  (( LIST_H > 1 )) || head=0
  scroll "$pick_top" "$pick" "$count" $(( LIST_H - head ))
  pick_top=$TOP

  # A narrow drawer that hid only the longer counts would make those
  # windows look empty, so the widest count decides for every row.
  sides=()
  for (( i = 0; i < count; i++ )); do
    sides[i]=
    (( window_counts[i] == 1 )) && sides[i]=' 1 card '
    (( window_counts[i] > 1 )) && sides[i]=" ${window_counts[i]} cards "
    (( ${#sides[i]} > wide )) && wide=${#sides[i]}
  done

  out=$'\e[H\e[2J'
  if (( head )); then
    fit ' Move to window' "$cols"
    goto 1
    out+=$'\e[1m'"$FIT"$'\e[0m'
  fi
  for (( row = 0; row < LIST_H - head && pick_top + row < count; row++ )); do
    i=$(( pick_top + row ))
    draw_row $(( head + row + 1 )) "$cols" " ${window_labels[i]}" \
      "${sides[i]}" $(( i == pick )) "$wide"
  done
  draw_below_list "$rows" "$cols" "$LIST_H" "$card" \
    "${picker_footer[@]:0:FOOT_H}"
  printf '%s' "$out"
}

read_key() {
  local rest=
  IFS= read -rsn1 KEY
  if [[ $KEY == $'\e' ]]; then
    IFS= read -rsn2 -t 0.05 rest
    KEY+=$rest
  fi
}

# Lists the windows other than $1 in place of the cards, with card $2 in the
# preview, and sets PICKED to the window the user picks. A popup cannot open
# another popup or choose-tree, so the drawer draws the list itself. Fails
# when the user cancels or there is no other window.
pick_window() {
  load_windows "$1"
  if (( ${#windows[@]} == 0 )); then
    notice='No other window'
    return 1
  fi
  pick=0
  pick_top=0
  while true; do
    draw_picker "$2"
    read_key
    case $KEY in
      $'\e[A' | $'\eOA' | k)
        (( pick > 0 )) && pick=$(( pick - 1 ))
        ;;
      $'\e[B' | $'\eOB' | j)
        (( pick < ${#windows[@]} - 1 )) && pick=$(( pick + 1 ))
        ;;
      '')
        PICKED=${windows[pick]}
        return 0
        ;;
      q | $'\e')
        return 1
        ;;
    esac
  done
}

# Hide the cursor and turn off autowrap so a width misestimate clips a
# line instead of breaking the layout.
prepare_terminal() {
  printf '\e[?25l\e[?7l'
}

restore_terminal() {
  printf '\e[0m\e[?25h\e[?7h'
}

with_terminal_restored() {
  restore_terminal
  "$@"
  prepare_terminal
}

paste_selected() {
  tmux set-buffer -b cuecard -- "$(<"${cards[selected]}")"
  tmux paste-buffer -p -d -b cuecard -t "$pane_id"
}

# The box holds a single line, so multi-line cards always open in vim.
edit_selected() {
  local card=${cards[selected]} lines what=card
  [[ $view == saved ]] && what='saved card'
  mapfile -t lines < "$card"
  if [[ $input == box ]] && (( ${#lines[@]} <= 1 )); then
    read_box "Edit $what (Enter saves, empty deletes)" "${lines[0]-}" ||
      return
    printf '%s\n' "$BOX_TEXT" > "$card"
  else
    edit_in_vim "$card"
  fi
  has_text "$card" || rm -f "$card"
}

# The drawer stays open when its window closes, but the cleanup hook of the
# window has run by then and would never remove a card written after that.
# So a window that is gone takes no new card, and the drawer says so.
window_open() {
  window_exists "$window_id" && return 0
  notice='Window is gone'
  return 1
}

# The selection follows the new card. Another drawer can add or remove cards
# while the input is open, so insert.sh writes the name of the new card to a
# file, rather than the drawer guessing it from the number of cards.
insert_card() {
  local made
  [[ $view == saved ]] || window_open || return
  made=$(mktemp) || return
  with_terminal_restored "$CURRENT_DIR/insert.sh" "$view" "$made"
  if [[ -s $made ]]; then
    refresh_selected "$(<"$made")"
  else
    load_cards
  fi
  rm -f "$made"
}

# Swaps the selected card with the one $1 places away and renames every card
# to consecutive orders. Cards from older versions can share an order, so
# swapping just the two orders would not always move a card.
move_selected() {
  local target card i
  refresh_selected || return
  target=$(( selected + $1 ))
  (( target >= 0 && target < ${#cards[@]} )) || return
  card=${cards[selected]}
  cards[selected]=${cards[target]}
  cards[target]=$card
  for (( i = 0; i < ${#cards[@]}; i++ )); do
    parse_card "${cards[i]}"
    card_name $(( i + 1 )) "$CARD_CREATED" "$CARD_RAND"
    [[ ${cards[i]} == "$dir/$CARD_NAME" ]] || mv "${cards[i]}" "$dir/$CARD_NAME"
  done
  selected=$target
  load_cards
}

# Moves card $1 to the bottom of the stack of window $2. Fails if the window
# is gone: its cleanup hook has already run and would never remove a
# directory written after that. The window can also close while the card
# moves, so it is checked again afterwards and the card goes back.
move_to_window() {
  local target
  target=$(window_dir "$2")
  window_exists "$2" || return 1
  move_card "$1" "$target" || return 1
  if ! window_exists "$2"; then
    mv "$target/$CARD_NAME" "$1"
    rmdir "$target" 2>/dev/null
    return 1
  fi
  update_count "$2"
  return 0
}

# The picker can stay open for a while, so the selected card is looked up
# again right before it moves. The selection keeps its index and lands on
# the card that takes its place.
move_selected_to_window() {
  (( ${#cards[@]} )) && refresh_selected || return
  pick_window "$window_id" "${cards[selected]}" || return
  if ! refresh_selected; then
    notice='Card is gone'
  elif ! move_to_window "${cards[selected]}" "$PICKED"; then
    notice='Window is gone, card kept'
    # Another drawer can remove the card while it moves.
    [[ -e ${cards[selected]} ]] || notice='Card is gone'
  fi
  # Also updates the count of this window.
  load_cards
}

# Copies the selected card to the bottom of the other view as a new card and
# keeps it where it is, so a window card can be saved for later and a saved
# card queued in this window.
copy_selected() {
  local target=saved
  [[ $view == saved ]] && target=window
  (( ${#cards[@]} )) && refresh_selected || return
  [[ $target == saved ]] || window_open || return
  if ! add_card "${cards[selected]}" "${view_dir[$target]}"; then
    notice='Could not copy the card'
    # Another drawer can remove the card while it is copied.
    [[ -e ${cards[selected]} ]] || notice='Card is gone'
    load_cards
  elif [[ $target == window ]]; then
    update_count "$window_id"
    notice='Added to window'
  else
    notice='Saved'
  fi
}

# Saved cards are meant to last, so deleting one takes a second d right after
# the first. Any other key cancels and does nothing else.
confirm_delete() {
  notice='Press d again to delete'
  draw
  read_key
  notice=
  [[ $KEY == d ]]
}

delete_selected() {
  (( ${#cards[@]} )) && refresh_selected || return
  if [[ $view == saved ]]; then
    confirm_delete && refresh_selected || return
  fi
  rm -f "${cards[selected]}"
  load_cards
}

# The cards of the other view can change while it is hidden, so its
# selected card is found again by <created>.<rand>. If that card is gone,
# the selection keeps its place in the list.
switch_view() {
  local next=saved
  [[ $view == saved ]] && next=window
  view_selected[$view]=$selected
  view_top[$view]=$top
  view_card[$view]=${cards[selected]-}
  view=$next
  dir=${view_dir[$view]}
  selected=${view_selected[$view]}
  top=${view_top[$view]}
  if [[ -n ${view_card[$view]-} ]]; then
    refresh_selected "${view_card[$view]}"
  else
    load_cards
  fi
}

main() {
  trap restore_terminal EXIT
  prepare_terminal
  load_cards
  while true; do
    draw
    read_key
    notice=
    case $KEY in
      $'\e[A' | $'\eOA' | k)
        (( selected > 0 )) && selected=$(( selected - 1 ))
        ;;
      $'\e[B' | $'\eOB' | j)
        (( selected < ${#cards[@]} - 1 )) && selected=$(( selected + 1 ))
        ;;
      K)
        move_selected -1
        ;;
      J)
        move_selected 1
        ;;
      $'\t' | $'\e[Z')
        switch_view
        ;;
      m)
        # Saved cards are templates: they are never moved or popped.
        [[ $view == window ]] && move_selected_to_window
        ;;
      c)
        copy_selected
        ;;
      '')
        (( ${#cards[@]} )) && refresh_selected || continue
        paste_selected
        exit 0
        ;;
      p)
        [[ $view == window ]] || continue
        (( ${#cards[@]} )) && refresh_selected || continue
        paste_selected
        rm -f "${cards[selected]}"
        update_count "$window_id"
        exit 0
        ;;
      i)
        insert_card
        ;;
      e)
        (( ${#cards[@]} )) && refresh_selected || continue
        with_terminal_restored edit_selected
        load_cards
        ;;
      d)
        delete_selected
        ;;
      q | $'\e')
        exit 0
        ;;
    esac
  done
}

main
