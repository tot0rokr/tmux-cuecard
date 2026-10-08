#!/usr/bin/env bash
set -eu

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# Writes a card for the current window, or a saved card when $1 is saved.
# The drawer passes a file as $2 to learn the name of the new card.
list=${1:-window}
made=${2-}
window_id=$(current_window_id)
mode=$(input_mode)
draft=$(mktemp)
trap 'rm -f "$draft"' EXIT

prompt='New card (Enter saves, empty cancels)'
[[ $list == saved ]] && prompt='New saved card (Enter saves, empty cancels)'
if [[ $mode == box ]]; then
  read_box "$prompt" || exit 0
  printf '%s\n' "$BOX_TEXT" > "$draft"
else
  edit_in_vim "$draft"
fi
has_text "$draft" || exit 0

dir=$(window_dir "$window_id")
[[ $list == saved ]] && dir=$(saved_dir)
if ! add_card "$draft" "$dir"; then
  tmux display-message "cuecard: could not write the card to $dir"
  exit 1
fi
[[ $list == saved ]] || update_count "$window_id"
[[ -z $made ]] || echo "$CARD_NAME" > "$made"
