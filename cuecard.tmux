#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$CURRENT_DIR/scripts"
source "$SCRIPTS_DIR/helpers.sh"

# Hooks do not run when the server itself exits, so drop the cards of
# servers that are gone.
remove_dead_server_dirs() {
  local dir pid
  for dir in "$(store_root)"/[0-9]*-[0-9]*; do
    [[ -d $dir ]] || continue
    pid=${dir##*/}
    pid=${pid%%-*}
    kill -0 "$pid" 2>/dev/null || rm -rf "$dir"
  done
}

STATUS_OPTIONS=(status-left status-right window-status-format
  window-status-current-format pane-border-format)

# Replaces #{cuecard} in the status formats, the same way other TPM plugins
# expand their placeholders.
interpolate_status() {
  local placeholder='#{cuecard}' format option value
  format=$(get_tmux_option @cuecard-status-format \
    '#{?#{@cuecard-count},cue:#{@cuecard-count},}')
  for option in "${STATUS_OPTIONS[@]}"; do
    value=$(get_tmux_option "$option" '')
    [[ $value == *"$placeholder"* ]] || continue
    tmux set-option -gq "$option" "${value//"$placeholder"/"$format"}"
  done
}

# Sets the count of windows that already had cards before this version.
sync_counts() {
  local window_id
  for window_id in $(tmux list-windows -a -F '#{window_id}'); do
    update_count "$window_id"
  done
}

main() {
  local drawer_key insert_key width input title popup box_popup cleanup_script
  drawer_key=$(get_tmux_option @cuecard-key Q)
  insert_key=$(get_tmux_option @cuecard-insert-key A)
  width=$(get_tmux_option @cuecard-width 40%)
  input=$(input_mode) || return
  title=' cuecard #{window_index}:#{window_name} '
  popup=(display-popup -E -x R -y 0 -w "$width" -h 100% -T "$title")
  box_popup=(display-popup -E -w 60% -h 5 -T "$title")

  tmux bind-key "$drawer_key" "${popup[@]}" "'$SCRIPTS_DIR/drawer.sh'"
  if [[ $input == box ]]; then
    tmux bind-key "$insert_key" "${box_popup[@]}" "'$SCRIPTS_DIR/insert.sh'"
  else
    tmux bind-key "$insert_key" "${popup[@]}" "'$SCRIPTS_DIR/insert.sh'"
  fi

  cleanup_script="$SCRIPTS_DIR/cleanup.sh"
  if ! tmux show-hooks -g window-unlinked | grep -qF "$cleanup_script"; then
    tmux set-hook -ga window-unlinked \
      "run-shell -b \"'$cleanup_script' '#{hook_window}'\""
  fi

  remove_dead_server_dirs
  interpolate_status
  sync_counts
}

main
