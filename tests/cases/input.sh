# Writing a card with prefix + A: the name of the new card, the box and vim
# input, and the options that pick the input and the keys.

INPUT_BAD_MODE_MESSAGE="cuecard: @cuecard-input must be vim or box, not 'emacs'"

test_insert_key_adds_the_card_below_the_largest_order() {
  start_host || return
  local before after name
  printf -v before '%(%s)T' -1
  add_card 'first card' || return
  printf -v after '%(%s)T' -1
  name=$(card_names "$(cards_dir)")
  [[ $name =~ ^0000000001\.([0-9]{10})\.[A-Za-z0-9]{6}$ ]] ||
    fail "first card: '$name', want 0000000001.<epoch>.<6 chars>" || return
  ((BASH_REMATCH[1] >= before && BASH_REMATCH[1] <= after)) ||
    fail "created ${BASH_REMATCH[1]}, want $before..$after" || return
  [[ $(<"$(cards_dir)/$name") == 'first card' ]] ||
    fail "card text: $(<"$(cards_dir)/$name")" || return
  make_card "$(cards_dir)" 0000000007.1759900000.aaaaaa 'seventh'
  add_card 'next card' || return
  name=$(card_of 'next card')
  [[ $name =~ ^0000000008\.[0-9]{10}\.[A-Za-z0-9]{6}$ ]] ||
    fail "next card: '$name', want order 0000000008" || return
  [[ $(titles "$(cards_dir)") == 'first card|seventh|next card' ]] ||
    fail "cards: $(titles "$(cards_dir)")"
}

test_insert_key_after_legacy_cards_takes_the_newest_epoch_plus_one() {
  start_host || return
  make_card "$(cards_dir)" 1759900000.aaaaaa 'legacy one'
  make_card "$(cards_dir)" 1759900100.bbbbbb 'legacy two'
  add_card 'after legacy' || return
  local name
  name=$(card_of 'after legacy')
  [[ $name =~ ^1759900101\.[0-9]{10}\.[A-Za-z0-9]{6}$ ]] ||
    fail "new card: '$name', want order 1759900101" || return
  [[ $(titles "$(cards_dir)") == 'legacy one|legacy two|after legacy' ]] ||
    fail "cards: $(titles "$(cards_dir)")"
}

test_insert_key_adds_nothing_for_empty_input() {
  start_host || return
  press C-b A
  wait_for screen_has 'New card' || fail "the input box did not open" || return
  press Enter
  wait_for screen_lacks 'New card' || fail "the input box did not close" || return
  add_card '   ' || return
  [[ -z $(card_names "$(cards_dir)") ]] || fail "cards: $(card_names "$(cards_dir)")" || return
  [[ -z $(card_count) ]] || fail "count: $(card_count), want none"
}

test_vim_input_adds_a_multi_line_card() {
  start_host "set -g @cuecard-input vim" || return
  # --clean keeps the user's vimrc out, so its line numbers must not show.
  printf 'set number\n' > "$CASE_DIR/home/.vimrc"
  press C-b A
  wait_for input_vim_ready || fail "vim did not open" || return
  [[ -z $(popup_line 1) ]] || fail "vim read the vimrc: row 1 is '$(popup_line 1)'" || return
  press i
  wait_for popup_has '-- INSERT --' || fail "vim did not enter insert mode" || return
  type_text 'first line'
  press Enter
  type_text 'second line'
  press Escape
  wait_for popup_lacks '-- INSERT --' || fail "vim did not leave insert mode" || return
  type_text ':wq'
  press Enter
  wait_for drawer_closed || fail "vim did not close" || return
  local name
  name=$(card_names "$(cards_dir)")
  [[ $name =~ ^0000000001\.[0-9]{10}\.[A-Za-z0-9]{6}$ ]] || fail "card: '$name'" || return
  [[ $(<"$(cards_dir)/$name") == $'first line\nsecond line' ]] ||
    fail "card text: $(paste -sd '|' "$(cards_dir)/$name")" || return
  [[ $(card_count) == 1 ]] || fail "count: '$(card_count)', want 1"
}

test_invalid_input_option_at_startup_still_binds_the_keys_and_they_say_why() {
  start_host "set -g @cuecard-input emacs" || return
  # tmux loads the config before the client attaches, so the message from
  # the load itself is lost; the keys must be bound to say it instead.
  [[ $(input_plugin_keys) == 'A Q' ]] ||
    fail "keys bound to the plugin: '$(input_plugin_keys)', want 'A Q'" || return
  [[ $(host show-options -gv status-right) != *'#{cuecard}'* ]] ||
    fail "status-right kept the placeholder: $(host show-options -gv status-right)" || return
  press C-b A
  wait_for input_message_count_is 1 ||
    fail "messages after prefix + A: '$(messages)', want: $INPUT_BAD_MODE_MESSAGE" ||
    return
  wait_for drawer_closed || fail "the input popup did not close" || return
  press C-b Q
  wait_for input_message_count_is 2 || fail "messages after prefix + Q: '$(messages)'" ||
    return
  wait_for drawer_closed || fail "the drawer did not close" || return
  [[ -z $(card_names "$(cards_dir)") ]] || fail "cards: $(card_names "$(cards_dir)")"
}

test_invalid_input_option_set_later_says_why_and_adds_no_card() {
  start_host || return
  host set-option -g @cuecard-input emacs
  # Loading the plugin again says why in a message.
  load_plugin >/dev/null 2>&1
  wait_for input_message_count_is 1 || fail "messages after the reload: $(messages)" ||
    return
  # The keys bound before the reload say it again instead of opening an input.
  press C-b A
  wait_for input_message_count_is 2 || fail "messages after prefix + A: $(messages)" ||
    return
  wait_for drawer_closed || fail "the input popup did not close" || return
  [[ -z $(card_names "$(cards_dir)") ]] || fail "cards: $(card_names "$(cards_dir)")"
}

test_key_options_rebind_the_drawer_and_insert_keys() {
  start_host "set -g @cuecard-key V" "set -g @cuecard-insert-key N" || return
  [[ $(input_plugin_keys) == 'N V' ]] ||
    fail "keys bound to the plugin: '$(input_plugin_keys)', want 'N V'" || return
  press C-b N
  wait_for screen_has 'New card' || fail "prefix + N did not open the input box" || return
  type_text 'rebound'
  press Enter
  wait_for screen_lacks 'New card' || fail "the input box did not close" || return
  [[ $(titles "$(cards_dir)") == 'rebound' ]] || fail "cards: $(titles "$(cards_dir)")" || return
  press C-b V
  wait_for drawer_drawn || fail "prefix + V did not open the drawer" || return
  [[ $(popup_line 2) == ' rebound'* ]] || fail "row 2: $(popup_line 2)" || return
  close_drawer
}

# vim draws ~ on the rows past the end of an empty buffer.
input_vim_ready() {
  [[ $(popup_line 2) == '~' ]]
}

# The prefix keys bound to a plugin script, sorted.
input_plugin_keys() {
  host list-keys -T prefix | grep -F "$REPO_DIR/scripts/" | awk '{print $4}' | sort |
    paste -sd ' ' -
}

# The number of times the message about the bad @cuecard-input was shown.
input_message_count_is() {
  [[ $(messages | grep -cF -- " message: $INPUT_BAD_MODE_MESSAGE") == "$1" ]]
}
