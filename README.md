# Claude Usage — KDE Plasma widget

A KDE Plasma 5 panel widget that shows your Claude Code subscription usage limits.

- **Panel badge** with your current 5-hour session usage, colored by the highest limit
  (theme positive / neutral / negative colors at < 70%, 70–90%, ≥ 90%; thresholds configurable).
- **Popup** with every limit (session, weekly, per-model when your plan has them), a progress bar,
  and when each one resets.
- **By model** breakdown of token usage for the current session window or week, read from
  Claude Code's local transcripts on this machine.
- Follows your Plasma theme, light or dark.

## Requirements

- KDE Plasma 5.24 or later (tested on 5.27; Plasma 6 is not supported)
- `/usr/bin/python3` (standard library only)
- Claude Code logged in with a Claude subscription (Pro / Max), so that
  `~/.claude/.credentials.json` exists

## Install

```bash
git clone <this repo> claude-usage-widget
cd claude-usage-widget
./install.sh
```

Then right-click the panel → **Add Widgets…** → search for **Claude Usage** and drag it onto the panel.

Re-run `./install.sh` after pulling changes, then restart Plasma to load them:
`systemctl --user restart plasma-plasmashell`.

To remove: `./uninstall.sh`.

## Configuration

Right-click the widget → **Configure Claude Usage…**

| Setting | Default |
|---|---|
| Refresh interval | 10 minutes |
| Warning color at | 70% |
| Critical color at | 90% |

## How it works

`package/contents/code/usage.py` is run by the widget and prints JSON. It:

1. Reads the OAuth token Claude Code stores in `~/.claude/.credentials.json` and calls
   `https://api.anthropic.com/api/oauth/usage` — the same endpoint Claude Code's `/usage` uses.
   This is not a documented public API and may change.
2. Calls that endpoint at most once every 5 minutes, caching the result in
   `~/.cache/claude-usage-widget.json`. It also reuses Claude Code's own cached copy in
   `~/.claude.json` when that is newer. After an HTTP 429 it waits for `Retry-After`
   (or 15 minutes) before trying again, showing the last known values meanwhile.
3. Sums tokens per model from `~/.claude/projects/**/*.jsonl` (input + output + cache writes;
   cache reads are excluded).

The token is only sent to `api.anthropic.com`. Nothing else leaves your machine.

### Caveats

- The per-model breakdown only covers Claude Code on this machine; usage from claude.ai or
  other devices counts toward your limits but isn't in it. It is a share of tokens, not of
  your limit.
- If the access token has expired the widget shows an error; running `claude` once refreshes it.

## Layout

```
package/
├── metadata.json              # widget id, name, version
└── contents/
    ├── code/usage.py          # data helper (fetch, cache, per-model breakdown)
    ├── config/main.xml        # config schema and defaults
    ├── config/config.qml      # config pages
    └── ui/
        ├── main.qml           # badge, tooltip, popup
        ├── UsageBar.qml       # progress bar
        └── configGeneral.qml  # settings page
```

## License

MIT — see [LICENSE](LICENSE).
