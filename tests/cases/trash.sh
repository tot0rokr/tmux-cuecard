# Recovery after discards, window closure, and server restarts.

trash_open_view() {
  open_drawer || return
  press t
  wait_for saved_view_is trash || fail "t did not open trash: $(saved_active_tab)"
}

trash_name_matches() {
  local name
  name=$(card_of "$1" "$TRASH_DIR")
  [[ $name =~ ^[0-9]+\.$2\.$3\.$4\.[A-Za-z0-9]{6}$ ]]
}

test_trash_pop_preserves_multiline_bytes_and_original_creation_time() {
  start_host || return
  local TRASH_DIR="$CASE_DIR/data/tmux-cuecard/trash"
  local text=$'pop me\n\tindented  \nlast line\n' archived
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa "$text"
  make_card "$(cards_dir)" 0000000002.1759900060.bbbbbb 'stay'
  open_drawer || return
  mark_paste
  press p
  wait_for drawer_closed || fail "p did not close the drawer" || return
  wait_for pasted_is "$(bracketed $'pop me\r\tindented  \rlast line')" || fail "pasted bytes: $(pasted)" || return
  wait_for titles_are "$TRASH_DIR" 'pop me' || fail "trash: $(titles "$TRASH_DIR")" || return
  archived=$(card_of 'pop me' "$TRASH_DIR")
  printf '%s\n' "$text" | cmp -s - "$TRASH_DIR/$archived" || fail "pop changed archived bytes" || return
  trash_name_matches 'pop me' 1759900000 window pop || fail "trash name: $archived" || return
  [[ $(titles "$(cards_dir)") == stay && $(card_count) == 1 ]] || fail "window cards: $(titles "$(cards_dir)"), count: $(card_count)"
}

test_trash_delete_collects_window_and_saved_cards_without_changing_bytes() {
  start_host || return
  local TRASH_DIR="$CASE_DIR/data/tmux-cuecard/trash"
  local window_text=$'window text\n\tsecond  ' saved_text=$'saved text\nlast\n' name
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa "$window_text"
  make_card "$SAVED_DIR" 0000000001.1759900060.bbbbbb "$saved_text"
  open_drawer || return
  press d
  wait_for card_count_unset || fail "window count after d: $(card_count)" || return
  name=$(card_of 'window text' "$TRASH_DIR")
  [[ -n $name ]] || fail "window d did not archive the card" || return
  printf '%s\n' "$window_text" | cmp -s - "$TRASH_DIR/$name" || fail "window delete changed bytes" || return
  trash_name_matches 'window text' 1759900000 window delete || fail "trash name: $name" || return
  press Tab
  wait_for saved_view_is saved || fail "saved view did not open" || return
  press d
  wait_for saved_first_footer_line_is ' Press d again to delete' || fail "saved confirmation: $(footer)" || return
  [[ -z $(card_of 'saved text' "$TRASH_DIR") ]] || fail "first d discarded the saved card" || return
  press d
  wait_for titles_are "$SAVED_DIR" '' || fail "saved cards: $(titles "$SAVED_DIR")" || return
  name=$(card_of 'saved text' "$TRASH_DIR")
  [[ -n $name ]] || fail "saved d d did not archive the card" || return
  printf '%s\n' "$saved_text" | cmp -s - "$TRASH_DIR/$name" || fail "saved delete changed bytes" || return
  trash_name_matches 'saved text' 1759900060 saved delete || fail "trash name: $name"
}

test_trash_closed_window_cards_restore_into_the_current_window() {
  start_host || return
  local TRASH_DIR="$CASE_DIR/data/tmux-cuecard/trash"
  local other text=$'recover me\nsecond line' name
  other=$(new_window other) || fail "could not open another window" || return
  make_card "$(cards_dir "$other")" 0000000001.1759900000.aaaaaa "$text"
  make_card "$(cards_dir)" 0000000001.1759900060.bbbbbb 'current card'
  host kill-window -t "$other"
  wait_for absent "$(cards_dir "$other")" || fail "closed window directory remains" || return
  trash_name_matches 'recover me' 1759900000 window window-closed || fail "trash: $(card_names "$TRASH_DIR")" || return
  trash_open_view || return
  press r
  wait_for titles_are "$(cards_dir)" 'current card|recover me' || fail "restored cards: $(titles "$(cards_dir)")" || return
  name=$(card_of 'recover me')
  [[ $name == 0000000002.1759900000.* ]] || fail "restored name: $name" || return
  printf '%s\n' "$text" | cmp -s - "$(cards_dir)/$name" || fail "restore changed bytes" || return
  wait_for card_count_is 2 || fail "window count: $(card_count)" || return
  [[ -z $(card_names "$TRASH_DIR") ]] || fail "restore left trash: $(card_names "$TRASH_DIR")"
}

test_trash_server_restart_keeps_trash_and_collects_leftover_window_cards() {
  start_host || return
  local TRASH_DIR="$CASE_DIR/data/tmux-cuecard/trash"
  local old_server=$SERVER_DIR archived
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'already discarded'
  make_card "$(cards_dir)" 0000000002.1759900060.bbbbbb 'pending at shutdown'
  open_drawer || return
  press d
  wait_for titles_are "$TRASH_DIR" 'already discarded' || fail "delete did not archive" || return
  archived=$(card_of 'already discarded' "$TRASH_DIR")
  close_drawer || return
  restart_host || return
  wait_for absent "$old_server" || fail "old server directory remains" || return
  [[ -f $TRASH_DIR/$archived ]] || fail "existing trash did not survive restart" || return
  trash_name_matches 'pending at shutdown' 1759900060 window server-closed || fail "restart trash: $(card_names "$TRASH_DIR")" || return
  [[ -z $(card_names "$(cards_dir)") ]] || fail "old cards appeared in the new window" || return
  trash_open_view || return
  popup_has 'pending at shutdown' || fail "restarted drawer did not list recovered cards"
}

test_trash_plugin_load_collects_all_windows_of_a_dead_server() {
  start_host || return
  local TRASH_DIR="$CASE_DIR/data/tmux-cuecard/trash"
  local dead="$CASE_DIR/state/tmux-cuecard/$(dead_pid)-1"
  make_card "$dead/@0" 0000000001.1759900000.aaaaaa 'dead first'
  make_card "$dead/@1" 0000000001.1759900060.bbbbbb 'dead second'
  make_card "$(cards_dir)" 0000000001.1759900120.cccccc 'live card'
  load_plugin || fail "plugin reload failed" || return
  wait_for absent "$dead" || fail "dead server directory remains" || return
  trash_name_matches 'dead first' 1759900000 window server-closed || fail "first dead card was not archived" || return
  trash_name_matches 'dead second' 1759900060 window server-closed || fail "second dead card was not archived" || return
  [[ $(titles "$(cards_dir)") == 'live card' ]] || fail "live window cards changed"
}

test_trash_lists_newest_discards_first_and_t_preserves_regular_selections() {
  start_host || return
  local TRASH_DIR="$CASE_DIR/data/tmux-cuecard/trash"
  drawer_stack "$(cards_dir)" 'window one' 'window two'
  drawer_stack "$SAVED_DIR" 'saved one' 'saved two'
  make_card "$TRASH_DIR" 1759900000.1700000000.window.delete.aaaaaa 'older trash'
  make_card "$TRASH_DIR" 1759900060.1690000000.saved.delete.bbbbbb 'newer trash'
  open_drawer || return
  press j
  wait_for selected_is 'window two' || fail "could not select window two" || return
  press t
  wait_for saved_view_is trash || fail "t did not open trash" || return
  [[ $(selected) == 'newer trash' ]] || fail "trash selected: $(selected)" || return
  [[ $(popup_line 2) == ' newer trash '*" $(drawer_date 1759900060)" ]] || fail "trash date: $(popup_line 2)" || return
  press t
  wait_for saved_view_is window || fail "t did not return to window" || return
  [[ $(selected) == 'window two' ]] || fail "window selection changed: $(selected)" || return
  press Tab
  wait_for saved_view_is saved || fail "saved view did not open" || return
  press j
  wait_for selected_is 'saved two' || fail "could not select saved two" || return
  press t
  wait_for saved_view_is trash || fail "saved t did not open trash" || return
  press t
  wait_for saved_view_is saved || fail "t did not return to saved" || return
  [[ $(selected) == 'saved two' ]] || fail "saved selection changed: $(selected)"
}

test_trash_saved_restore_keeps_its_creation_time_and_saved_destination() {
  start_host || return
  local TRASH_DIR="$CASE_DIR/data/tmux-cuecard/trash"
  local text=$'saved recovery\n\tsecond line' name
  make_card "$TRASH_DIR" 1759900060.1700000000.saved.delete.aaaaaa "$text"
  make_card "$SAVED_DIR" 0000000001.1759900000.bbbbbb 'saved survivor'
  trash_open_view || return
  press r
  wait_for titles_are "$SAVED_DIR" 'saved survivor|saved recovery' || fail "saved restore: $(titles "$SAVED_DIR")" || return
  name=$(card_of 'saved recovery' "$SAVED_DIR")
  [[ $name == 0000000002.1700000000.* ]] || fail "restored name: $name" || return
  printf '%s\n' "$text" | cmp -s - "$SAVED_DIR/$name" || fail "restored bytes differ" || return
  [[ -z $(card_names "$TRASH_DIR") && -z $(card_names "$(cards_dir)") ]] || fail "restore left trash or wrote a window card" || return
  card_count_unset || fail "saved restore changed window count: $(card_count)"
}

test_trash_permanent_delete_requires_confirmation_and_other_keys_cancel() {
  start_host 'set -g @cuecard-width 60' || return
  local TRASH_DIR="$CASE_DIR/data/tmux-cuecard/trash" before
  make_card "$TRASH_DIR" 1759900000.1700000000.window.delete.aaaaaa 'keep'
  make_card "$TRASH_DIR" 1759900060.1700000060.window.pop.bbbbbb 'remove'
  before=$(saved_fingerprint "$TRASH_DIR")
  trash_open_view || return
  press d
  wait_for saved_first_footer_line_is ' Press d again to delete permanently' || fail "delete confirmation: $(footer)" || return
  [[ $(saved_fingerprint "$TRASH_DIR") == "$before" ]] || fail "first d deleted a card" || return
  press j
  wait_for popup_lacks 'Press d again to delete permanently' || fail "j did not cancel" || return
  [[ $(selected) == remove && $(saved_fingerprint "$TRASH_DIR") == "$before" ]] || fail "cancelling changed selection or cards" || return
  press d
  wait_for saved_first_footer_line_is ' Press d again to delete permanently' || fail "second delete did not ask" || return
  press d
  wait_for titles_are "$TRASH_DIR" keep || fail "trash after d d: $(titles "$TRASH_DIR")" || return
  wait_for selected_is keep || fail "selection after permanent delete: $(selected)"
}

test_trash_empty_confirmation_uses_a_snapshot_and_keeps_new_arrivals() {
  start_host 'set -g @cuecard-width 60' || return
  local TRASH_DIR="$CASE_DIR/data/tmux-cuecard/trash" before
  make_card "$TRASH_DIR" 1759900000.1700000000.window.delete.aaaaaa 'first'
  make_card "$TRASH_DIR" 1759900060.1700000060.saved.delete.bbbbbb 'second'
  before=$(saved_fingerprint "$TRASH_DIR")
  trash_open_view || return
  press D
  wait_for saved_first_footer_line_is ' Press D again to empty trash' || fail "empty confirmation: $(footer)" || return
  press q
  wait_for popup_lacks 'Press D again to empty trash' || fail "q did not cancel" || return
  [[ $(saved_fingerprint "$TRASH_DIR") == "$before" ]] || fail "cancelling emptied trash" || return
  saved_view_is trash || fail "q closed the drawer instead of cancelling" || return
  press D
  wait_for saved_first_footer_line_is ' Press D again to empty trash' || fail "second empty did not ask" || return
  make_card "$TRASH_DIR" 1759900120.1700000120.window.pop.cccccc 'arrived later'
  press D
  wait_for titles_are "$TRASH_DIR" 'arrived later' || fail "empty result: $(titles "$TRASH_DIR")" || return
  wait_for selected_is 'arrived later' || fail "selection: $(selected)"
}

test_trash_yank_and_enter_use_the_card_without_removing_it() {
  start_host || return
  local TRASH_DIR="$CASE_DIR/data/tmux-cuecard/trash"
  local text=$'trash text\nsecond line' before
  make_card "$TRASH_DIR" 1759900000.1700000000.window.pop.aaaaaa "$text"
  before=$(saved_fingerprint "$TRASH_DIR")
  trash_open_view || return
  mark_paste
  press y
  wait_for drawer_buffer_is "$text" || fail "yank buffer: $(drawer_buffer)" || return
  saved_view_is trash || fail "yank closed trash" || return
  [[ -z $(pasted) ]] || fail "yank pasted the card" || return
  press Enter
  wait_for drawer_closed || fail "Enter did not close the drawer" || return
  wait_for pasted_is "$(bracketed "${text//$'\n'/$'\r'}")" || fail "trash paste bytes: $(pasted)" || return
  [[ $(saved_fingerprint "$TRASH_DIR") == "$before" ]] || fail "yank or Enter changed trash"
}

test_trash_unsupported_mutators_leave_cards_unchanged() {
  start_host || return
  local TRASH_DIR="$CASE_DIR/data/tmux-cuecard/trash" before
  make_card "$TRASH_DIR" 1759900000.1700000000.window.delete.aaaaaa 'older'
  make_card "$TRASH_DIR" 1759900060.1700000060.saved.delete.bbbbbb 'newer'
  before=$(saved_fingerprint "$TRASH_DIR")
  trash_open_view || return
  mark_paste
  press i e p c M m J K j
  wait_for selected_is older || fail "unsupported key changed view or blocked navigation" || return
  [[ $(saved_fingerprint "$TRASH_DIR") == "$before" ]] || fail "unsupported key changed trash" || return
  [[ -z $(card_names "$(cards_dir)") && -z $(card_names "$SAVED_DIR") ]] || fail "unsupported key created a card" || return
  [[ -z $(pasted) ]] || fail "p pasted a trash card"
}

test_trash_empty_box_edits_preserve_window_and_saved_cards() {
  start_host 'set -g @cuecard-width 60' || return
  local TRASH_DIR="$CASE_DIR/data/tmux-cuecard/trash" before_window before_saved
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa 'window original'
  make_card "$SAVED_DIR" 0000000001.1759900060.bbbbbb 'saved original'
  before_window=$(saved_fingerprint "$(cards_dir)")
  before_saved=$(saved_fingerprint "$SAVED_DIR")
  open_drawer || return
  press e
  wait_for saved_box_open 'Edit card (Enter saves, empty cancels)' || fail "window edit box did not open" || return
  press C-u Enter
  wait_for saved_first_footer_line_is ' Empty edit ignored' || fail "empty edit notice: $(footer)" || return
  [[ $(saved_fingerprint "$(cards_dir)") == "$before_window" && $(card_count) == 1 ]] || fail "empty window edit changed the card or count" || return
  press Tab
  wait_for saved_view_is saved || fail "saved view did not open" || return
  press e
  wait_for saved_box_open 'Edit saved card (Enter saves, empty cancels)' || fail "saved edit box did not open" || return
  press C-u
  type_text '   '
  press Enter
  wait_for saved_first_footer_line_is ' Empty edit ignored' || fail "blank saved edit notice: $(footer)" || return
  [[ $(saved_fingerprint "$SAVED_DIR") == "$before_saved" ]] || fail "blank saved edit changed the card" || return
  [[ -z $(card_names "$TRASH_DIR") ]] || fail "empty edits discarded cards"
}

test_trash_empty_vim_edit_keeps_the_original_multiline_card() {
  start_host 'set -g @cuecard-input vim' || return
  local TRASH_DIR="$CASE_DIR/data/tmux-cuecard/trash" before
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa $'first line\n\tsecond line  '
  before=$(saved_fingerprint "$(cards_dir)")
  open_drawer || return
  press e
  wait_for drawer_vim_shown || fail "vim did not open" || return
  type_text ':%d'
  press Enter
  type_text ':wq'
  press Enter
  wait_for saved_first_footer_line_is ' Empty edit ignored' || fail "empty vim edit notice: $(footer)" || return
  [[ $(saved_fingerprint "$(cards_dir)") == "$before" && $(card_count) == 1 ]] || fail "empty vim edit changed bytes or count" || return
  [[ -z $(card_names "$TRASH_DIR") ]] || fail "empty vim edit discarded the card"
}

test_trash_capital_m_moves_between_window_and_saved_preserving_bytes_and_age() {
  start_host || return
  local TRASH_DIR="$CASE_DIR/data/tmux-cuecard/trash"
  local text=$'move me\n\tsecond line  ' name
  make_card "$(cards_dir)" 0000000001.1759900000.aaaaaa "$text"
  make_card "$(cards_dir)" 0000000002.1759900060.bbbbbb 'stay in window'
  make_card "$SAVED_DIR" 0000000001.1759900120.cccccc 'stay saved'
  open_drawer || return
  press M
  wait_for titles_are "$SAVED_DIR" 'stay saved|move me' || fail "M to saved: $(titles "$SAVED_DIR")" || return
  wait_for card_count_is 1 || fail "M to saved count: $(card_count)" || return
  [[ $(titles "$(cards_dir)") == 'stay in window' ]] || fail "M left a source card" || return
  name=$(card_of 'move me' "$SAVED_DIR")
  [[ $name == 0000000002.1759900000.* ]] || fail "move to saved lost age: $name" || return
  printf '%s\n' "$text" | cmp -s - "$SAVED_DIR/$name" || fail "move to saved changed bytes" || return
  press Tab
  wait_for saved_view_is saved || fail "saved view did not open" || return
  press j
  wait_for selected_is 'move me' || fail "could not select moved card" || return
  press M
  wait_for titles_are "$(cards_dir)" 'stay in window|move me' || fail "M to window: $(titles "$(cards_dir)")" || return
  wait_for card_count_is 2 || fail "M to window count: $(card_count)" || return
  [[ $(titles "$SAVED_DIR") == 'stay saved' ]] || fail "M left a saved source" || return
  name=$(card_of 'move me')
  [[ $name == 0000000003.1759900000.* ]] || fail "move to window lost age: $name" || return
  printf '%s\n' "$text" | cmp -s - "$(cards_dir)/$name" || fail "move to window changed bytes" || return
  [[ -z $(card_names "$TRASH_DIR") ]] || fail "M sent a transferred card to trash"
}

test_trash_failed_discard_keeps_the_original_cards_and_count() {
  start_host || return
  local before
  drawer_stack "$(cards_dir)" 'keep first' 'keep second'
  make_card "$CASE_DIR/data/tmux-cuecard" trash 'not a directory'
  before=$(saved_fingerprint "$(cards_dir)")
  open_drawer || return
  press d j
  wait_for selected_is 'keep second' || fail "failed discard blocked the drawer" || return
  [[ $(saved_fingerprint "$(cards_dir)") == "$before" && $(card_count) == 2 ]] ||
    fail "failed discard changed the cards or count"
}

test_trash_cancelled_box_edit_preserves_a_concurrent_update() {
  start_host 'set -g @cuecard-width 60' || return
  local name=0000000001.1759900000.aaaaaa before
  make_card "$(cards_dir)" "$name" 'original text'
  open_drawer || return
  press e
  wait_for saved_box_open 'Edit card (Enter saves, empty cancels)' ||
    fail "edit box did not open" || return
  make_card "$(cards_dir)" "$name" 'updated by another drawer'
  before=$(saved_fingerprint "$(cards_dir)")
  press C-u C-d
  wait_for saved_view_is window || fail "Ctrl-D did not cancel editing" || return
  wait_for selected_is 'updated by another drawer' ||
    fail "cancelled edit overwrote the latest text: $(selected)" || return
  [[ $(saved_fingerprint "$(cards_dir)") == "$before" && $(card_count) == 1 ]] ||
    fail "cancelled box edit changed the latest card or count"
}

test_trash_cancelled_vim_edit_preserves_a_concurrent_update() {
  start_host 'set -g @cuecard-input vim' || return
  local name=0000000001.1759900000.aaaaaa before
  make_card "$(cards_dir)" "$name" $'original first\noriginal second'
  open_drawer || return
  press e
  wait_for drawer_vim_shown || fail "vim did not open" || return
  press i
  wait_for popup_has '-- INSERT --' || fail "vim did not enter insert mode" || return
  type_text 'discard this edit '
  press Escape
  wait_for popup_lacks '-- INSERT --' || fail "vim did not leave insert mode" || return
  make_card "$(cards_dir)" "$name" $'external first\nexternal second'
  before=$(saved_fingerprint "$(cards_dir)")
  type_text ':q!'
  press Enter
  wait_for saved_view_is window || fail "q! did not close vim" || return
  wait_for selected_is 'external first' ||
    fail "cancelled vim edit overwrote the latest text: $(selected)" || return
  [[ $(saved_fingerprint "$(cards_dir)") == "$before" && $(card_count) == 1 ]] ||
    fail "cancelled vim edit changed the latest card or count"
}

test_trash_failed_pop_keeps_the_original_after_pasting() {
  start_host 'set -g @cuecard-width 60' || return
  local before
  drawer_stack "$(cards_dir)" 'keep after paste' 'second card'
  make_card "$CASE_DIR/data/tmux-cuecard" trash 'not a directory'
  before=$(saved_fingerprint "$(cards_dir)")
  open_drawer || return
  mark_paste
  press p
  wait_for saved_first_footer_line_is ' Pasted, but could not move card to trash' ||
    fail "failed pop notice: $(footer)" || return
  wait_for pasted_is "$(bracketed 'keep after paste')" || fail "failed pop did not paste" || return
  [[ $(saved_fingerprint "$(cards_dir)") == "$before" && $(card_count) == 2 ]] ||
    fail "failed pop changed the original cards or count"
}

test_trash_failed_window_cleanup_keeps_cards_in_the_closed_window_directory() {
  start_host || return
  local other dir before
  other=$(new_window other) || fail "could not open another window" || return
  dir=$(cards_dir "$other")
  drawer_stack "$dir" $'recover later\nsecond line' 'also recover'
  make_card "$CASE_DIR/data/tmux-cuecard" trash 'not a directory'
  before=$(saved_fingerprint "$dir")
  host kill-window -t "$other"
  wait_for message_shown 'cuecard: could not move closed window cards to trash' ||
    fail "cleanup did not report the archive failure" || return
  [[ $(saved_fingerprint "$dir") == "$before" ]] ||
    fail "failed cleanup changed the closed window cards"
}
