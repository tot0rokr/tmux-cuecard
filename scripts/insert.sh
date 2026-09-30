#!/usr/bin/env bash
set -eu

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

window_id=$(current_window_id)
draft=$(mktemp)
trap 'rm -f "$draft"' EXIT

open_editor "$draft"
has_text "$draft" || exit 0

dir=$(window_dir "$window_id")
mkdir -p "$dir"
mv "$draft" "$(mktemp "$dir/$(date +%s).XXXXXX")"
