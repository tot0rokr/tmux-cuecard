# tmux-cuecard

Keep prompts you plan to send later on cue cards, one stack per tmux window, and paste them when the time is right. Built for queuing up instructions to an AI coding agent such as Claude Code while it is still busy.

Cards live in a drawer that slides in from the right edge of the terminal.

```
┌─ cuecard 0:claude ─────────┐
│ Write the PR description … │
│ Run the tests after the r… │
├────────────────────────────┤
│ Write the PR description   │
│ in English.                │
├────────────────────────────┤
│ Enter pick   p pop   i new │
│ e edit   d delete   q quit │
└────────────────────────────┘
```

## Requirements

- tmux 3.3 or later
- bash 4 or later (on macOS, install a newer bash with Homebrew)
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
| `Enter`          | Pick: paste the card and keep it         |
| `p`              | Pop: paste the card and remove it        |
| `i`              | Write a new card                         |
| `e`              | Edit the card (an empty card is removed) |
| `d`              | Delete the card                          |
| `q`, `Esc`       | Close the drawer                         |

With `box` input, `e` still opens vim for a card with more than one line.

The newest card is at the top. The lower half of the drawer previews the selected card in full.

Cards are pasted into the pane that was active when the drawer opened. The paste uses bracketed paste and never presses Enter, so a multi-line card lands in the prompt as one block and waits for you to review and send it.

## Options

| Option                | Default | Description                           |
| --------------------- | ------- | ------------------------------------- |
| `@cuecard-key`        | `Q`     | Key that opens the drawer             |
| `@cuecard-insert-key` | `A`     | Key that writes a new card            |
| `@cuecard-width`      | `40%`   | Width of the drawer                   |
| `@cuecard-input`      | `box`   | How to write a card: `box` or `vim`   |

```tmux
set -g @cuecard-key 'C'
set -g @cuecard-width '60'
set -g @cuecard-input 'vim'
```

## Storage

Each card is a plain file under `${XDG_STATE_HOME:-~/.local/state}/tmux-cuecard/<server>/<window_id>/`.

Cards belong to the tmux window, not the drawer:

- Closing the drawer, or picking a card, keeps every card.
- Closing a tmux window deletes the cards of that window.
- Cards do not survive a tmux server restart. The cards of servers that are gone are deleted the next time the plugin loads.

## License

[MIT](LICENSE)
