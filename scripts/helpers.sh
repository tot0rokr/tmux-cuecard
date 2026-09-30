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

open_editor() {
  local editor=${VISUAL:-${EDITOR:-vi}}
  # Unquoted so editor values with flags (e.g. "code -w") still work.
  $editor "$1"
}
