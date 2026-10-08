# tmux-cuecard

Keep prompts you plan to send later on cue cards, one stack per tmux window, and paste them when the time is right. Built for queuing up instructions to an AI coding agent such as Claude Code while it is still busy.

Cards live in a drawer that slides in from the right edge of the terminal. Prompts you send again and again can be saved in the same drawer and reused from every window.

```
┌─ cuecard 0:claude ───────────┐
│ window 2   saved 3           │
│ Run the tests af 10-08 09:12 │
│ Write the PR des 10-08 09:15 │
│──────────────────────────────│
│Run the tests after the merge │
│and fix any failures.         │
│──────────────────────────────│
│ Enter pick   p pop   i new   │
│ e edit   d delete   q quit   │
│ c save   Tab saved           │
│ J/K move   m to window       │
└──────────────────────────────┘
```

## Requirements

- tmux 3.3 or later
- bash 4.2 or later (on macOS, install a newer bash with Homebrew)
- Vim 8.1 or later, for `vim` input and for editing multi-line cards

## Installation

### With TPM

Add the plugin to `~/.tmux.conf`:

```tmux
set -g @plugin 'tot0rokr/tmux-cuecard'
```

Then press `prefix` + `I` to install it.

### Manual

```bash
git clone https://github.com/tot0rokr/tmux-cuecard ~/.tmux/plugins/tmux-cuecard
```

Add this line to `~/.tmux.conf` and reload the config:

```tmux
run-shell ~/.tmux/plugins/tmux-cuecard/cuecard.tmux
```

## Usage

| Key            | Action                                |
| -------------- | ------------------------------------- |
| `prefix` + `Q` | Open the drawer                       |
| `prefix` + `A` | Write a new card without the drawer   |

How you write a card depends on `@cuecard-input`:

- `box` (default): a one-line input box. `Enter` saves the card.
- `vim`: opens `vim --clean`, so your vimrc and plugins stay out of the popup. Cards can span multiple lines.

Saving an empty card adds nothing.

Inside the drawer:

| Key              | Action                                                 |
| ---------------- | ------------------------------------------------------ |
| `↑` `↓`, `k` `j` | Move the selection                                     |
| `K` `J`          | Move the card up or down                               |
| `m`              | Move the card to another window (window cards only)    |
| `Enter`          | Pick: paste the card and keep it                       |
| `p`              | Pop: paste the card and remove it (window cards only)  |
| `i`              | Write a new card                                       |
| `e`              | Edit the card (an empty card is removed)               |
| `d`              | Delete the card (saved cards ask first)                |
| `c`              | Copy the card between the window and the saved cards   |
| `Tab`            | Switch between the window's cards and the saved cards  |
| `q`, `Esc`       | Close the drawer                                       |

With `box` input, `e` still opens vim for a card with more than one line.

Cards are listed oldest first: the top card is next in line, and a new card goes to the bottom. `K` and `J` change a card's place in line, and the new order is kept. Each row shows when the card was created, unless the drawer is too narrow for it. The lower half of the drawer previews the selected card in full.

`m` lists the other windows of the tmux server, with the number of cards each one holds. Pick a window with `Enter` to move the card to the bottom of its stack; the card keeps its creation time. `q` or `Esc` goes back to the cards.

Cards are pasted into the pane that was active when the drawer opened. The paste uses bracketed paste and never presses Enter, so a multi-line card lands in the prompt as one block and waits for you to review and send it.

## Saved cards

Saved cards are prompts you keep for good, such as `Run the tests and fix the failures` or `Write the PR description`. Every window, session and tmux server shares the same saved cards, and they survive tmux restarts. They are kept under `${XDG_DATA_HOME:-~/.local/share}/tmux-cuecard/saved/`, and nothing deletes them automatically (see [Storage](#storage)).

The tab bar at the top of the drawer shows the window's cards and the saved cards, with the number of cards in each; a drawer too narrow for both shows only the open one. `Tab` (or `Shift` + `Tab`) switches between them. The drawer always opens on the window's cards, and each list keeps its selection while the drawer is open.

The saved cards use the same keys, with a few differences, because they are templates rather than a queue:

- `Enter` pastes the card and keeps it, as always. `p` and `m` do nothing, so a saved card is never popped or moved away.
- `d` asks first: press `d` again to delete the card, or any other key to keep it.
- `i` writes a new saved card. `prefix` + `A` always writes a card for the window.

`c` copies a card from one list to the bottom of the other and leaves the original where it is. In the window's cards, `c` saves the card for later. In the saved cards, `c` adds the card to this window's stack, so you can queue it up like any other card. The copy is a new card created at that moment.

## Status line

Put `#{cuecard}` in a status format to show how many cards are waiting. It shows `cue:2` when the window has two cards, and nothing when it has none. Saved cards are not counted.

```tmux
set -g status-right '#{cuecard} %H:%M'
```

The placeholder works in `status-left`, `status-right`, `window-status-format`, `window-status-current-format` and `pane-border-format`. In a window format each window shows its own count. With `pane-border-status top`, a pane border format can put the count in the top right corner of each pane:

```tmux
set -g pane-border-status top
set -g pane-border-format '#[align=right]#{cuecard}'
```

Set the options that use `#{cuecard}` before the plugin loads. The count updates as soon as you add or remove a card. It is kept in the window option `@cuecard-count`, so you can also use it in your own formats.

## Options

| Option                   | Default                                        | Description                         |
| ------------------------ | ---------------------------------------------- | ----------------------------------- |
| `@cuecard-key`           | `Q`                                            | Key that opens the drawer           |
| `@cuecard-insert-key`    | `A`                                            | Key that writes a new card          |
| `@cuecard-width`         | `40%`                                          | Width of the drawer                 |
| `@cuecard-input`         | `box`                                          | How to write a card: `box` or `vim` |
| `@cuecard-status-format` | `#{?#{@cuecard-count},cue:#{@cuecard-count},}` | What `#{cuecard}` expands to        |

```tmux
set -g @cuecard-key 'C'
set -g @cuecard-width '60'
set -g @cuecard-input 'vim'
set -g @cuecard-status-format '#{?#{@cuecard-count},#[fg=yellow]● #{@cuecard-count}#[default],}'
```

## Storage

Each window card is a plain file under `${XDG_STATE_HOME:-~/.local/state}/tmux-cuecard/<server>/<window_id>/`. The file is named `<order>.<created>.<random>`, where `<order>` sets its place in the stack and `<created>` is its creation time in epoch seconds. Moving a card to another window moves its file to that window's directory with a new `<order>`.

Window cards belong to the tmux window, not the drawer:

- Closing the drawer, or picking a card, keeps every card.
- Closing a tmux window deletes the cards of that window.
- Cards do not survive a tmux server restart. The cards of servers that are gone are deleted the next time the plugin loads.

Saved cards are user data, so they live apart from the window cards, in `${XDG_DATA_HOME:-~/.local/share}/tmux-cuecard/saved/`, with files named the same way. The directory is created when you save the first card. Nothing deletes saved cards automatically: only `d` or emptying a card with `e` removes one.

## Development

`tests/run.sh` runs the integration tests. A harness server runs a real tmux client in a pane and types into it with `send-keys`, so the tests see what you would see, the drawer and the status line included. Every server uses its own `tcc-test-<pid>-*` socket, and `HOME`, `XDG_STATE_HOME` and `XDG_DATA_HOME` point into a scratch directory, so the default server and your own cards are never touched. Pass the name of a file in `tests/cases/`, such as `drawer`, to run only the tests in that file, or any other part of a test name to run only the matching tests.

```bash
tests/run.sh
tests/run.sh drawer
tests/run.sh paste
```

The tests live in `tests/cases/`, one file per area. They are run on tmux 3.7b with bash 5.2. To test another tmux build, put a directory with a `tmux` symlink to it first in `PATH`:

```bash
mkdir -p /tmp/tmux-3.3-bin
ln -sf /path/to/tmux-3.3 /tmp/tmux-3.3-bin/tmux
PATH=/tmp/tmux-3.3-bin:$PATH tests/run.sh
```

## License

[MIT](LICENSE)
