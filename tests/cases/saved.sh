# Saved cards: the collection every window shares, shown in the drawer's
# saved view. The tab bar, switching views, writing, pasting, deleting,
# editing, reordering and copying saved cards, and where they are kept.

saved_window_footer=' Enter pick   p pop   i new| e edit   d delete   q quit| c save   Tab saved| J/K move   m to window'
saved_view_footer=' Enter pick   c to window| i new   e edit   q quit| J/K move   Tab window| d delete'
saved_new_prompt='New saved card (Enter saves, empty cancels)'
# A drawer of the default 40% on a 100-column client is 38 columns wide,
# which wraps the input box prompts, so the tests that read them widen it.
saved_wide='set -g @cuecard-width 60'

# --- helpers -----------------------------------------------------------------

# The label of the tab drawn in bold, which names the open view, trimmed.
saved_active_tab() {
  popup_lines -e | head -n 1 |
    sed -nE $'s/.*\e\\[([0-9;]*;)?1m([^\e]*).*/\\2/p' | sed 's/^ *//; s/ *$//'
}

saved_view_is() {
  [[ $(saved_active_tab) == "$1 "* ]]
}

# The first footer line, where the drawer says what a key did.
saved_first_footer_line_is() {
  [[ $(footer | cut -d '|' -f 1) == "$1" ]]
}

# The input box in the drawer is open once readline has drawn its '> '
# under prompt $1, so keys typed from then on reach readline.
saved_box_open() {
  [[ $(popup_line 1) == "$1" && $(popup_line 2) == '>'* ]]
}

saved_now() {
  printf '%(%s)T' -1
}

# The last card of directory $1 in stack order.
saved_last_card() {
  local files=("$1"/*)
  [[ -e ${files[-1]} ]] && printf '%s\n' "${files[-1]}"
}

# Every card of directory $1 by name and checksum, to tell that nothing in
# it changed.
saved_fingerprint() {
  local file
  for file in "$1"/*; do
    [[ -e $file ]] && printf '%s %s\n' "${file##*/}" "$(cksum < "$file")"
  done | paste -sd '|' -
}

# Opens the drawer and switches it to the saved view.
saved_open_view() {
  open_drawer || return
  press Tab
  wait_for saved_view_is saved ||
    fail "Tab did not open the saved view, active tab: '$(saved_active_tab)'"
}

# Writes card $1 with the input box of the open saved view.
saved_write_with_i() {
  press i
  wait_for saved_box_open "$saved_new_prompt" ||
    fail "i did not open the box, row 1: '$(popup_line 1)'" || return
  type_text "$1"
  press Enter
  wait_for saved_view_is saved || fail "the drawer did not come back to the saved view"
}

# --- tab bar and views -------------------------------------------------------

test_saved_tab_bar_shows_both_counts_and_the_drawer_opens_on_the_window_view() {
  start_host || return
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'window one'
  make_card "$(cards_dir)" 0000000002.1759900060.bbbbbb 'window two'
  make_card "$SAVED_DIR" 0000000001.1759900000.cccccc 'saved one'
  make_card "$SAVED_DIR" 0000000002.1759900060.dddddd 'saved two'
  make_card "$SAVED_DIR" 0000000003.1759900120.eeeeee 'saved three'
  open_drawer || return
  [[ $(popup_line 1) == ' window 2   saved 3' ]] ||
    fail "tab bar: '$(popup_line 1)', want ' window 2   saved 3'" || return
  [[ $(saved_active_tab) == 'window 2' ]] ||
    fail "active tab: '$(saved_active_tab)', want 'window 2'" || return
  [[ $(selected) == 'window one' ]] || fail "selected: '$(selected)'" || return
  # The count of the hidden view comes from its directory, so a card that
  # another drawer or tmux server saves shows up on the next redraw.
  make_card "$SAVED_DIR" 0000000004.1759900180.ffffff 'saved four'
  press j
  wait_for popup_line_is 1 ' window 2   saved 4' ||
    fail "tab bar after another drawer saved a card: '$(popup_line 1)'" || return
  press Tab
  wait_for saved_view_is saved ||
    fail "Tab did not open the saved view, active tab: '$(saved_active_tab)'" || return
  [[ $(popup_line 1) == ' window 2   saved 4' ]] ||
    fail "saved view tab bar: '$(popup_line 1)', want ' window 2   saved 4'" || return
  [[ $(selected) == 'saved one' ]] || fail "saved view selected: '$(selected)'" || return
  footer_is "$saved_view_footer" ||
    fail "saved view footer: '$(footer)'" || return
  # Closed from the saved view, the drawer still opens on the window view.
  close_drawer || return
  open_drawer || return
  [[ $(saved_active_tab) == 'window 2' ]] ||
    fail "reopened on '$(saved_active_tab)', want 'window 2'" || return
  [[ $(selected) == 'window one' ]] || fail "reopened selected: '$(selected)'" || return
  footer_is "$saved_window_footer" ||
    fail "reopened footer: '$(footer)'"
}

test_saved_tab_and_shift_tab_switch_views_and_each_view_keeps_its_selection() {
  start_host || return
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'w1'
  make_card "$(cards_dir)" 0000000002.1759900060.bbbbbb 'w2'
  make_card "$(cards_dir)" 0000000003.1759900120.cccccc 'w3'
  make_card "$SAVED_DIR" 0000000001.1759900000.dddddd 's1'
  make_card "$SAVED_DIR" 0000000002.1759900060.eeeeee 's2'
  make_card "$SAVED_DIR" 0000000003.1759900120.ffffff 's3'
  open_drawer || return
  press j
  wait_for selected_is 'w2' || fail "window view selected: '$(selected)'" || return
  press Tab
  wait_for saved_view_is saved || fail "Tab: active tab '$(saved_active_tab)'" || return
  [[ $(selected) == 's1' ]] || fail "saved view first opened on '$(selected)'" || return
  press j
  press j
  wait_for selected_is 's3' || fail "saved view selected: '$(selected)'" || return
  press Tab
  wait_for saved_view_is window || fail "Tab back: active tab '$(saved_active_tab)'" || return
  [[ $(selected) == 'w2' ]] || fail "window view came back on '$(selected)', want w2" || return
  press BTab
  wait_for saved_view_is saved || fail "BTab: active tab '$(saved_active_tab)'" || return
  [[ $(selected) == 's3' ]] || fail "saved view came back on '$(selected)', want s3" || return
  press BTab
  wait_for saved_view_is window || fail "BTab back: active tab '$(saved_active_tab)'" || return
  [[ $(selected) == 'w2' ]] || fail "window view came back on '$(selected)', want w2"
}

# ' window 1' and ' saved 2' with the gap between them take 19 columns.
test_saved_narrow_drawer_shows_only_the_active_tab() {
  start_host 'set -g @cuecard-width 20' || return
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'window card'
  make_card "$SAVED_DIR" 0000000001.1759900000.bbbbbb 'saved one'
  make_card "$SAVED_DIR" 0000000002.1759900060.cccccc 'saved two'
  open_drawer || return
  [[ $(popup_line 1) == ' window 1' ]] ||
    fail "18 columns, window view tab bar: '$(popup_line 1)', want ' window 1'" || return
  press Tab
  wait_for popup_line_is 1 ' saved 2' ||
    fail "18 columns, saved view tab bar: '$(popup_line 1)', want ' saved 2'" || return
  [[ $(saved_active_tab) == 'saved 2' ]] || fail "active tab: '$(saved_active_tab)'" || return
  close_drawer || return
  # One column wider, both tabs fit again.
  host set -g @cuecard-width 21
  load_plugin
  open_drawer || return
  [[ $(popup_line 1) == ' window 1   saved 2' ]] ||
    fail "19 columns, tab bar: '$(popup_line 1)', want ' window 1   saved 2'"
}

test_saved_empty_view_shows_the_hint_and_the_saved_footer() {
  start_host || return
  saved_open_view || return
  [[ $(popup_line 1) == ' window 0   saved 0' ]] || fail "tab bar: '$(popup_line 1)'" || return
  [[ $(popup_line 2) == ' (empty) press i to add' ]] || fail "row 2: '$(popup_line 2)'" || return
  [[ $(popup_line 3) == ' or c in the window view' ]] || fail "row 3: '$(popup_line 3)'" || return
  [[ -z $(selected) ]] || fail "selected: '$(selected)', want nothing" || return
  footer_is "$saved_view_footer" ||
    fail "footer: '$(footer)', want '$saved_view_footer'"
}

# --- writing -----------------------------------------------------------------

test_saved_dir_is_created_on_the_first_write_with_order_created_rand_names() {
  start_host "$saved_wide" || return
  saved_open_view || return
  [[ ! -e $SAVED_DIR ]] || fail "opening the saved view created $SAVED_DIR" || return
  press i
  wait_for saved_box_open "$saved_new_prompt" || fail "box row 1: '$(popup_line 1)'" || return
  press Enter
  wait_for saved_view_is saved || fail "an empty box did not go back to the drawer" || return
  [[ ! -e $SAVED_DIR ]] || fail "an empty card created $SAVED_DIR" || return
  local t0 t1 name re='^0000000001\.([0-9]+)\.[A-Za-z0-9]{6}$'
  t0=$(saved_now)
  saved_write_with_i 'first saved' || return
  wait_for titles_are "$SAVED_DIR" 'first saved' ||
    fail "saved cards: '$(titles "$SAVED_DIR")'" || return
  t1=$(saved_now)
  name=$(card_names "$SAVED_DIR")
  [[ $name =~ $re ]] || fail "name: '$name', want 0000000001.<created>.<rand>" || return
  ((BASH_REMATCH[1] >= t0 && BASH_REMATCH[1] <= t1)) ||
    fail "created ${BASH_REMATCH[1]}, want between $t0 and $t1" || return
  printf 'first saved\n' | cmp -s - "$SAVED_DIR/$name" ||
    fail "content: $(od -c "$SAVED_DIR/$name" | head -n 2)" || return
  [[ -z $(card_names "$(cards_dir)") ]] || fail "window cards: $(card_names "$(cards_dir)")"
}

test_saved_i_selects_the_new_saved_card_and_keeps_the_window_count() {
  start_host "$saved_wide" || return
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'window card'
  make_card "$SAVED_DIR" 0000000001.1759900000.bbbbbb 'saved one'
  make_card "$SAVED_DIR" 0000000002.1759900060.cccccc 'saved two'
  saved_open_view || return
  [[ $(card_count) == 1 ]] || fail "count before: '$(card_count)'" || return
  press i
  wait_for saved_box_open "$saved_new_prompt" ||
    fail "box row 1: '$(popup_line 1)', want '$saved_new_prompt'" || return
  type_text 'saved three'
  press Enter
  wait_for selected_is 'saved three' || fail "selected: '$(selected)'" || return
  [[ $(titles "$SAVED_DIR") == 'saved one|saved two|saved three' ]] ||
    fail "saved cards: '$(titles "$SAVED_DIR")'" || return
  [[ $(saved_last_card "$SAVED_DIR") == "$SAVED_DIR"/0000000003.* ]] ||
    fail "bottom card: $(saved_last_card "$SAVED_DIR"), want order 0000000003" || return
  [[ $(popup_line 1) == ' window 1   saved 3' ]] || fail "tab bar: '$(popup_line 1)'" || return
  [[ $(card_count) == 1 ]] || fail "count after: '$(card_count)', want 1" || return
  [[ $(titles "$(cards_dir)") == 'window card' ]] ||
    fail "window cards: '$(titles "$(cards_dir)")'"
}

test_saved_prefix_a_still_writes_a_window_card() {
  start_host || return
  make_card "$SAVED_DIR" 0000000001.1759900000.aaaaaa 'template'
  saved_open_view || return
  close_drawer || return
  press C-b A
  wait_for screen_has 'New card (Enter saves, empty cancels)' ||
    fail "prefix+A did not open the window box" || return
  screen_lacks 'New saved card' || fail "prefix+A opened the saved box" || return
  type_text 'from prefix a'
  press Enter
  wait_for titles_are "$(cards_dir)" 'from prefix a' ||
    fail "window cards: '$(titles "$(cards_dir)")'" || return
  [[ $(titles "$SAVED_DIR") == 'template' ]] ||
    fail "saved cards: '$(titles "$SAVED_DIR")', want only 'template'" || return
  [[ $(card_count) == 1 ]] || fail "count: '$(card_count)', want 1"
}

# --- pasting -----------------------------------------------------------------

test_saved_enter_pastes_the_saved_card_and_keeps_it() {
  start_host || return
  make_card "$SAVED_DIR" 0000000001.1759900000.aaaaaa 'first template'
  make_card "$SAVED_DIR" 0000000002.1759900060.bbbbbb 'second template'
  local before
  before=$(saved_fingerprint "$SAVED_DIR")
  saved_open_view || return
  press j
  wait_for selected_is 'second template' || fail "selected: '$(selected)'" || return
  mark_paste
  press Enter
  wait_for drawer_closed || fail "Enter did not close the drawer" || return
  wait_for pasted_is "$(bracketed 'second template')" ||
    fail "pasted: $(pasted), want: $(bracketed 'second template')" || return
  [[ $(saved_fingerprint "$SAVED_DIR") == "$before" ]] ||
    fail "saved cards changed: $(card_names "$SAVED_DIR")" || return
  [[ -z $(card_names "$(cards_dir)") ]] || fail "window cards: $(card_names "$(cards_dir)")"
}

# p would pop the card and m would open the window picker. Neither shows
# anything in the saved view, so j after them proves the drawer read them.
test_saved_p_and_m_do_nothing_in_the_saved_view() {
  start_host || return
  local other before
  other=$(new_window other)
  make_card "$SAVED_DIR" 0000000001.1759900000.aaaaaa 'one'
  make_card "$SAVED_DIR" 0000000002.1759900060.bbbbbb 'two'
  before=$(saved_fingerprint "$SAVED_DIR")
  saved_open_view || return
  mark_paste
  press p
  press m
  press j
  wait_for selected_is 'two' ||
    fail "after p m j, selected: '$(selected)', want 'two'" || return
  saved_view_is saved || fail "active tab: '$(saved_active_tab)'" || return
  popup_lacks 'Move to window' || fail "m opened the window picker" || return
  [[ -z $(pasted) ]] || fail "pasted: $(pasted)" || return
  [[ $(saved_fingerprint "$SAVED_DIR") == "$before" ]] ||
    fail "saved cards changed: $(card_names "$SAVED_DIR")" || return
  [[ -z $(card_names "$(cards_dir "$other")") ]] ||
    fail "cards of the other window: $(card_names "$(cards_dir "$other")")"
}

# --- deleting, editing, reordering -------------------------------------------

test_saved_d_asks_first_and_only_a_second_d_deletes() {
  start_host || return
  make_card "$SAVED_DIR" 0000000001.1759900000.aaaaaa 'keep me'
  make_card "$SAVED_DIR" 0000000002.1759900060.bbbbbb 'delete me'
  make_card "$SAVED_DIR" 0000000003.1759900120.cccccc 'last'
  local asking=' Press d again to delete| i new   e edit   q quit| J/K move   Tab window| d delete'
  saved_open_view || return
  press j
  wait_for selected_is 'delete me' || fail "selected: '$(selected)'" || return
  press d
  wait_for footer_is "$asking" || fail "footer after d: '$(footer)'" || return
  [[ $(titles "$SAVED_DIR") == 'keep me|delete me|last' ]] ||
    fail "one d deleted a card: '$(titles "$SAVED_DIR")'" || return
  # Any other key keeps the card, and is not acted on.
  press j
  wait_for footer_is "$saved_view_footer" ||
    fail "footer after d j: '$(footer)'" || return
  [[ $(titles "$SAVED_DIR") == 'keep me|delete me|last' ]] ||
    fail "d j deleted a card: '$(titles "$SAVED_DIR")'" || return
  [[ $(selected) == 'delete me' ]] ||
    fail "the j that cancelled moved the selection to '$(selected)'" || return
  press d
  wait_for footer_is "$asking" || fail "footer after the second d: '$(footer)'" || return
  press d
  wait_for titles_are "$SAVED_DIR" 'keep me|last' ||
    fail "after d d: '$(titles "$SAVED_DIR")', want 'keep me|last'" || return
  wait_for popup_line_is 1 ' window 0   saved 2' || fail "tab bar: '$(popup_line 1)'" || return
  [[ $(selected) == 'last' ]] || fail "selected after the delete: '$(selected)'" || return
  footer_is "$saved_view_footer" || fail "footer: '$(footer)'"
}

test_saved_e_edits_the_saved_card_in_place() {
  start_host "$saved_wide" || return
  make_card "$SAVED_DIR" 0000000001.1759900000.aaaaaa 'old text'
  saved_open_view || return
  press e
  wait_for popup_line_is 1 'Edit saved card (Enter saves, empty deletes)' ||
    fail "e box row 1: '$(popup_line 1)'" || return
  wait_for popup_line_is 2 '> old text' || fail "e box row 2: '$(popup_line 2)'" || return
  press C-u
  type_text 'new text'
  press Enter
  wait_for selected_is 'new text' || fail "selected: '$(selected)'" || return
  [[ $(card_names "$SAVED_DIR") == 0000000001.1759900000.aaaaaa ]] ||
    fail "saved cards: '$(card_names "$SAVED_DIR")', want the same name" || return
  printf 'new text\n' | cmp -s - "$SAVED_DIR/0000000001.1759900000.aaaaaa" ||
    fail "content: $(od -c "$SAVED_DIR/0000000001.1759900000.aaaaaa" | head -n 2)"
}

test_saved_shift_j_and_k_reorder_saved_cards_and_persist() {
  start_host || return
  make_card "$SAVED_DIR" 0000000001.1759900000.aaaaaa 'one'
  make_card "$SAVED_DIR" 0000000002.1759900060.bbbbbb 'two'
  make_card "$SAVED_DIR" 0000000003.1759900120.cccccc 'three'
  saved_open_view || return
  press J
  wait_for titles_are "$SAVED_DIR" 'two|one|three' ||
    fail "after J: '$(titles "$SAVED_DIR")'" || return
  press J
  wait_for titles_are "$SAVED_DIR" 'two|three|one' ||
    fail "after J J: '$(titles "$SAVED_DIR")'" || return
  press K
  wait_for titles_are "$SAVED_DIR" 'two|one|three' ||
    fail "after J J K: '$(titles "$SAVED_DIR")'" || return
  wait_for selected_is 'one' || fail "selected: '$(selected)', want 'one'" || return
  # Each card keeps its <created>.<rand> and takes a new <order>.
  local want='0000000001.1759900060.bbbbbb 0000000002.1759900000.aaaaaa 0000000003.1759900120.cccccc'
  [[ $(card_names "$SAVED_DIR") == "$want" ]] ||
    fail "names: '$(card_names "$SAVED_DIR")', want '$want'" || return
  close_drawer || return
  saved_open_view || return
  [[ $(popup_line 2) == ' two'* && $(popup_line 3) == ' one'* && $(popup_line 4) == ' three'* ]] ||
    fail "reopened rows: '$(popup_line 2)' '$(popup_line 3)' '$(popup_line 4)'"
}

# --- copying -----------------------------------------------------------------

test_saved_c_in_the_window_view_copies_the_card_to_the_saved_cards() {
  start_host || return
  local source copy t0 t1 before re='^0000000002\.([0-9]+)\.([A-Za-z0-9]{6})$'
  source="$(cards_dir)/0000000001.1759900000.aaaaaa"
  mkdir -p "$(cards_dir)"
  # Bytes a copy could lose: a tab, trailing blanks, no final newline.
  printf 'queue me\n\tindented  \nno newline at the end' > "$source"
  make_card "$SAVED_DIR" 0000000001.1759900060.bbbbbb 'existing'
  before=$(saved_fingerprint "$(cards_dir)")
  open_drawer || return
  t0=$(saved_now)
  press c
  wait_for saved_first_footer_line_is ' Saved' ||
    fail "footer after c: '$(footer)'" || return
  t1=$(saved_now)
  copy=$(saved_last_card "$SAVED_DIR")
  [[ ${copy##*/} =~ $re ]] ||
    fail "copy: '${copy##*/}', want 0000000002.<created>.<rand> at the bottom" || return
  ((BASH_REMATCH[1] >= t0 && BASH_REMATCH[1] <= t1)) ||
    fail "copy created ${BASH_REMATCH[1]}, want between $t0 and $t1" || return
  [[ ${BASH_REMATCH[2]} != aaaaaa ]] || fail "the copy kept the <rand> of the card" || return
  cmp -s "$source" "$copy" ||
    fail "the copy differs: $(od -c "$copy" | head -n 3)" || return
  [[ $(saved_fingerprint "$(cards_dir)") == "$before" ]] ||
    fail "window cards changed: $(card_names "$(cards_dir)")" || return
  [[ $(card_count) == 1 ]] || fail "count: '$(card_count)', want 1" || return
  [[ $(popup_line 1) == ' window 1   saved 2' ]] || fail "tab bar: '$(popup_line 1)'" || return
  [[ $(saved_active_tab) == 'window 1' ]] || fail "c switched the view to '$(saved_active_tab)'"
}

test_saved_c_in_the_saved_view_adds_the_card_to_the_window() {
  start_host || return
  local source copy t0 t1 before re='^0000000002\.([0-9]+)\.([A-Za-z0-9]{6})$'
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'window card'
  source="$SAVED_DIR/0000000001.1759900060.bbbbbb"
  mkdir -p "$SAVED_DIR"
  printf 'saved\ttemplate  \nsecond line' > "$source"
  before=$(saved_fingerprint "$SAVED_DIR")
  saved_open_view || return
  [[ $(card_count) == 1 ]] || fail "count before: '$(card_count)'" || return
  t0=$(saved_now)
  press c
  wait_for saved_first_footer_line_is ' Added to window' ||
    fail "footer after c: '$(footer)'" || return
  t1=$(saved_now)
  copy=$(saved_last_card "$(cards_dir)")
  [[ ${copy##*/} =~ $re ]] ||
    fail "copy: '${copy##*/}', want 0000000002.<created>.<rand> at the bottom" || return
  ((BASH_REMATCH[1] >= t0 && BASH_REMATCH[1] <= t1)) ||
    fail "copy created ${BASH_REMATCH[1]}, want between $t0 and $t1" || return
  [[ ${BASH_REMATCH[2]} != bbbbbb ]] || fail "the copy kept the <rand> of the card" || return
  cmp -s "$source" "$copy" ||
    fail "the copy differs: $(od -c "$copy" | head -n 3)" || return
  [[ $(card_count) == 2 ]] || fail "count after: '$(card_count)', want 2" || return
  [[ $(saved_fingerprint "$SAVED_DIR") == "$before" ]] ||
    fail "saved cards changed: $(card_names "$SAVED_DIR")" || return
  [[ $(popup_line 1) == ' window 2   saved 1' ]] || fail "tab bar: '$(popup_line 1)'" || return
  saved_view_is saved || fail "c switched the view to '$(saved_active_tab)'"
}

# --- storage -----------------------------------------------------------------

# A card saved from a window outlives that window, and the plugin load that
# drops the cards of dead servers leaves the saved cards alone.
test_saved_cards_survive_closing_a_window_and_the_plugin_load_cleanup() {
  start_host || return
  local other before dead
  other=$(new_window other)
  host select-window -t "$other"
  wait_for status_has '1:other*' || fail "status line: $(status_line)" || return
  make_card "$(cards_dir "$other")" 0000000001.1759900000.aaaaaa 'card of other'
  open_drawer || return
  press c
  wait_for saved_first_footer_line_is ' Saved' || fail "footer after c: '$(footer)'" || return
  close_drawer || return
  [[ $(titles "$SAVED_DIR") == 'card of other' ]] ||
    fail "saved cards: '$(titles "$SAVED_DIR")'" || return
  before=$(saved_fingerprint "$SAVED_DIR")
  host kill-window -t "$other"
  wait_for absent "$(cards_dir "$other")" ||
    fail "closing the window kept $(cards_dir "$other")" || return
  [[ $(saved_fingerprint "$SAVED_DIR") == "$before" ]] ||
    fail "closing the window changed the saved cards: '$(card_names "$SAVED_DIR")'" || return
  dead="$CASE_DIR/state/tmux-cuecard/$(dead_pid)-1"
  make_card "$dead/@0" 0000000001.1.bbbbbb 'card of a dead server'
  load_plugin
  wait_for absent "$dead" || fail "the plugin load kept $dead" || return
  [[ $(saved_fingerprint "$SAVED_DIR") == "$before" ]] ||
    fail "the plugin load changed the saved cards: '$(card_names "$SAVED_DIR")'" || return
  saved_open_view || return
  [[ $(popup_line 1) == ' window 0   saved 1' ]] || fail "tab bar: '$(popup_line 1)'" || return
  [[ $(selected) == 'card of other' ]] || fail "selected: '$(selected)'"
}

test_saved_cards_survive_a_restart_of_the_host_server() {
  start_host || return
  local before old_server
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'window card'
  make_card "$SAVED_DIR" 0000000001.1759900000.bbbbbb 'saved one'
  make_card "$SAVED_DIR" 0000000002.1759900060.cccccc 'saved two'
  before=$(saved_fingerprint "$SAVED_DIR")
  old_server=$SERVER_DIR
  restart_host || return
  [[ $SERVER_DIR != "$old_server" ]] || fail "the server did not restart" || return
  # Window cards do not survive a restart, and the plugin load drops them.
  wait_for absent "$old_server" || fail "the restart kept $old_server" || return
  [[ $(saved_fingerprint "$SAVED_DIR") == "$before" ]] ||
    fail "the restart changed the saved cards: '$(card_names "$SAVED_DIR")'" || return
  open_drawer || return
  [[ $(popup_line 1) == ' window 0   saved 2' ]] || fail "tab bar: '$(popup_line 1)'" || return
  press Tab
  wait_for saved_view_is saved || fail "Tab: active tab '$(saved_active_tab)'" || return
  [[ $(popup_line 2) == ' saved one'* && $(popup_line 3) == ' saved two'* ]] ||
    fail "rows: '$(popup_line 2)' '$(popup_line 3)'"
}

# The directory goes back to writable even when a check fails, so the
# harness can remove it.
test_saved_unwritable_dir_writes_nothing_and_says_so() {
  start_host "$saved_wide" || return
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'window card'
  mkdir -p "$SAVED_DIR"
  chmod 555 "$SAVED_DIR"
  local status
  saved_try_unwritable_dir
  status=$?
  chmod 755 "$SAVED_DIR"
  return "$status"
}

saved_try_unwritable_dir() {
  [[ ! -w $SAVED_DIR ]] || fail "$SAVED_DIR is still writable (running as root?)" || return
  open_drawer || return
  press c
  wait_for saved_first_footer_line_is ' Could not copy the card' ||
    fail "footer after c: '$(footer)'" || return
  [[ -z $(card_names "$SAVED_DIR") ]] || fail "c wrote $(card_names "$SAVED_DIR")" || return
  press Tab
  wait_for saved_view_is saved || fail "Tab: active tab '$(saved_active_tab)'" || return
  press i
  wait_for saved_box_open "$saved_new_prompt" || fail "box row 1: '$(popup_line 1)'" || return
  type_text 'lost card'
  press Enter
  wait_for message_shown "cuecard: could not write the card to $SAVED_DIR" ||
    fail "messages: $(messages | tail -n 3)" || return
  wait_for popup_line_is 2 ' (empty) press i to add' ||
    fail "the drawer did not come back to the empty saved view, row 2: '$(popup_line 2)'" || return
  [[ -z $(card_names "$SAVED_DIR") ]] || fail "i wrote $(card_names "$SAVED_DIR")" || return
  [[ $(titles "$(cards_dir)") == 'window card' && $(card_count) == 1 ]] ||
    fail "window cards: '$(titles "$(cards_dir)")', count '$(card_count)'"
}
