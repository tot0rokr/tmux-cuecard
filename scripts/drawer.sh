#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
shopt -s nullglob

pane_id=$(current_pane_id)
window_id=$(current_window_id)
dir=$(window_dir "$window_id")
input=$(input_mode) || exit 1

cards=()
titles=()
dates=()
selected=0
top=0
footer=(' Enter pick   p pop   i new' ' e edit   d delete   q quit'
  ' J/K move   m to window')
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
  update_count "$window_id"
}

# A drawer on another client can rename or remove cards of this window, so
# a key that touches files first reloads them and finds the selected card
# again by <created>.<rand>, which a move keeps. Fails if the card is gone.
refresh_selected() {
  local id i
  parse_card "${cards[selected]}"
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

# Splits $1 at the widest prefix that fits in $2 terminal columns, counting
# East Asian wide characters and emoji as two columns.
# Sets FIT, FIT_COLS and REST.
fit() {
  local text=$1 max=$2 len=${#1} i=0 used=0 code w
  while (( i < len )); do
    printf -v code '%d' "'${text:i:1}"
    w=1
    if (( (code >= 0x1100 && code <= 0x115F) || (code >= 0x2E80 && code <= 0xA4CF) ||
          (code >= 0xAC00 && code <= 0xD7A3) || (code >= 0xF900 && code <= 0xFAFF) ||
          (code >= 0xFE30 && code <= 0xFE4F) || (code >= 0xFF00 && code <= 0xFF60) ||
          (code >= 0xFFE0 && code <= 0xFFE6) || (code >= 0x1F300 && code <= 0x1F64F) ||
          (code >= 0x1F900 && code <= 0x1F9FF) || (code >= 0x20000 && code <= 0x3FFFD) )); then
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
# still fits. Sets LIST_H and FOOT_H.
layout() {
  local rows=$1 max_list
  FOOT_H=$(( rows - 4 ))
  (( FOOT_H < 2 )) && FOOT_H=2
  (( FOOT_H > $2 )) && FOOT_H=$2
  (( FOOT_H > rows - 2 )) && FOOT_H=$(( rows - 2 ))
  max_list=$(( (rows - FOOT_H - 2) / 2 ))
  LIST_H=$3
  (( LIST_H > max_list )) && LIST_H=$max_list
  (( LIST_H < 1 )) && LIST_H=1
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

# Draws what goes under a list of $3 rows in a drawer of $1 rows and $2
# columns: a separator, the preview of card $4 and, under another
# separator, the footer lines $5...
draw_below_list() {
  local rows=$1 cols=$2 list_h=$3 card=$4 row sep line lines preview_bottom
  shift 4
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

draw() {
  local rows cols count row i
  read -r rows cols < <(stty size)
  count=${#cards[@]}
  layout "$rows" ${#footer[@]} "$count"
  scroll "$top" "$selected" "$count" "$LIST_H"
  top=$TOP

  out=$'\e[H\e[2J'
  if (( count == 0 )); then
    goto 1
    out+=$'\e[2m (empty) press i to add\e[0m'
  fi
  for (( row = 0; row < LIST_H && top + row < count; row++ )); do
    i=$(( top + row ))
    draw_row $(( row + 1 )) "$cols" " ${titles[i]}" " ${dates[i]} " \
      $(( i == selected ))
  done
  draw_below_list "$rows" "$cols" "$LIST_H" "${cards[selected]-}" \
    "${footer[@]:0:FOOT_H}"
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
  local card=${cards[selected]} lines
  mapfile -t lines < "$card"
  if [[ $input == box ]] && (( ${#lines[@]} <= 1 )); then
    read_box 'Edit card (Enter saves, empty deletes)' "${lines[0]-}" || return
    printf '%s\n' "$BOX_TEXT" > "$card"
  else
    edit_in_vim "$card"
  fi
  has_text "$card" || rm -f "$card"
}

# A new card goes to the bottom, so the selection follows it there.
insert_card() {
  local count=${#cards[@]}
  with_terminal_restored "$CURRENT_DIR/insert.sh"
  load_cards
  (( ${#cards[@]} > count )) && selected=$(( ${#cards[@]} - 1 ))
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
      m)
        move_selected_to_window
        ;;
      '')
        (( ${#cards[@]} )) && refresh_selected || continue
        paste_selected
        exit 0
        ;;
      p)
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
        (( ${#cards[@]} )) && refresh_selected || continue
        rm -f "${cards[selected]}"
        load_cards
        ;;
      q | $'\e')
        exit 0
        ;;
    esac
  done
}

main
