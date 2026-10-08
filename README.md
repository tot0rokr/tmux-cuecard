# tmux-cuecard

Keep prompts you plan to send later on cue cards, one stack per tmux window, and paste them when the time is right. Built for queuing up instructions to an AI coding agent such as Claude Code while it is still busy.

Cards live in a drawer that slides in from the right edge of the terminal.

```
┌─ cuecard 0:claude ───────────┐
│ Run the tests af 10-08 09:12 │
│ Write the PR des 10-08 09:15 │
│──────────────────────────────│
│Run the tests after the merge │
│and fix any failures.         │
│──────────────────────────────│
│ Enter pick   p pop   i new   │
│ e edit   d delete   q quit   │
│ J/K move                     │
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

| Key              | Action                                   |
| ---------------- | ---------------------------------------- |
| `↑` `↓`, `k` `j` | Move the selection                       |
| `K` `J`          | Move the card up or down                 |
| `Enter`          | Pick: paste the card and keep it         |
| `p`              | Pop: paste the card and remove it        |
| `i`              | Write a new card                         |
| `e`              | Edit the card (an empty card is removed) |
| `d`              | Delete the card                          |
| `q`, `Esc`       | Close the drawer                         |

With `box` input, `e` still opens vim for a card with more than one line.

Cards are listed oldest first: the top card is next in line, and a new card goes to the bottom. `K` and `J` change a card's place in line, and the new order is kept. Each row shows when the card was created, unless the drawer is too narrow for it. The lower half of the drawer previews the selected card in full.

Cards are pasted into the pane that was active when the drawer opened. The paste uses bracketed paste and never presses Enter, so a multi-line card lands in the prompt as one block and waits for you to review and send it.

## Status line

Put `#{cuecard}` in a status format to show how many cards are waiting. It shows `cue:2` when the window has two cards, and nothing when it has none.

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

Each card is a plain file under `${XDG_STATE_HOME:-~/.local/state}/tmux-cuecard/<server>/<window_id>/`. The file is named `<order>.<created>.<random>`, where `<order>` sets its place in the stack and `<created>` is its creation time in epoch seconds.

Cards belong to the tmux window, not the drawer:

- Closing the drawer, or picking a card, keeps every card.
- Closing a tmux window deletes the cards of that window.
- Cards do not survive a tmux server restart. The cards of servers that are gone are deleted the next time the plugin loads.

## License

[MIT](LICENSE)
