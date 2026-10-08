# Moving a card to another window with m: the window picker, the move
# itself, the counts it updates and the selection it leaves.

test_m_opens_the_picker_with_every_other_window_once() {
  start_host || return
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'card a'
  new_window w1 > /dev/null
  new_window w2 > /dev/null
  host new-session -d -s other -n o1 'sleep 100000'
  # list-windows -a lists a window once for every session it is linked
  # into, so w1 and the drawer's own window show up twice there.
  host link-window -s main:w1 -t other:
  host link-window -s main:agent -t other:
  open_drawer || return
  move_open_picker || return
  wait_for move_rows_are 'main:1 w1|main:2 w2|other:0 o1' ||
    fail "rows: $(move_rows), want main:1 w1|main:2 w2|other:0 o1" || return
  wait_for footer_is ' Enter move   q cancel' || fail "footer: $(footer)" || return
  wait_for move_picked_is 'main:1 w1' || fail "selected: $(move_picked), want main:1 w1"
}

test_picker_shows_dimmed_card_counts() {
  local w1 w3
  start_host || return
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'card a'
  w1=$(new_window w1)
  new_window w2 > /dev/null
  w3=$(new_window w3)
  make_card "$(cards_dir "$w1")" 0000000001.1759800000.eeeeee 'w1 one'
  make_card "$(cards_dir "$w1")" 0000000002.1759800060.ffffff 'w1 two'
  make_card "$(cards_dir "$w3")" 0000000001.1759800120.gggggg 'w3 one'
  # make_card leaves @cuecard-count alone, and the picker reads the counts
  # from it. The plugin counts the cards of every window when it loads.
  load_plugin
  open_drawer || return
  move_open_picker || return
  wait_for move_rows_are 'main:1 w1 (2 cards)|main:2 w2|main:3 w3 (1 card)' ||
    fail "rows: $(move_rows), want main:1 w1 (2 cards)|main:2 w2|main:3 w3 (1 card)" || return
  # w1 is the selected row, so its count is also in reverse video.
  wait_for move_count_dimmed 'main:1 w1' ' 2 cards ' ||
    fail "w1 row: $(move_raw_row 'main:1 w1'), want ' 2 cards ' dimmed" || return
  wait_for move_count_dimmed 'main:3 w3' ' 1 card ' ||
    fail "w3 row: $(move_raw_row 'main:3 w3'), want ' 1 card ' dimmed"
}

test_move_puts_the_card_at_the_bottom_of_the_target_stack() {
  local w1 w2 want
  start_host || return
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'card a'
  make_card "$(cards_dir)" 0000000002.1759900060.bbbbbb $'card b\n\tsecond line  \n한글 ✅'
  make_card "$(cards_dir)" 0000000003.1759900120.cccccc 'card c'
  cp "$(cards_dir)/0000000002.1759900060.bbbbbb" "$CASE_DIR/card-b"
  w1=$(new_window w1)
  w2=$(new_window w2)
  # 08 and 09 are not octal numbers, so the next order must be worked out
  # in base 10.
  make_card "$(cards_dir "$w2")" 0000000008.1759800000.eeeeee 'w2 eight'
  make_card "$(cards_dir "$w2")" 0000000009.1759800060.ffffff 'w2 nine'
  open_drawer || return
  press j
  move_open_picker || return
  press j
  wait_for move_picked_is 'main:2 w2' || fail "selected: $(move_picked), want main:2 w2" || return
  press Enter
  want='0000000008.1759800000.eeeeee 0000000009.1759800060.ffffff 0000000010.1759900060.bbbbbb'
  wait_for card_names_are "$(cards_dir "$w2")" "$want" ||
    fail "w2 cards: $(card_names "$(cards_dir "$w2")"), want $want" || return
  want='0000000001.1759900000.aaaaaa 0000000003.1759900120.cccccc'
  [[ $(card_names "$(cards_dir)") == "$want" ]] ||
    fail "source cards: $(card_names "$(cards_dir)"), want $want" || return
  cmp -s "$CASE_DIR/card-b" "$(cards_dir "$w2")/0000000010.1759900060.bbbbbb" ||
    fail "the moved card changed: $(od -c "$(cards_dir "$w2")/0000000010.1759900060.bbbbbb")" || return
  [[ ! -e $(cards_dir "$w1") ]] || fail "w1 got cards: $(card_names "$(cards_dir "$w1")")"
}

test_move_creates_the_missing_target_directory() {
  local w1
  start_host || return
  move_three_cards
  w1=$(new_window w1)
  open_drawer || return
  [[ ! -e $(cards_dir "$w1") ]] || fail "w1 already has $(cards_dir "$w1")" || return
  move_open_picker || return
  press Enter
  wait_for card_names_are "$(cards_dir "$w1")" 0000000001.1759900000.aaaaaa ||
    fail "w1 cards: $(card_names "$(cards_dir "$w1")"), want 0000000001.1759900000.aaaaaa"
}

test_move_updates_both_window_counts_and_the_status_line() {
  local w1
  start_host || return
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'card a'
  make_card "$(cards_dir)" 0000000002.1759900060.bbbbbb 'card b'
  w1=$(new_window w1)
  open_drawer || return
  move_open_picker || return
  press Enter
  wait_for card_count_is 1 || fail "source count: '$(card_count)', want 1" || return
  wait_for card_count_is 1 "$w1" || fail "w1 count: '$(card_count "$w1")', want 1" || return
  # The window list stays in view to the left of the drawer.
  wait_for status_has '0:agent*cue:1 1:w1cue:1' ||
    fail "status: $(status_line), want 0:agent*cue:1 1:w1cue:1" || return
  close_drawer || return
  wait_for move_status_right_is 'cue:1' || fail "status: $(status_line), want cue:1 on the right" || return
  # Moving the last card unsets the count of its window.
  open_drawer || return
  move_open_picker || return
  press Enter
  wait_for card_count_is '' || fail "source count: '$(card_count)', want none" || return
  wait_for card_count_is 2 "$w1" || fail "w1 count: '$(card_count "$w1")', want 2" || return
  wait_for status_has '0:agent* 1:w1cue:2' ||
    fail "status: $(status_line), want 0:agent* 1:w1cue:2" || return
  close_drawer || return
  wait_for move_status_right_is '' || fail "status: $(status_line), want nothing on the right"
}

test_move_keeps_the_selection_index() {
  start_host || return
  move_three_cards
  new_window w1 > /dev/null
  open_drawer || return
  press j
  move_open_picker || return
  press Enter
  wait_for move_rows_are 'card a|card c' || fail "rows: $(move_rows), want card a|card c" || return
  wait_for selected_is 'card c' || fail "selected: $(selected), want card c"
}

test_move_of_the_bottom_card_clamps_the_selection() {
  start_host || return
  move_three_cards
  new_window w1 > /dev/null
  open_drawer || return
  press j j
  move_open_picker || return
  press Enter
  wait_for move_rows_are 'card a|card b' || fail "rows: $(move_rows), want card a|card b" || return
  wait_for selected_is 'card b' || fail "selected: $(selected), want card b"
}

test_picker_q_and_esc_go_back_to_the_unchanged_card_list() {
  local w1 w2 before key
  start_host || return
  move_three_cards
  w1=$(new_window w1)
  w2=$(new_window w2)
  open_drawer || return
  before=$(card_names "$(cards_dir)")
  press j
  for key in q Escape; do
    move_open_picker || return
    press j
    wait_for move_picked_is 'main:2 w2' || fail "selected: $(move_picked), want main:2 w2" || return
    press "$key"
    wait_for move_list_shown || fail "$key did not go back to the cards: row 1 is '$(popup_line 1)'" || return
    wait_for move_rows_are 'card a|card b|card c' ||
      fail "rows after $key: $(move_rows), want card a|card b|card c" || return
    wait_for selected_is 'card b' || fail "selected after $key: $(selected), want card b" || return
    wait_for footer_is "$(move_list_footer)" || fail "footer after $key: $(footer)" || return
    [[ $(card_names "$(cards_dir)") == "$before" ]] ||
      fail "cards after $key: $(card_names "$(cards_dir)"), want $before" || return
    [[ ! -e $(cards_dir "$w1") && ! -e $(cards_dir "$w2") ]] ||
      fail "a card moved on $key: w1 $(card_names "$(cards_dir "$w1")"), w2 $(card_names "$(cards_dir "$w2")")" ||
      return
  done
}

test_move_does_nothing_on_an_empty_stack() {
  start_host || return
  new_window w1 > /dev/null
  open_drawer || return
  wait_for move_rows_are '(empty) press i to add' || fail "rows: $(move_rows)" || return
  # Had m opened the picker, q would only close the picker.
  press m q
  wait_for drawer_closed || fail "m opened the picker on an empty stack"
}

test_move_without_another_window_shows_a_notice() {
  start_host || return
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'card a'
  make_card "$(cards_dir)" 0000000002.1759900060.bbbbbb 'card b'
  open_drawer || return
  press m
  wait_for footer_is "$(move_list_footer 'No other window')" ||
    fail "footer: $(footer), want $(move_list_footer 'No other window')" || return
  wait_for move_list_shown || fail "row 1 is '$(popup_line 1)', want the tab bar" || return
  wait_for move_rows_are 'card a|card b' || fail "rows: $(move_rows), want card a|card b" || return
  press j
  wait_for footer_is "$(move_list_footer)" || fail "footer after j: $(footer)" || return
  wait_for selected_is 'card b' || fail "selected after j: $(selected), want card b"
}

test_move_to_a_window_that_closed_keeps_the_card() {
  local w1 before
  start_host || return
  move_three_cards
  w1=$(new_window w1)
  new_window w2 > /dev/null
  make_card "$(cards_dir "$w1")" 0000000001.1759800000.eeeeee 'w1 one'
  open_drawer || return
  before=$(card_names "$(cards_dir)")
  move_open_picker || return
  wait_for move_picked_is 'main:1 w1' || fail "selected: $(move_picked), want main:1 w1" || return
  host kill-window -t "$w1"
  # The cleanup hook removes the directory of the closed window. Waiting for
  # it means that a directory found later was written by the move.
  wait_for absent "$(cards_dir "$w1")" || fail "the cleanup hook kept $(cards_dir "$w1")" || return
  press Enter
  wait_for footer_is "$(move_list_footer 'Window is gone, card kept')" ||
    fail "footer: $(footer), want $(move_list_footer 'Window is gone, card kept')" || return
  [[ ! -e $(cards_dir "$w1") ]] ||
    fail "the move wrote $(cards_dir "$w1"): $(card_names "$(cards_dir "$w1")")" || return
  [[ $(card_names "$(cards_dir)") == "$before" ]] ||
    fail "cards: $(card_names "$(cards_dir)"), want $before" || return
  wait_for move_rows_are 'card a|card b|card c' || fail "rows: $(move_rows), want card a|card b|card c" || return
  wait_for selected_is 'card a' || fail "selected: $(selected), want card a" || return
  [[ $(card_count) == 3 ]] || fail "source count: '$(card_count)', want 3"
}

test_picker_scrolls_and_stops_at_both_ends() {
  local n ids=()
  ROWS=12 start_host || return
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'card a'
  for n in {1..10}; do
    ids+=("$(new_window "w$n")")
  done
  open_drawer || return
  move_open_picker || return
  # A 12-row client leaves room for the heading and two windows.
  wait_for move_rows_are 'main:1 w1|main:2 w2' || fail "rows: $(move_rows), want main:1 w1|main:2 w2" || return
  press j j j j j j j j j
  wait_for move_picked_is 'main:10 w10' || fail "selected: $(move_picked), want main:10 w10" || return
  wait_for move_rows_are 'main:9 w9|main:10 w10' ||
    fail "rows at the bottom: $(move_rows), want main:9 w9|main:10 w10" || return
  # j stays on the last window, so the k after it lands on the one above.
  press j k
  wait_for move_picked_is 'main:9 w9' || fail "selected after j k: $(move_picked), want main:9 w9" || return
  press k k k k k k k k
  wait_for move_picked_is 'main:1 w1' || fail "selected: $(move_picked), want main:1 w1" || return
  wait_for move_rows_are 'main:1 w1|main:2 w2' ||
    fail "rows at the top: $(move_rows), want main:1 w1|main:2 w2" || return
  # k stays on the first window, so the j after it lands on the second.
  press k j
  wait_for move_picked_is 'main:2 w2' || fail "selected after k j: $(move_picked), want main:2 w2" || return
  # The card goes to the window picked further down the list.
  press j j j j j j j
  wait_for move_rows_are 'main:8 w8|main:9 w9' || fail "rows: $(move_rows), want main:8 w8|main:9 w9" || return
  wait_for move_picked_is 'main:9 w9' || fail "selected: $(move_picked), want main:9 w9" || return
  press Enter
  wait_for card_names_are "$(cards_dir "${ids[8]}")" 0000000001.1759900000.aaaaaa ||
    fail "w9 cards: $(card_names "$(cards_dir "${ids[8]}")"), want 0000000001.1759900000.aaaaaa"
}

test_move_into_legacy_cards_puts_the_card_after_them() {
  local w1 want
  start_host || return
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'card a'
  w1=$(new_window w1)
  # Cards written before the stack could be reordered are named
  # <created>.<rand>, so their creation time is their order.
  make_card "$(cards_dir "$w1")" 1759800000.cccccc 'legacy one'
  make_card "$(cards_dir "$w1")" 1759800500.dddddd 'legacy two'
  open_drawer || return
  move_open_picker || return
  press Enter
  want='1759800000.cccccc 1759800500.dddddd 1759800501.1759900000.aaaaaa'
  wait_for card_names_are "$(cards_dir "$w1")" "$want" ||
    fail "w1 cards: $(card_names "$(cards_dir "$w1")"), want $want" || return
  [[ $(titles "$(cards_dir "$w1")") == 'legacy one|legacy two|card a' ]] ||
    fail "w1 titles: $(titles "$(cards_dir "$w1")"), want legacy one|legacy two|card a"
}

test_move_does_nothing_in_the_saved_view() {
  local w1
  start_host || return
  make_card "$SAVED_DIR" 0000000001.1759900000.ssssss 'saved one'
  w1=$(new_window w1)
  open_drawer || return
  press Tab
  wait_for popup_has 'c to window' || fail "Tab did not open the saved cards: row 1 is '$(popup_line 1)'" || return
  # Had m opened the picker, q would only close the picker.
  press m q
  wait_for drawer_closed || fail "m opened the picker in the saved view" || return
  [[ $(card_names "$SAVED_DIR") == 0000000001.1759900000.ssssss ]] ||
    fail "saved cards: $(card_names "$SAVED_DIR")" || return
  [[ ! -e $(cards_dir "$w1") ]] || fail "w1 got cards: $(card_names "$(cards_dir "$w1")")"
}

# --- helpers -----------------------------------------------------------------

# Writes cards a, b and c to the stack of the drawer's window.
move_three_cards() {
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'card a'
  make_card "$(cards_dir)" 0000000002.1759900060.bbbbbb 'card b'
  make_card "$(cards_dir)" 0000000003.1759900120.cccccc 'card c'
}

move_open_picker() {
  press m
  wait_for move_picker_shown || fail "m did not open the picker: row 1 is '$(popup_line 1)'"
}

move_picker_shown() {
  [[ $(popup_line 1) == ' Move to window' ]]
}

move_list_shown() {
  [[ $(popup_line 1) =~ ^\ window\ [0-9]+ ]]
}

# The popup rows from row 2 down to the first separator, joined by '|':
# the cards of the list without their dates, or the windows of the picker
# with their card counts in parentheses, as in 'main:2 w2 (2 cards)'.
move_rows() {
  popup_lines | sed -n '2,$p' | sed '/^─/,$d' |
    sed -E 's/ [0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} *$//; s/ +([0-9]+ cards?) *$/ (\1)/; s/^ +//; s/ +$//' |
    paste -sd '|' -
}

move_rows_are() {
  [[ $(move_rows) == "$1" ]]
}

# The footer of the card list, with $1 in place of its first line.
move_list_footer() {
  printf ' %s| e edit   d delete   q quit| c save   Tab saved| J/K move   m to window' \
    "${1:-Enter pick   p pop   i new}"
}

# The label of the selected picker row, without its card count.
move_picked() {
  selected | sed -E 's/ +[0-9]+ cards?$//'
}

move_picked_is() {
  [[ $(move_picked) == "$1" ]]
}

# The picker row of window label $1 with its attributes, escapes made visible.
move_raw_row() {
  popup_lines -e | grep -F -- " $1 " | cat -v
}

# Succeeds when the picker row of window label $1 shows $2 dimmed.
move_count_dimmed() {
  popup_lines -e | grep -F -- " $1 " | grep -qE $'\e''\[([0-9;]*;)?2(;[0-9;]*)?m'"$2"
}

# Succeeds when status-right shows $1: the text after the last run of two
# or more blanks, as the window list never has two in a row.
move_status_right_is() {
  local right
  right=$(status_line)
  [[ $right =~ \ {2,}([^ ]*)$ ]] && right=${BASH_REMATCH[1]} || right=
  [[ $right == "$1" ]]
}
