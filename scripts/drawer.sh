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
footer=(' Enter pick   p pop   i new' ' e edit   d delete   q quit' ' J/K move')

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

draw() {
  local rows cols count max_list list_h row i pad sep line lines preview_bottom
  local title_cols foot_h
  read -r rows cols < <(stty size)
  count=${#cards[@]}

  # A short drawer gives up the last footer lines before its only preview
  # row, but keeps the first two as long as the list row still fits.
  foot_h=$(( rows - 4 ))
  (( foot_h > ${#footer[@]} )) && foot_h=${#footer[@]}
  (( foot_h < 2 )) && foot_h=2
  (( foot_h > rows - 2 )) && foot_h=$(( rows - 2 ))

  max_list=$(( (rows - foot_h - 2) / 2 ))
  list_h=$count
  (( list_h > max_list )) && list_h=$max_list
  (( list_h < 1 )) && list_h=1
  (( selected < top )) && top=$selected
  (( selected >= top + list_h )) && top=$(( selected - list_h + 1 ))
  # Scroll back up when cards at the bottom are gone, so no list row is
  # left empty while cards above it are hidden.
  (( top > count - list_h )) && top=$(( count - list_h ))
  (( top < 0 )) && top=0

  # A date takes 13 columns, so a narrow drawer leaves them out rather than
  # cut every title down to a few characters.
  title_cols=$cols
  (( cols >= 24 )) && title_cols=$(( cols - 13 ))

  printf -v sep '%*s' "$cols" ''
  sep=${sep// /─}

  out=$'\e[H\e[2J'
  if (( count == 0 )); then
    goto 1
    out+=$'\e[2m (empty) press i to add\e[0m'
  fi
  for (( row = 0; row < list_h && top + row < count; row++ )); do
    i=$(( top + row ))
    fit " ${titles[i]}" "$title_cols"
    printf -v pad '%*s' $(( title_cols - FIT_COLS )) ''
    goto $(( row + 1 ))
    (( i == selected )) && out+=$'\e[7m'
    out+="$FIT$pad"
    (( title_cols < cols )) && out+=$'\e[2m'" ${dates[i]} "
    out+=$'\e[0m'
  done

  goto $(( list_h + 1 ))
  out+=$'\e[2m'"$sep"$'\e[0m'
  row=$(( list_h + 2 ))
  preview_bottom=$(( rows - foot_h - 1 ))
  if (( count > 0 )); then
    mapfile -t lines < "${cards[selected]}"
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
  for line in "${footer[@]:0:foot_h}"; do
    row=$(( row + 1 ))
    fit "$line" "$cols"
    goto $row
    out+=$FIT
  done
  out+=$'\e[0m'
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

main() {
  trap restore_terminal EXIT
  prepare_terminal
  load_cards
  while true; do
    draw
    read_key
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
