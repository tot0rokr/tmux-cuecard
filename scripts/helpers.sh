#!/usr/bin/env bash

get_tmux_option() {
  local value
  value=$(tmux show-option -gqv "$1")
  echo "${value:-$2}"
}

store_root() {
  echo "${XDG_STATE_HOME:-$HOME/.local/state}/tmux-cuecard"
}

# Window ids restart from @0 when the tmux server restarts, so cards are
# namespaced by server instance to keep them from leaking into new windows.
server_dir() {
  echo "$(store_root)/$(tmux display-message -p '#{pid}-#{start_time}')"
}

window_dir() {
  echo "$(server_dir)/$1"
}

# display-popup does not expand formats in its command, so popup scripts look
# up the window and pane they were opened from.
current_window_id() {
  tmux display-message -p '#{window_id}'
}

current_pane_id() {
  tmux display-message -p '#{pane_id}'
}

window_exists() {
  tmux list-windows -a -F '#{window_id}' | grep -qxF "$1"
}

# Mirrors the number of cards into a window option, so status formats can
# show it without running a shell command on every redraw.
update_count() {
  local cards
  cards=("$(window_dir "$1")"/*)
  [[ -e ${cards[0]} ]] || cards=()
  if (( ${#cards[@]} )); then
    tmux set-option -wq -t "$1" @cuecard-count "${#cards[@]}"
  else
    tmux set-option -wqu -t "$1" @cuecard-count
  fi
}

# A card file is named <order>.<created>.<rand>, and the glob order of the
# names is the order of the stack. Cards written before the stack could be
# reordered are named <created>.<rand>, so their creation time doubles as
# the order. Sets CARD_ORDER, CARD_CREATED and CARD_RAND.
parse_card() {
  local name=${1##*/}
  CARD_ORDER=${name%%.*}
  CARD_CREATED=$CARD_ORDER
  CARD_RAND=${name#*.}
  if [[ $CARD_RAND == *.* ]]; then
    CARD_CREATED=${CARD_RAND%%.*}
    CARD_RAND=${CARD_RAND#*.}
  fi
  # A stray file must not abort the script with an arithmetic error.
  [[ $CARD_ORDER =~ ^[0-9]+$ ]] || CARD_ORDER=0
  [[ $CARD_CREATED =~ ^[0-9]+$ ]] || CARD_CREATED=0
}

# Zero-padding keeps the glob order of the names equal to the numeric order.
# Sets CARD_NAME.
card_name() {
  printf -v CARD_NAME '%010d.%s.%s' $(( 10#$1 )) "$2" "$3"
}

# Prints the order that puts a new card below every card in directory $1.
next_order() {
  local card max=0
  for card in "$1"/*; do
    [[ -e $card ]] || continue
    parse_card "$card"
    (( 10#$CARD_ORDER > max )) && max=$(( 10#$CARD_ORDER ))
  done
  echo $(( max + 1 ))
}

# Moves card $1 to the bottom of the stack in directory $2. It keeps its
# <created>.<rand>, so it keeps its creation time and the drawer can still
# find it. Sets CARD_NAME to its new name.
move_card() {
  local card=$1 dir=$2 order
  mkdir -p "$dir"
  order=$(next_order "$dir")
  parse_card "$card"
  card_name "$order" "$CARD_CREATED" "$CARD_RAND"
  mv "$card" "$dir/$CARD_NAME"
}

has_text() {
  grep -q '[^[:space:]]' "$1"
}

# Errors go to display-message because TPM and display-popup -E both hide
# a script's stderr.
input_mode() {
  local mode
  mode=$(get_tmux_option @cuecard-input box)
  if [[ $mode != vim && $mode != box ]]; then
    tmux display-message "cuecard: @cuecard-input must be vim or box, not '$mode'"
    return 1
  fi
  echo "$mode"
}

# --clean skips the user's vimrc and plugins, which can break editing in a popup.
edit_in_vim() {
  vim --clean "$1"
}

# Reads one line into BOX_TEXT, prefilled with $2.
read_box() {
  printf '\e[H\e[2J%s\n' "$1"
  IFS= read -e -r -p '> ' -i "${2-}" BOX_TEXT
}
