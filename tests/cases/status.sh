# The card count: #{cuecard} in the status formats and the window option
# @cuecard-count behind it, the plugin load, and the cleanup of the cards
# of closed windows and of dead servers.

STATUS_DEFAULT_FORMAT='#{?#{@cuecard-count},cue:#{@cuecard-count},}'

test_status_count_shows_each_windows_own_count_and_nothing_at_zero() {
  start_host || return
  local second
  second=$(new_window second) || fail "could not open a second window" || return
  host select-window -t "$second"
  add_card 'second one' || return
  add_card 'second two' || return
  host select-window -t "$WINDOW"
  wait_for status_text_is '[main] 0:agent* 1:secondcue:2' ||
    fail "status: $(status_text), want cue:2 on window 1 only" || return
  add_card 'agent one' || return
  wait_for status_text_is '[main] 0:agent*cue:1 1:secondcue:2 cue:1' ||
    fail "status: $(status_text)" || return
  host select-window -t "$second"
  wait_for status_text_is '[main] 0:agentcue:1 1:second*cue:2 cue:2' ||
    fail "status on window 1: $(status_text)"
}

test_status_count_placeholder_is_replaced_in_every_status_format() {
  start_host "set -g status-left '[#{cuecard}] '" "set -g pane-border-status top" \
    "set -g pane-border-format 'border:#{cuecard}:'" || return
  local f=$STATUS_DEFAULT_FORMAT option want
  for option in "status-left=[$f] " "status-right=$f" "window-status-format=#I:#W$f" \
    "window-status-current-format=#I:#W*$f" "pane-border-format=border:$f:"; do
    want=${option#*=}
    option=${option%%=*}
    [[ $(host show-options -gv "$option") == "$want" ]] ||
      fail "$option: $(host show-options -gv "$option"), want: $want" || return
  done
  add_card 'one' || return
  wait_for status_text_is '[cue:1] 0:agent*cue:1 cue:1' || fail "status: $(status_text)" || return
  wait_for status_border_has 'border:cue:1:' || fail "pane border: $(screen | head -n 1)"
}

test_status_count_uses_a_custom_status_format() {
  local format='#{?#{@cuecard-count},cards=#{@cuecard-count},none}'
  start_host "set -g @cuecard-status-format '$format'" || return
  wait_for status_text_is '[main] 0:agent*none none' ||
    fail "status with no cards: $(status_text)" || return
  add_card 'one' || return
  wait_for status_text_is '[main] 0:agent*cards=1 cards=1' || fail "status: $(status_text)"
}

test_status_count_expands_once_when_the_config_is_sourced_again() {
  start_host || return
  add_card 'one' || return
  host source-file "$CASE_DIR/tmux.conf" || fail "source-file failed" || return
  load_plugin || fail "the plugin did not load again" || return
  local right current hooks
  right=$(host show-options -gv status-right)
  current=$(host show-options -gv window-status-current-format)
  [[ $right == "$STATUS_DEFAULT_FORMAT" ]] || fail "status-right: $right" || return
  [[ $current == "#I:#W*$STATUS_DEFAULT_FORMAT" ]] ||
    fail "window-status-current-format: $current" || return
  wait_for status_text_is '[main] 0:agent*cue:1 cue:1' || fail "status: $(status_text)" || return
  hooks=$(host show-hooks -g window-unlinked | grep -cF "$REPO_DIR/scripts/cleanup.sh")
  [[ $hooks == 1 ]] || fail "window-unlinked runs cleanup.sh $hooks times, want 1"
}

test_count_drops_right_away_when_a_card_is_popped() {
  start_host || return
  add_card 'one' || return
  add_card 'two' || return
  wait_for card_count_is 2 || fail "count: $(card_count), want 2" || return
  open_drawer || return
  press p
  wait_for drawer_closed || fail "p did not close the drawer" || return
  wait_for card_count_is 1 || fail "count after p: $(card_count), want 1" || return
  wait_for status_text_is '[main] 0:agent*cue:1 cue:1' || fail "status: $(status_text)"
}

test_count_drops_right_away_when_a_card_is_deleted() {
  start_host || return
  add_card 'one' || return
  add_card 'two' || return
  open_drawer || return
  press d
  wait_for card_count_is 1 || fail "count after d: $(card_count), want 1" || return
  drawer_shown || fail "d closed the drawer" || return
  close_drawer || return
  wait_for status_text_is '[main] 0:agent*cue:1 cue:1' || fail "status: $(status_text)"
}

test_count_is_unset_when_the_last_card_is_emptied_with_e() {
  start_host || return
  add_card 'only card' || return
  wait_for card_count_is 1 || fail "count: $(card_count), want 1" || return
  open_drawer || return
  press e
  # readline draws the prefilled text once it owns the terminal; a C-u sent
  # before that would be eaten by the tty line editing.
  wait_for screen_has '> only card' || fail "e did not open the edit box" || return
  press C-u Enter
  wait_for card_count_unset || fail "count after emptying: '$(card_count)', want unset" ||
    return
  wait_for popup_has '(empty)' || fail "the drawer does not show an empty list" || return
  close_drawer || return
  [[ -z $(card_names "$(cards_dir)") ]] || fail "cards left: $(card_names "$(cards_dir)")" || return
  wait_for status_text_is '[main] 0:agent*' || fail "status: $(status_text), want no count"
}

test_plugin_load_syncs_counts_with_the_cards_on_disk() {
  start_host || return
  local second third
  second=$(new_window second) || fail "could not open a second window" || return
  third=$(new_window third) || fail "could not open a third window" || return
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'one'
  make_card "$(cards_dir)" 0000000002.1759900000.bbbbbb 'two'
  make_card "$(cards_dir "$second")" 0000000001.1759900000.cccccc 'three'
  # A count left over from cards that are gone.
  host set-option -w -t "$third" @cuecard-count 4
  card_count_unset || fail "count before the load: $(card_count)" || return
  load_plugin || fail "the plugin did not load again" || return
  card_count_is 2 || fail "count of window 0: '$(card_count)', want 2" || return
  card_count_is 1 "$second" || fail "count of window 1: '$(card_count "$second")', want 1" ||
    return
  card_count_unset "$third" || fail "count of window 2: '$(card_count "$third")', want unset" ||
    return
  wait_for status_text_is '[main] 0:agent*cue:2 1:secondcue:1 2:third cue:2' ||
    fail "status: $(status_text)"
}

test_closing_a_window_deletes_its_cards() {
  start_host || return
  local second
  second=$(new_window second) || fail "could not open a second window" || return
  make_card "$(cards_dir "$second")" 0000000001.1759900000.aaaaaa 'goes with the window'
  make_card "$(cards_dir)" 0000000001.1759900000.bbbbbb 'stays'
  host kill-window -t "$second"
  wait_for absent "$(cards_dir "$second")" ||
    fail "cards of the closed window: $(card_names "$(cards_dir "$second")")" || return
  [[ $(titles "$(cards_dir)") == 'stays' ]] || fail "cards of window 0: $(titles "$(cards_dir)")"
}

test_window_linked_into_two_sessions_keeps_its_cards_when_it_leaves_one() {
  start_host || return
  local shared closing
  host new-session -d -s other 'sleep 100000' || fail "could not open a second session" || return
  shared=$(new_window shared) || fail "could not open a window" || return
  closing=$(new_window closing) || fail "could not open a window" || return
  host link-window -d -s "$shared" -t other:9 || fail "could not link the window" || return
  make_card "$(cards_dir "$shared")" 0000000001.1759900000.aaaaaa 'shared card'
  make_card "$(cards_dir "$closing")" 0000000001.1759900000.bbbbbb 'closing card'
  host unlink-window -t other:9 || fail "could not unlink the window" || return
  # The cleanup hook runs in the background, so nothing tells when it is
  # done keeping the cards. The hook of a window closed afterwards starts
  # later, so once that one has deleted its cards the first has run too.
  host kill-window -t "$closing"
  wait_for absent "$(cards_dir "$closing")" || fail "the closed window kept its cards" ||
    return
  [[ $(titles "$(cards_dir "$shared")") == 'shared card' ]] ||
    fail "cards of the window still in session main: '$(titles "$(cards_dir "$shared")")'" ||
    return
  host kill-window -t "$shared"
  wait_for absent "$(cards_dir "$shared")" ||
    fail "the window kept its cards after it left its last session"
}

test_plugin_load_deletes_the_cards_of_dead_servers() {
  start_host || return
  local dead_dir
  dead_dir="$CASE_DIR/state/tmux-cuecard/$(dead_pid)-1700000000"
  make_card "$dead_dir/@0" 0000000001.1700000000.aaaaaa 'card of a dead server'
  make_card "$(cards_dir)" 0000000001.1759900000.bbbbbb 'card of this server'
  load_plugin || fail "the plugin did not load again" || return
  wait_for absent "$dead_dir" ||
    fail "cards of the dead server: $(card_names "$dead_dir/@0")" || return
  [[ $(titles "$(cards_dir)") == 'card of this server' ]] ||
    fail "cards of this server: '$(titles "$(cards_dir)")'"
}

# The status line with each run of blanks squeezed to one space.
status_text() {
  status_line | tr -s ' '
}

status_text_is() {
  [[ $(status_text) == "$1" ]]
}

# The top pane border, drawn on the first row with pane-border-status top.
status_border_has() {
  screen | head -n 1 | grep -qF -- "$1"
}
