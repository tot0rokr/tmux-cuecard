#!/usr/bin/env bash
# Integration tests. A harness server runs a real host client in a pane and
# types into it with send-keys, so capture-pane of that pane shows what the
# host client draws, the drawer popup and the status line included. Every
# server uses its own -L socket, and the host server gets HOME,
# XDG_STATE_HOME and XDG_DATA_HOME in a scratch directory, so the default
# server and your real cards are never touched.
#
#   tests/run.sh           runs every test
#   tests/run.sh drawer    runs the tests defined in tests/cases/drawer.sh
#   tests/run.sh paste     runs the tests whose name contains "paste", since
#                          there is no tests/cases/paste.sh
#
# The tests live in tests/cases/*.sh as functions named test_*.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$REPO_DIR/tests"
ID="tcc-test-$$"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tcc-test.XXXXXX")
TIMEOUT_SECONDS=5
POLL_SECONDS=0.1

SOCKET_DIR="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
HARNESS=(env -u TMUX tmux -L "$ID-harness" -f /dev/null)
HOST=(env -u TMUX tmux -L "$ID-host")

PASSED=0
FAILED=0
FAILURES=()
CASE=0

stop_servers() {
  local name
  for name in harness host; do
    env -u TMUX tmux -L "$ID-$name" kill-server 2>/dev/null
    # kill-server leaves the socket file behind.
    rm -f "$SOCKET_DIR/$ID-$name"
  done
}

cleanup() {
  stop_servers
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

wait_for() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  until "$@"; do
    ((SECONDS >= deadline)) && return 1
    sleep "$POLL_SECONDS"
  done
}

fail() {
  printf '    %s\n' "$*"
  return 1
}

host() {
  "${HOST[@]}" "$@"
}

absent() {
  [[ ! -e $1 ]]
}

# --- host --------------------------------------------------------------------

# Starts a fresh host server and client for one test. ROWS and COLS size the
# client; the arguments are tmux.conf lines that go before the plugin loads.
# The first window, "agent", records every byte it receives into $PASTE_LOG
# with bracketed paste on, so a test can check exactly what was pasted.
start_host() {
  local conf
  stop_servers
  CASE=$((CASE + 1))
  CASE_DIR="$WORK_DIR/$CASE"
  mkdir -p "$CASE_DIR/home" "$CASE_DIR/state" "$CASE_DIR/data"
  PASTE_LOG="$CASE_DIR/paste.log"
  : > "$PASTE_LOG"
  conf="$CASE_DIR/tmux.conf"
  {
    printf '%s\n' "$@"
    printf '%s\n' "set -g status-right '#{cuecard}'" \
      "set -g window-status-format '#I:#W#{cuecard}'" \
      "set -g window-status-current-format '#I:#W*#{cuecard}'" \
      "run-shell '$REPO_DIR/cuecard.tmux'"
  } > "$conf"
  cat > "$CASE_DIR/recorder" <<'EOF'
printf '\e[?2004h'
stty raw -echo
exec cat >> "$1"
EOF
  # restart_host runs the host client again with this same command.
  HOST_COMMAND="env -u TMUX -u TMUX_PANE HOME='$CASE_DIR/home' \
XDG_STATE_HOME='$CASE_DIR/state' XDG_DATA_HOME='$CASE_DIR/data' \
tmux -L '$ID-host' -f '$conf' new-session -s main -n agent \
\"bash '$CASE_DIR/recorder' '$PASTE_LOG'\""
  "${HARNESS[@]}" new-session -d -s harness -x "${COLS:-100}" -y "${ROWS:-24}" \
    "$HOST_COMMAND"
  wait_for host_ready || fail "the host client did not start" || return
  host_isolated || fail "the host server is not isolated" || return
  locate_host
}

# Points WINDOW at the agent window and SERVER_DIR and SAVED_DIR at the
# card directories of the host server. SERVER_DIR is named after the pid
# and start time of the server, so it changes with every start.
locate_host() {
  WINDOW=$(host display-message -p -t main:agent '#{window_id}')
  SERVER_DIR="$CASE_DIR/state/tmux-cuecard/$(host display-message -p '#{pid}-#{start_time}')"
  SAVED_DIR="$CASE_DIR/data/tmux-cuecard/saved"
}

# Kills the host server and starts it again in the same harness pane, with
# the same tmux.conf, scratch directories and paste log. start_host would
# make a new CASE_DIR, and with it a new saved directory.
restart_host() {
  local pid
  pid=$(host display-message -p '#{pid}')
  # Keeps the pane after the host client exits, so it can be respawned.
  "${HARNESS[@]}" set-option -w -t harness remain-on-exit on
  host kill-server
  # The new server drops the cards of servers that are gone when the plugin
  # loads, so the old one must be gone by then.
  wait_for process_gone "$pid" || fail "the host server $pid did not exit" || return
  wait_for harness_pane_dead || fail "the host client did not exit" || return
  "${HARNESS[@]}" respawn-pane -t harness "$HOST_COMMAND"
  wait_for host_ready || fail "the host client did not start again" || return
  host_isolated || fail "the restarted host server is not isolated" || return
  locate_host
}

host_ready() {
  [[ $(host list-clients -F '#{client_tty}' 2>/dev/null) ]] &&
    screen | tail -n 1 | grep -q 'agent'
}

# Every card the plugin writes must land in this test's scratch directory.
host_isolated() {
  [[ $(host show-environment -g HOME) == "HOME=$CASE_DIR/home" &&
    $(host show-environment -g XDG_STATE_HOME) == "XDG_STATE_HOME=$CASE_DIR/state" &&
    $(host show-environment -g XDG_DATA_HOME) == "XDG_DATA_HOME=$CASE_DIR/data" ]]
}

process_gone() {
  ! kill -0 "$1" 2>/dev/null
}

harness_pane_dead() {
  [[ $("${HARNESS[@]}" display-message -p -t harness '#{pane_dead}') == 1 ]]
}

# A pid no process has, for the card directory of a dead server. kill -0
# alone also fails for another user's process.
dead_pid() {
  local pid=4194300
  while kill -0 "$pid" 2>/dev/null || [[ -e /proc/$pid ]]; do
    pid=$((pid - 1))
  done
  echo "$pid"
}

# Runs cuecard.tmux again inside the host server, the way a reload of the
# config or TPM does. The load sets @cuecard-count from the cards on disk,
# which make_card leaves alone, and drops the cards of dead servers.
load_plugin() {
  host run-shell "'$REPO_DIR/cuecard.tmux'"
}

# The messages shown on a client. The log also lists every command, the
# display-message that showed a message included, as ' command: ' lines.
messages() {
  host show-messages | grep -F ' message: '
}

message_shown() {
  messages | grep -qF -- " message: $1"
}

# Prints the id of a new window named $1 in session ${2:-main}, without
# switching to it.
new_window() {
  host new-window -d -P -F '#{window_id}' -t "${2:-main}:" -n "$1" 'sleep 100000'
}

# --- input -------------------------------------------------------------------

press() {
  "${HARNESS[@]}" send-keys -t harness "$@"
}

type_text() {
  "${HARNESS[@]}" send-keys -t harness -l -- "$1"
}

# --- screen ------------------------------------------------------------------

screen() {
  "${HARNESS[@]}" capture-pane -p -t harness
}

screen_has() {
  screen | grep -qF -- "$1"
}

screen_lacks() {
  ! screen_has "$1"
}

status_line() {
  screen | tail -n 1
}

status_has() {
  status_line | grep -qF -- "$1"
}

drawer_shown() {
  screen_has '┌─ cuecard'
}

drawer_closed() {
  ! drawer_shown
}

# tmux draws the popup border before the drawer script draws anything, so
# a drawer counts as open once its tab bar is on row 1.
drawer_drawn() {
  [[ $(popup_line 1) =~ ^\ (window|saved)\ [0-9]+ ]]
}

open_drawer() {
  press C-b Q
  wait_for drawer_drawn || fail "the drawer did not open"
}

close_drawer() {
  press q
  wait_for drawer_closed || fail "the drawer did not close"
}

# The rows inside the popup border, as plain text. ${1:-} adds -e to keep
# the attributes. The host pane draws nothing, so its only '│' are the
# popup's own borders.
popup_lines() {
  local line
  "${HARNESS[@]}" capture-pane -p ${1:+-e} -t harness | while IFS= read -r line; do
    [[ $line == *│*│* ]] || continue
    line=${line#*│}
    printf '%s\n' "${line%│*}"
  done
}

# Row $1 of the popup, counted from 1, trailing blanks removed.
popup_line() {
  popup_lines | sed -n "${1}p" | sed 's/ *$//'
}

popup_line_is() {
  [[ $(popup_line "$1") == "$2" ]]
}

popup_has() {
  popup_lines | grep -qF -- "$1"
}

popup_lacks() {
  ! popup_has "$1"
}

# The rows under the last separator, joined with '|': the footer of the
# card list or of the window picker. Trailing blanks are removed, and the
# blank each row starts with is kept.
footer() {
  popup_lines |
    awk '/^─/ { seen = 1; n = 0; next } seen { rows[++n] = $0 }
      END { for (i = 1; i <= n; i++) print rows[i] }' |
    sed 's/ *$//' | paste -sd '|' -
}

footer_is() {
  [[ $(footer) == "$1" ]]
}

# The text of the reverse-video row, trimmed, with the date left out.
selected() {
  popup_lines -e | while IFS= read -r line; do
    [[ $line =~ $'\e'\[([0-9;]*;)?7(;[0-9;]*)?m ]] || continue
    line=$(printf '%s' "$line" | sed $'s/\e\\[[0-9;]*m//g')
    printf '%s\n' "$line" | sed -E 's/ [0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} *$//; s/^ +//; s/ +$//'
    break
  done
}

selected_is() {
  [[ $(selected) == "$1" ]]
}

# --- cards -------------------------------------------------------------------

cards_dir() {
  echo "$SERVER_DIR/${1:-$WINDOW}"
}

# Writes a card file by hand: make_card DIR NAME TEXT.
make_card() {
  mkdir -p "$1"
  printf '%s\n' "$3" > "$1/$2"
}

# The first line of every card in directory $1, in stack order. A drawer
# can rename a card between the glob and the read; wait_for tries again.
titles() {
  local file
  for file in "$1"/*; do
    [[ -e $file ]] && head -n 1 "$file" 2>/dev/null
  done | paste -sd '|' -
}

titles_are() {
  [[ $(titles "$1") == "$2" ]]
}

# The file name of the card in directory ${2:-$(cards_dir)} whose first line
# is $1.
card_of() {
  local file
  for file in "${2:-$(cards_dir)}"/*; do
    [[ -e $file && $(head -n 1 "$file") == "$1" ]] && echo "${file##*/}"
  done
}

card_names() {
  ls -1 "$1" 2>/dev/null | paste -sd ' ' -
}

card_names_are() {
  [[ $(card_names "$1") == "$2" ]]
}

# The window option @cuecard-count of window ${1:-$WINDOW}.
card_count() {
  host show-options -wqv -t "${1:-$WINDOW}" @cuecard-count
}

# @cuecard-count of window ${2:-$WINDOW} is $1. An empty $1 also matches an
# option set to an empty value.
card_count_is() {
  [[ $(card_count "${2:-$WINDOW}") == "$1" ]]
}

# Window ${1:-$WINDOW} has no @cuecard-count of its own. A count set to 0
# or to an empty value fails.
card_count_unset() {
  [[ -z $(host show-options -wq -t "${1:-$WINDOW}" @cuecard-count) ]]
}

# Adds a card through prefix + A with box input.
add_card() {
  press C-b A
  wait_for screen_has 'New card' || fail "the input box did not open" || return
  type_text "$1"
  press Enter
  wait_for screen_lacks 'New card' || fail "the input box did not close"
}

# The bytes pasted since the last call to mark_paste, in od -c notation.
mark_paste() {
  PASTE_MARK=$(wc -c < "$PASTE_LOG")
}

pasted() {
  tail -c +$((PASTE_MARK + 1)) "$PASTE_LOG" | od -An -c | tr -s ' ' |
    sed 's/^ //' | paste -sd ' ' -
}

pasted_is() {
  [[ $(pasted) == "$1" ]]
}

# od -c notation of the bracketed paste of $1.
bracketed() {
  printf '\e[200~%s\e[201~' "$1" | od -An -c | tr -s ' ' | sed 's/^ //' |
    paste -sd ' ' -
}

# --- runner ------------------------------------------------------------------

# Two case files that define the same test would leave only the one sourced
# last, so that test would run once and the other never.
tests_unique() {
  local file name status=0
  local -A first=()
  for file in "$TESTS_DIR"/cases/*.sh; do
    for name in $(sed -n 's/^\(test_[A-Za-z0-9_]*\) *().*/\1/p' "$file"); do
      if [[ -z ${first[$name]:-} ]]; then
        first[$name]=$file
      elif [[ ${first[$name]} == "$file" ]]; then
        printf '%s is defined twice in %s\n' "$name" "${file#"$REPO_DIR"/}" >&2
        status=1
      else
        printf '%s is defined in both %s and %s\n' "$name" \
          "${first[$name]#"$REPO_DIR"/}" "${file#"$REPO_DIR"/}" >&2
        status=1
      fi
    done
  done
  return "$status"
}

tests_unique || exit 1
for case_file in "$TESTS_DIR"/cases/*.sh; do
  source "$case_file"
done

# The file that defines function $1. With extdebug, declare -F prints
# "name line file".
defined_in() {
  local where
  where=$(shopt -s extdebug && declare -F "$1")
  where=${where#"$1" }
  printf '%s\n' "${where#* }"
}

run() {
  local name=$1
  if "$name"; then
    PASSED=$((PASSED + 1))
    printf 'ok      %s\n' "${name#test_}"
  else
    FAILED=$((FAILED + 1))
    FAILURES+=("$name")
    printf 'FAILED  %s\n' "${name#test_}"
    printf '    last screen:\n'
    screen 2>/dev/null | sed -e '/^[[:space:]]*$/d' -e 's/^/      | /' | head -30
  fi
}

main() {
  local name file=
  [[ -n ${1:-} && -f $TESTS_DIR/cases/$1.sh ]] && file="$TESTS_DIR/cases/$1.sh"
  for name in $(declare -F | awk '{print $3}' | grep '^test_'); do
    if [[ -n $file ]]; then
      [[ $(defined_in "$name") == "$file" ]] || continue
    elif [[ -n ${1:-} && $name != *"$1"* ]]; then
      continue
    fi
    run "$name"
  done
  printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
  ((FAILED == 0))
}

main "$@"
