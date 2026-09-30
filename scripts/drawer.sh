#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
shopt -s nullglob

pane_id=$(current_pane_id)
dir=$(window_dir "$(current_window_id)")

cards=()
titles=()
selected=0
top=0

sanitize() {
  local text=${1//$'\t'/    }
  SANITIZED=${text//[[:cntrl:]]/}
}

# Newest card first. Titles are the first non-blank line of each card.
load_cards() {
  local files file line i
  files=("$dir"/*)
  cards=()
  titles=()
  for (( i = ${#files[@]} - 1; i >= 0; i-- )); do
    file=${files[i]}
    line=
    while IFS= read -r line; do
      [[ $line == *[![:space:]]* ]] && break
    done < "$file"
    sanitize "$line"
    cards+=("$file")
    titles+=("$SANITIZED")
  done
  (( selected >= ${#cards[@]} )) && selected=$(( ${#cards[@]} - 1 ))
  (( selected < 0 )) && selected=0
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
  read -r rows cols < <(stty size)
  count=${#cards[@]}

  max_list=$(( (rows - 4) / 2 ))
  list_h=$count
  (( list_h > max_list )) && list_h=$max_list
  (( list_h < 1 )) && list_h=1
  (( selected < top )) && top=$selected
  (( selected >= top + list_h )) && top=$(( selected - list_h + 1 ))

  printf -v sep '%*s' "$cols" ''
  sep=${sep// /─}

  out=$'\e[H\e[2J'
  if (( count == 0 )); then
    goto 1
    out+=$'\e[2m (empty) press i to add\e[0m'
  fi
  for (( row = 0; row < list_h && top + row < count; row++ )); do
    i=$(( top + row ))
    fit " ${titles[i]}" "$cols"
    printf -v pad '%*s' $(( cols - FIT_COLS )) ''
    goto $(( row + 1 ))
    (( i == selected )) && out+=$'\e[7m'
    out+="$FIT$pad"$'\e[0m'
  done

  goto $(( list_h + 1 ))
  out+=$'\e[2m'"$sep"$'\e[0m'
  row=$(( list_h + 2 ))
  preview_bottom=$(( rows - 3 ))
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

  goto $(( rows - 2 ))
  out+=$'\e[2m'"$sep"
  goto $(( rows - 1 ))
  out+=' Enter pick   p pop   i new'
  goto "$rows"
  out+=' e edit   d delete   q quit'$'\e[0m'
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

edit_selected() {
  local card=${cards[selected]}
  open_editor "$card"
  has_text "$card" || rm -f "$card"
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
      '')
        (( ${#cards[@]} )) || continue
        paste_selected
        exit 0
        ;;
      p)
        (( ${#cards[@]} )) || continue
        paste_selected
        rm -f "${cards[selected]}"
        exit 0
        ;;
      i)
        with_terminal_restored "$CURRENT_DIR/insert.sh"
        selected=0
        load_cards
        ;;
      e)
        (( ${#cards[@]} )) || continue
        with_terminal_restored edit_selected
        load_cards
        ;;
      d)
        (( ${#cards[@]} )) || continue
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
