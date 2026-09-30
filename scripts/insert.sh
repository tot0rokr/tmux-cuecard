#!/usr/bin/env bash
set -eu

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

window_id=$(current_window_id)
mode=$(input_mode)
draft=$(mktemp)
trap 'rm -f "$draft"' EXIT

if [[ $mode == box ]]; then
  read_box 'New card (Enter saves, empty cancels)' || exit 0
  printf '%s\n' "$BOX_TEXT" > "$draft"
else
  edit_in_vim "$draft"
fi
has_text "$draft" || exit 0

dir=$(window_dir "$window_id")
mkdir -p "$dir"
mv "$draft" "$(mktemp "$dir/$(date +%s).XXXXXX")"
