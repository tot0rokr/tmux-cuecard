# The drawer: listing, picking, popping, editing, deleting and reordering
# the cards of a window.

test_drawer_lists_cards_oldest_first_with_the_top_one_selected() {
  start_host || return
  add_card 'first card' || return
  add_card 'second card' || return
  open_drawer || return
  [[ $(popup_line 2) == ' first card'* ]] || fail "row 2: $(popup_line 2)" || return
  [[ $(popup_line 3) == ' second card'* ]] || fail "row 3: $(popup_line 3)" || return
  [[ $(selected) == 'first card' ]] || fail "selected: $(selected)"
}

test_drawer_rows_show_the_creation_date() {
  start_host || return
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'dated card'
  open_drawer || return
  local want
  printf -v want '%(%m-%d %H:%M)T' 1759900000
  [[ $(popup_line 2) == ' dated card '*" $want" ]] ||
    fail "row 2: $(popup_line 2), want the date $want"
}

test_drawer_enter_pastes_the_card_and_keeps_it() {
  start_host || return
  add_card 'keep me' || return
  open_drawer || return
  mark_paste
  press Enter
  wait_for drawer_closed || fail "Enter did not close the drawer" || return
  wait_for pasted_is "$(bracketed 'keep me')" ||
    fail "pasted: $(pasted), want: $(bracketed 'keep me')" || return
  [[ $(titles "$(cards_dir)") == 'keep me' ]] || fail "cards: $(titles "$(cards_dir)")"
}

test_drawer_p_pastes_the_card_and_removes_it() {
  start_host || return
  add_card 'pop me' || return
  add_card 'stay' || return
  open_drawer || return
  mark_paste
  press p
  wait_for drawer_closed || fail "p did not close the drawer" || return
  wait_for pasted_is "$(bracketed 'pop me')" || fail "pasted: $(pasted)" || return
  [[ $(titles "$(cards_dir)") == 'stay' ]] || fail "cards: $(titles "$(cards_dir)")"
}

test_drawer_shift_j_and_k_move_the_card_and_keep_the_order() {
  start_host || return
  add_card 'one' || return
  add_card 'two' || return
  add_card 'three' || return
  open_drawer || return
  press J
  wait_for selected_is 'one' || return
  wait_for titles_are "$(cards_dir)" 'two|one|three' ||
    fail "after J: $(titles "$(cards_dir)")" || return
  press K
  press K
  wait_for titles_are "$(cards_dir)" 'one|two|three' ||
    fail "after K K: $(titles "$(cards_dir)")" || return
  close_drawer || return
  open_drawer || return
  [[ $(popup_line 2) == ' one'* ]] || fail "reopened row 2: $(popup_line 2)"
}

# --- helpers -----------------------------------------------------------------

# Writes cards $2... to directory $1 as a stack in that order, a minute
# apart: card n is named <n>.<1759900000 + 60n>.cardNN.
drawer_stack() {
  local dir=$1 n=0 text
  shift
  for text in "$@"; do
    n=$((n + 1))
    make_card "$dir" "$(printf '%010d.%d.card%02d' "$n" $((1759900000 + n * 60)) "$n")" "$text"
  done
}

# The date a list row shows for a card created at epoch $1.
drawer_date() {
  printf '%(%m-%d %H:%M)T' "$1"
}

# The number of columns inside the popup border. Row 1 is the ASCII tab bar.
drawer_width() {
  local line
  line=$(popup_lines | head -n 1)
  echo "${#line}"
}

# The titles in the list rows, from row 2 down to the first separator, with
# dates and padding left out. An empty list row shows as an empty field.
drawer_list() {
  popup_lines | awk 'NR > 1 && /^─/ { exit } NR > 1' |
    sed -E 's/ [0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} *$//; s/^ +//; s/ +$//' |
    paste -sd '|' -
}

drawer_list_is() {
  [[ $(drawer_list) == "$1" ]]
}

# The preview rows between the two separators, trailing blanks and blank
# rows at the bottom left out.
drawer_preview() {
  popup_lines | awk '/^─/ { n++; next } n == 1' | sed 's/ *$//' |
    sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}' | paste -sd '|' -
}

drawer_preview_is() {
  [[ $(drawer_preview) == "$1" ]]
}

# Matches row $1 against the glob pattern $2.
drawer_row_like() {
  [[ $(popup_line "$1") == $2 ]]
}

# vim marks the rows past the end of the file with '~'.
drawer_vim_shown() {
  popup_lines | grep -qx '~ *'
}

# --- e: edit -----------------------------------------------------------------

test_drawer_e_edits_a_one_line_card_in_a_prefilled_box() {
  local names
  start_host || return
  drawer_stack "$(cards_dir)" 'one' 'two' 'three'
  names=$(card_names "$(cards_dir)")
  open_drawer || return
  press j
  wait_for selected_is 'two' || fail "selected: $(selected), want two" || return
  press e
  wait_for popup_line_is 1 'Edit card (Enter saves, empty deletes)' ||
    fail "the edit box did not open: $(popup_line 1)" || return
  wait_for popup_line_is 2 '> two' || fail "box: $(popup_line 2), want: > two" || return
  press C-u
  type_text 'two edited'
  press Enter
  wait_for titles_are "$(cards_dir)" 'one|two edited|three' ||
    fail "cards: $(titles "$(cards_dir)"), want: one|two edited|three" || return
  wait_for selected_is 'two edited' || fail "selected: $(selected), want: two edited" || return
  wait_for drawer_list_is 'one|two edited|three' || fail "list: $(drawer_list)" || return
  card_names_are "$(cards_dir)" "$names" ||
    fail "names: $(card_names "$(cards_dir)"), want them unchanged: $names"
}

test_drawer_e_that_empties_a_card_removes_it() {
  start_host || return
  drawer_stack "$(cards_dir)" 'one' 'two' 'three'
  open_drawer || return
  press j
  wait_for selected_is 'two' || fail "selected: $(selected), want two" || return
  press e
  wait_for popup_line_is 2 '> two' || fail "box: $(popup_line 2), want: > two" || return
  press C-u
  press Enter
  wait_for titles_are "$(cards_dir)" 'one|three' ||
    fail "cards: $(titles "$(cards_dir)"), want: one|three" || return
  wait_for selected_is 'three' || fail "selected: $(selected), want three" || return
  wait_for drawer_list_is 'one|three' || fail "list: $(drawer_list), want: one|three" || return
  [[ $(card_count) == 2 ]] || fail "@cuecard-count: $(card_count), want 2"
}

test_drawer_e_on_a_multi_line_card_opens_vim() {
  local names
  start_host || return
  drawer_stack "$(cards_dir)" $'first line\nsecond line' 'other'
  names=$(card_names "$(cards_dir)")
  open_drawer || return
  press e
  wait_for drawer_vim_shown || fail "vim did not open" || return
  wait_for popup_line_is 1 'first line' && wait_for popup_line_is 2 'second line' ||
    fail "vim rows: $(popup_line 1)|$(popup_line 2), want: first line|second line" || return
  screen_lacks 'Edit card' || fail "the one-line box opened for a multi-line card" || return
  type_text ':q'
  press Enter
  wait_for drawer_drawn || fail "the drawer did not come back after vim" || return
  wait_for selected_is 'first line' || fail "selected: $(selected), want: first line" || return
  card_names_are "$(cards_dir)" "$names" ||
    fail "names: $(card_names "$(cards_dir)"), want them unchanged: $names" || return
  [[ $(cat "$(cards_dir)/${names%% *}") == $'first line\nsecond line' ]] ||
    fail "card text: $(cat "$(cards_dir)/${names%% *}"), want it unchanged"
}

# --- d, i, q -----------------------------------------------------------------

test_drawer_d_deletes_the_selected_card() {
  start_host || return
  drawer_stack "$(cards_dir)" 'one' 'two' 'three'
  open_drawer || return
  press j
  wait_for selected_is 'two' || fail "selected: $(selected), want two" || return
  press d
  wait_for titles_are "$(cards_dir)" 'one|three' ||
    fail "cards: $(titles "$(cards_dir)"), want: one|three" || return
  wait_for selected_is 'three' || fail "selected: $(selected), want three" || return
  wait_for drawer_list_is 'one|three' || fail "list: $(drawer_list), want: one|three" || return
  [[ $(card_count) == 2 ]] || fail "@cuecard-count: $(card_count), want 2"
}

test_drawer_d_on_the_last_row_selects_the_new_last_row() {
  start_host || return
  drawer_stack "$(cards_dir)" 'one' 'two' 'three'
  open_drawer || return
  press j j
  wait_for selected_is 'three' || fail "selected: $(selected), want three" || return
  press d
  wait_for titles_are "$(cards_dir)" 'one|two' ||
    fail "cards: $(titles "$(cards_dir)"), want: one|two" || return
  wait_for selected_is 'two' || fail "selected: $(selected), want two" || return
  wait_for drawer_list_is 'one|two' || fail "list: $(drawer_list), want: one|two"
}

test_drawer_i_adds_a_card_at_the_bottom_and_selects_it() {
  local name
  start_host || return
  drawer_stack "$(cards_dir)" 'one' 'two'
  open_drawer || return
  press i
  wait_for screen_has 'New card (Enter saves, empty cancels)' ||
    fail "the input box did not open" || return
  type_text 'three'
  press Enter
  wait_for titles_are "$(cards_dir)" 'one|two|three' ||
    fail "cards: $(titles "$(cards_dir)"), want: one|two|three" || return
  wait_for selected_is 'three' || fail "selected: $(selected), want three" || return
  wait_for drawer_list_is 'one|two|three' || fail "list: $(drawer_list), want: one|two|three" || return
  name=$(card_of 'three')
  [[ $name =~ ^0000000003\.[0-9]{10}\.[A-Za-z0-9]{6}$ ]] ||
    fail "new card name: $name, want 0000000003.<created>.<rand>"
}

test_drawer_q_and_esc_close_without_changes() {
  local names key
  start_host || return
  drawer_stack "$(cards_dir)" 'one' 'two'
  names=$(card_names "$(cards_dir)")
  for key in q Escape; do
    open_drawer || return
    press j
    wait_for selected_is 'two' || fail "selected: $(selected), want two" || return
    mark_paste
    press "$key"
    wait_for drawer_closed || fail "$key did not close the drawer" || return
    card_names_are "$(cards_dir)" "$names" ||
      fail "after $key, names: $(card_names "$(cards_dir)"), want: $names" || return
    pasted_is '' || fail "$key pasted: $(pasted)" || return
    [[ $(card_count) == 2 ]] || fail "after $key, @cuecard-count: $(card_count), want 2" || return
  done
}

# --- J and K -----------------------------------------------------------------

test_drawer_shift_k_at_the_top_and_shift_j_at_the_bottom_rename_nothing() {
  local dir names
  start_host || return
  dir=$(cards_dir)
  # Gaps in the orders, so a renumbering would show in the names.
  make_card "$dir" 0000000002.1759900060.card01 'one'
  make_card "$dir" 0000000005.1759900120.card02 'two'
  make_card "$dir" 0000000009.1759900180.card03 'three'
  names=$(card_names "$dir")
  open_drawer || return
  # Keys are read in order, so once j has moved the selection, K is done.
  press K j
  wait_for selected_is 'two' || fail "selected: $(selected), want two" || return
  card_names_are "$dir" "$names" || fail "K on the top card renamed: $(card_names "$dir")" || return
  press j
  wait_for selected_is 'three' || fail "selected: $(selected), want three" || return
  press J k
  wait_for selected_is 'two' || fail "selected: $(selected), want two" || return
  card_names_are "$dir" "$names" || fail "J on the bottom card renamed: $(card_names "$dir")" || return
  wait_for drawer_list_is 'one|two|three' || fail "list: $(drawer_list), want: one|two|three"
}

test_drawer_shift_k_order_persists_after_reopening() {
  start_host || return
  drawer_stack "$(cards_dir)" 'one' 'two' 'three'
  open_drawer || return
  press j j
  wait_for selected_is 'three' || fail "selected: $(selected), want three" || return
  press K
  wait_for titles_are "$(cards_dir)" 'one|three|two' ||
    fail "after K: $(titles "$(cards_dir)"), want: one|three|two" || return
  press K
  wait_for titles_are "$(cards_dir)" 'three|one|two' ||
    fail "after K K: $(titles "$(cards_dir)"), want: three|one|two" || return
  wait_for selected_is 'three' || fail "selected: $(selected), want three" || return
  close_drawer || return
  open_drawer || return
  wait_for drawer_list_is 'three|one|two' ||
    fail "reopened list: $(drawer_list), want: three|one|two" || return
  wait_for selected_is 'three' || fail "reopened selection: $(selected), want three" || return
  wait_for drawer_row_like 2 " three * $(drawer_date 1759900180)" ||
    fail "row 2: $(popup_line 2), want the date $(drawer_date 1759900180)" || return
  card_names_are "$(cards_dir)" '0000000001.1759900180.card03 0000000002.1759900060.card01 0000000003.1759900120.card02' ||
    fail "names: $(card_names "$(cards_dir)")"
}

# --- legacy and odd names ----------------------------------------------------

test_drawer_legacy_names_list_in_order_dated_by_their_epoch() {
  local dir names
  start_host || return
  dir=$(cards_dir)
  make_card "$dir" 1759900000.aaaaaa 'legacy one'
  make_card "$dir" 1759903600.bbbbbb 'legacy two'
  make_card "$dir" 1759990000.cccccc 'legacy three'
  names=$(card_names "$dir")
  open_drawer || return
  wait_for drawer_list_is 'legacy one|legacy two|legacy three' ||
    fail "list: $(drawer_list), want: legacy one|legacy two|legacy three" || return
  wait_for drawer_row_like 2 " legacy one * $(drawer_date 1759900000)" ||
    fail "row 2: $(popup_line 2), want the date $(drawer_date 1759900000)" || return
  wait_for drawer_row_like 3 " legacy two * $(drawer_date 1759903600)" ||
    fail "row 3: $(popup_line 3), want the date $(drawer_date 1759903600)" || return
  wait_for drawer_row_like 4 " legacy three * $(drawer_date 1759990000)" ||
    fail "row 4: $(popup_line 4), want the date $(drawer_date 1759990000)" || return
  card_names_are "$dir" "$names" || fail "opening renamed the cards: $(card_names "$dir")"
}

# Older versions could write two cards in the same second, which then share
# their order key.
test_drawer_moving_same_second_legacy_cards_renumbers_the_stack() {
  local dir
  start_host || return
  dir=$(cards_dir)
  make_card "$dir" 1759900000.aaaaaa 'legacy one'
  make_card "$dir" 1759900100.bbbbbb 'tie B'
  make_card "$dir" 1759900100.zzzzzz 'tie Z'
  open_drawer || return
  wait_for drawer_list_is 'legacy one|tie B|tie Z' || fail "list: $(drawer_list)" || return
  press j
  wait_for selected_is 'tie B' || fail "selected: $(selected), want: tie B" || return
  press J
  wait_for card_names_are "$dir" '0000000001.1759900000.aaaaaa 0000000002.1759900100.zzzzzz 0000000003.1759900100.bbbbbb' ||
    fail "after J, names: $(card_names "$dir")" || return
  wait_for selected_is 'tie B' || fail "selected: $(selected), want: tie B" || return
  wait_for drawer_list_is 'legacy one|tie Z|tie B' ||
    fail "list: $(drawer_list), want: legacy one|tie Z|tie B" || return
  wait_for drawer_row_like 4 " tie B * $(drawer_date 1759900100)" ||
    fail "row 4: $(popup_line 4), want the date $(drawer_date 1759900100)" || return
  press K
  wait_for card_names_are "$dir" '0000000001.1759900000.aaaaaa 0000000002.1759900100.bbbbbb 0000000003.1759900100.zzzzzz' ||
    fail "after K, names: $(card_names "$dir")"
}

# Bash reads 08 and 09 as bad octal numbers unless told the base.
test_drawer_order_keys_8_and_9_sort_move_and_the_next_card_gets_10() {
  local dir name
  start_host || return
  dir=$(cards_dir)
  make_card "$dir" 0000000008.1759900000.aaaaaa 'eight'
  make_card "$dir" 0000000009.1759900060.bbbbbb 'nine'
  open_drawer || return
  wait_for drawer_list_is 'eight|nine' || fail "list: $(drawer_list), want: eight|nine" || return
  press i
  wait_for screen_has 'New card (Enter saves, empty cancels)' ||
    fail "the input box did not open" || return
  type_text 'ten'
  press Enter
  wait_for titles_are "$dir" 'eight|nine|ten' ||
    fail "cards: $(titles "$dir"), want: eight|nine|ten" || return
  name=$(card_of 'ten')
  [[ $name == 0000000010.* ]] || fail "new card name: $name, want order 0000000010" || return
  wait_for selected_is 'ten' || fail "selected: $(selected), want ten" || return
  press k K
  wait_for card_names_are "$dir" "0000000001.1759900060.bbbbbb 0000000002.1759900000.aaaaaa 0000000003.${name#*.}" ||
    fail "after K on nine, names: $(card_names "$dir")" || return
  wait_for selected_is 'nine' || fail "selected: $(selected), want nine" || return
  wait_for drawer_list_is 'nine|eight|ten' || fail "list: $(drawer_list), want: nine|eight|ten"
}

# --- drawing -----------------------------------------------------------------

test_drawer_preview_shows_the_selected_card_in_full_and_wraps_long_lines() {
  local digits long w
  printf -v digits '%s' {0..9}{0..9}
  long=${digits:0:90}
  start_host || return
  drawer_stack "$(cards_dir)" 'first card' $'second card\n'"$long"$'\nlast line'
  open_drawer || return
  wait_for drawer_preview_is 'first card' || fail "preview: $(drawer_preview), want: first card" || return
  w=$(drawer_width)
  press j
  wait_for drawer_preview_is "second card|${long:0:w}|${long:w:w}|${long:2*w}|last line" ||
    fail "preview: $(drawer_preview)" || return
  press k
  wait_for drawer_preview_is 'first card' || fail "preview after k: $(drawer_preview), want: first card"
}

test_drawer_narrower_than_24_columns_drops_the_dates() {
  local long='an ascii title that is too long'
  start_host 'set -g @cuecard-width 25' || return
  drawer_stack "$(cards_dir)" 'short' "$long"
  open_drawer || return
  [[ $(drawer_width) == 23 ]] || fail "drawer width: $(drawer_width), want 23" || return
  wait_for popup_line_is 3 " ${long:0:22}" ||
    fail "row 3: $(popup_line 3), want the title across the full width: ${long:0:22}" || return
  wait_for popup_line_is 2 ' short' || fail "row 2: $(popup_line 2), want: ' short'" || return
  ! popup_lines | grep -qE '[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' ||
    fail "a row shows a date: $(popup_lines | grep -E '[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}')"
}

test_drawer_24_columns_wide_shows_the_dates() {
  local long='an ascii title that is too long' want2 want3
  start_host 'set -g @cuecard-width 26' || return
  drawer_stack "$(cards_dir)" 'short' "$long"
  open_drawer || return
  [[ $(drawer_width) == 24 ]] || fail "drawer width: $(drawer_width), want 24" || return
  # 24 columns leave 11 for the title, next to the 13 of ' MM-DD HH:MM '.
  printf -v want2 '%-11s %s' ' short' "$(drawer_date 1759900060)"
  want3=" ${long:0:10} $(drawer_date 1759900120)"
  wait_for popup_line_is 2 "$want2" || fail "row 2: '$(popup_line 2)', want: '$want2'" || return
  wait_for popup_line_is 3 "$want3" || fail "row 3: '$(popup_line 3)', want: '$want3'"
}

test_drawer_footer_is_clipped_not_wrapped_when_narrow() {
  local want
  start_host 'set -g @cuecard-width 22' || return
  drawer_stack "$(cards_dir)" 'one'
  open_drawer || return
  [[ $(drawer_width) == 20 ]] || fail "drawer width: $(drawer_width), want 20" || return
  want=' Enter pick   p pop| e edit   d delete| c save   Tab saved| J/K move   m to win'
  wait_for footer_is "$want" || fail "footer: $(footer), want: $want" || return
  # A wrapped last row would scroll the drawer up and take the tab bar away.
  wait_for popup_line_is 1 ' window 1   saved 0' || fail "row 1: $(popup_line 1)" || return
  popup_lacks 'i new' && popup_lacks 'q quit' ||
    fail "the clipped end of a footer line shows up: $(popup_lines | paste -sd '|' -)"
}

test_drawer_window_footer_lists_the_keys() {
  local want
  start_host || return
  drawer_stack "$(cards_dir)" 'one'
  open_drawer || return
  want=' Enter pick   p pop   i new| e edit   d delete   q quit| c save   Tab saved| J/K move   m to window'
  wait_for footer_is "$want" || fail "footer: $(footer), want: $want"
}

# Rows are 38 columns wide here, which leaves 25 for the title.
test_drawer_korean_titles_keep_the_date_right_aligned() {
  local want2 want3
  start_host || return
  drawer_stack "$(cards_dir)" '한국어로 쓴 긴 카드 제목입니다' 'a가나다라마바사아자차카타파하'
  open_drawer || return
  [[ $(drawer_width) == 38 ]] || fail "drawer width: $(drawer_width), want 38" || return
  # The first title fills the 25 columns exactly. In the second, the next
  # wide character would straddle the edge, so a blank takes its place.
  want2=" 한국어로 쓴 긴 카드 제목 $(drawer_date 1759900060)"
  want3=" a가나다라마바사아자차카  $(drawer_date 1759900120)"
  wait_for popup_line_is 2 "$want2" || fail "row 2: '$(popup_line 2)', want: '$want2'" || return
  wait_for popup_line_is 3 "$want3" || fail "row 3: '$(popup_line 3)', want: '$want3'"
}

# fit() used to count U+2705 and U+1F680 as one column each, which pushed
# the end of the date out of the row and cut the preview short.
test_drawer_emoji_count_as_two_columns_in_rows_and_preview() {
  local text='✅ done 🚀 ship it and then some more words here' want
  start_host || return
  drawer_stack "$(cards_dir)" "$text"
  open_drawer || return
  [[ $(drawer_width) == 38 ]] || fail "drawer width: $(drawer_width), want 38" || return
  want=" ✅ done 🚀 ship it and t $(drawer_date 1759900060)"
  wait_for popup_line_is 2 "$want" || fail "row 2: '$(popup_line 2)', want: '$want'" || return
  want='✅ done 🚀 ship it and then some more|words here'
  wait_for drawer_preview_is "$want" || fail "preview: $(drawer_preview), want: $want"
}

# --- scrolling and short drawers ---------------------------------------------

# A 16-row client leaves the drawer three list rows.
test_drawer_j_scrolls_a_list_longer_than_its_rows() {
  ROWS=16 start_host || return
  drawer_stack "$(cards_dir)" 'card 1' 'card 2' 'card 3' 'card 4' 'card 5' 'card 6'
  open_drawer || return
  wait_for drawer_list_is 'card 1|card 2|card 3' || fail "list: $(drawer_list)" || return
  press j j j
  wait_for selected_is 'card 4' || fail "selected: $(selected), want: card 4" || return
  wait_for drawer_list_is 'card 2|card 3|card 4' ||
    fail "list: $(drawer_list), want: card 2|card 3|card 4" || return
  press j j
  wait_for selected_is 'card 6' || fail "selected: $(selected), want: card 6" || return
  wait_for drawer_list_is 'card 4|card 5|card 6' ||
    fail "list: $(drawer_list), want: card 4|card 5|card 6" || return
  press k k k
  wait_for selected_is 'card 3' || fail "selected: $(selected), want: card 3" || return
  wait_for drawer_list_is 'card 3|card 4|card 5' ||
    fail "list: $(drawer_list), want: card 3|card 4|card 5"
}

test_drawer_deleting_at_the_bottom_of_a_scrolled_list_scrolls_back() {
  ROWS=16 start_host || return
  drawer_stack "$(cards_dir)" 'card 1' 'card 2' 'card 3' 'card 4' 'card 5' 'card 6'
  open_drawer || return
  press j j j j j
  wait_for selected_is 'card 6' || fail "selected: $(selected), want: card 6" || return
  wait_for drawer_list_is 'card 4|card 5|card 6' || fail "list: $(drawer_list)" || return
  press d
  wait_for titles_are "$(cards_dir)" 'card 1|card 2|card 3|card 4|card 5' ||
    fail "cards: $(titles "$(cards_dir)")" || return
  wait_for drawer_list_is 'card 3|card 4|card 5' ||
    fail "list: $(drawer_list), want: card 3|card 4|card 5" || return
  wait_for selected_is 'card 5' || fail "selected: $(selected), want: card 5" || return
  press d
  wait_for drawer_list_is 'card 2|card 3|card 4' ||
    fail "list: $(drawer_list), want: card 2|card 3|card 4" || return
  wait_for selected_is 'card 4' || fail "selected: $(selected), want: card 4"
}

# A client of 3 rows leaves the drawer only its tab bar, one of 4 rows the
# tab bar and one list row: that one-row list used to crash the drawer.
test_drawer_very_short_drawers_keep_the_tab_bar_on_row_1() {
  local rows
  for rows in 3 4 5 6 7 8; do
    ROWS=$rows start_host || return
    drawer_stack "$(cards_dir)" 'card one' 'card two'
    open_drawer || fail "with $rows rows" || return
    wait_for popup_line_is 1 ' window 2   saved 0' ||
      fail "with $rows rows, row 1: $(popup_line 1)" || return
    if ((rows > 3)); then
      wait_for selected_is 'card one' ||
        fail "with $rows rows, selected: $(selected), want: card one" || return
    fi
    press j d
    wait_for titles_are "$(cards_dir)" 'card one' ||
      fail "with $rows rows, cards: $(titles "$(cards_dir)"), want: card one" || return
    # The tab bar counts the cards, so it shows the drawer drew again.
    wait_for popup_line_is 1 ' window 1   saved 0' ||
      fail "with $rows rows, row 1 after d: $(popup_line 1)" || return
    if ((rows > 3)); then
      wait_for selected_is 'card one' ||
        fail "with $rows rows, selected after d: $(selected), want: card one" || return
    fi
    close_drawer || fail "with $rows rows" || return
  done
}
