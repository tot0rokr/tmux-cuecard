#!/usr/bin/env bash
set -eu

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

window_id=$1
if [[ ! $window_id =~ ^@[0-9]+$ ]]; then
  echo "cuecard: invalid window id '$window_id'" >&2
  exit 1
fi

# window-unlinked also fires when a window leaves one of several sessions.
if window_exists "$window_id"; then
  exit 0
fi

if ! trash_window "$(window_dir "$window_id")" window-closed; then
  tmux display-message 'cuecard: could not move closed window cards to trash'
  exit 1
fi
