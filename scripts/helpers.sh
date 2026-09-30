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
