---
name: tuios-recording
description: Record a tuios pane, especially a TML surface (tml show --pane dashboards, graphics, simulations), as an asciicast, then render it to GIF and MP4 with captions drawn inside the surface. Use whenever the user wants a screen recording, demo video, GIF, cast, walkthrough or "record this pane" of anything in tuios, wants to show a TML pane in another terminal or window, or asks about recording with asciinema, agg, wezterm record, Ghostty or tuios record-pane, even if they don't say "skill" or name the tools.
---

# Recording tuios panes

Record a tuios pane to a `.cast`, render it with `agg` and ffmpeg, and play it back in a popup.
What works depends on one question: **is the pane a TML surface?**

## Why a TML surface needs a different route

A TML surface is drawn by the attached tuios *client*, not by the pane's PTY. Every tool that reads
the pane's output gets only the placeholder text "This pane shows a TML surface. This client cannot
draw it":

| Tool | Plain pane (shell, agent, htop) | TML surface |
|---|---|---|
| `tuios record-pane start -w W -o f.cast` | works, simplest route | placeholder |
| `tuios screenshot -w W` | works | placeholder |
| `tuios pane-view -w W` (e.g. in a Ghostty window) | works | placeholder |
| `tuios send-keys -w W` | reaches the program | bypasses the surface, keys go nowhere |
| asciinema/`wezterm record` of `tuios attach SESSION` | works | **works**: a real client draws it |

Ghostty has no recording action, and on macOS a Ghostty window is opened with `open -na Ghostty
--args -e CMD` (`ghostty +new-window` is not supported there). `wezterm record PROG` is only an
asciicast of a program it starts, the same as `asciinema rec -c`. Prefer asciinema: v3 casts
support markers.

For a plain pane, use `record-pane` and skip to [Render](#render). The rest is for TML surfaces.

## Route for a TML surface

1. **Stage it in its own session**, so the recorded client shows nothing else:
   `tuios new demo --detach`, open the surface there (`tuios tml show FILE --pane -s demo --events`),
   and close the session's initial shell window (`tuios close-window -s demo <id>`).
2. **Open the surface from the process that will drive it.** Only the pane that opened a surface may
   patch, replace or close it. A script started from your pane inherits your pane's identity, so a
   driver script that runs `tml show` itself (or a helper you start from the same pane) can patch.
3. **Record a headless client**: `scripts/timeline.py` runs
   `asciinema rec --headless --window-size COLSxROWS -c "tuios attach demo <chrome-hiding flags>"`,
   plays a timeline of state patches, then ends the recording with `tuios detach-client -s demo`.
   The chrome flags: `--dockbar-position hidden --border-style hidden --hide-clock --hide-scrollbar
   --hide-window-buttons --window-title-position hidden`. At 200x46 no sidebar showed; at 140 cols the
   rail took a quarter of the width. If it shows, widen the window or crop the video.
4. **Render, check frames, trim**, then play it (below).

## Drive with state, not keys

Patch the surface's state with `tuios tml patch SURFACE '[{"op":"replace","path":"/caption","value":"…"}]'`
instead of pressing keys:

- `tuios run-command -s demo Press KEY` reaches the surface but needs the pane's `respond` grant, and
  every key is its own permission prompt. `send-keys -w` never reaches a surface.
- Run the whole timeline as **one script** so the user approves once. Interleaving tool calls with
  sleeps costs a prompt per call and breaks the timing.
- Patch paths are JSON pointers from the state root: `/caption`, `/sim/status`. A helper that
  prefixes paths (`/sim/` + key) silently writes captions to `/sim/caption`, where nothing shows.

Design the document so everything the demo changes is state:

- **Tabs:** `<tabs value="state.tab">`, then patch `/tab`. Without `value`, the open tab is view
  state and cannot be patched.
- **Selection:** a table's cursor is view state too. Use `select="none"` and a marker column
  (`mark: "▶"`) that you patch.
- **Captions (subtitles):** asciicast has no subtitle track, and Homebrew's ffmpeg lacks `drawtext`
  and `subtitles`. Put a caption row at the top of a demo copy of the document:
  `<row gap="2"><badge role="accent">{state.key}</badge><text><b>{state.caption}</b></text></row>`.
  `key` doubles as a keystroke or scene badge ("tab: Backoff", "▶ misroute").
- **Highlights:** bind `role` to state (`<badge role="{state.st.hold}">`, `<stat role="{state.statusRole}">`)
  and patch it; add a `<toast ttl="3s">{state.toast}</toast>`. Spotlight dims other panes, which
  does not help when only one pane is recorded.
- **Animation:** TML has no timers; the driver patches every 50 to 600 ms. Fast-forward idle waits
  (short sleeps per simulated tick) and pause on the moments that matter. 100 patches a second is the
  cap per surface.

## Timeline script

`scripts/timeline.py` records and drives in one process. Write a timeline JSON:

```json
{"lead_in": 3, "tail": 4, "steps": [
  {"patch": {"caption": "Overview: …", "tab": "overview", "key": ""}, "wait": 5},
  {"patch": {"tab": "backoff", "key": "tab: Backoff", "caption": "Backoff: …"}, "wait": 6},
  {"run": ["python3", "-I", "play_scenario.py", "SURFACE", "misroute"]},
  {"patch": {"caption": "End card"}, "wait": 4}
]}
```

```bash
python3 -I ~/.claude/skills/tuios-recording/scripts/timeline.py \
  --surface tml-xxxx --session demo --cast out.cast --size 200x46 --title "Demo" timeline.json
```

A `run` step blocks until its command ends; use it for scripted animations that patch the surface
themselves. Keys in `patch` may contain `/` for nested paths (`"sim/scenarios"`).

## Render

```bash
~/.claude/skills/tuios-recording/scripts/render.sh out.cast OUTDIR      # OUTDIR/out.gif, out.mp4
```

It runs `mise exec github:asciinema/agg@latest -- agg` (no global install) and ffmpeg (yuv420p, even
dimensions, faststart).

## Check the result by looking at it

- Do not grep the `.cast` for caption text: tuios redraws only changed cells, so a caption that
  showed can be absent from the raw stream. Look at frames instead.
- `scripts/contact_sheet.sh VIDEO OUT.png 4 12 20 …` tiles frames at those seconds; add
  `--crop-top 150` for a strip of just the caption rows. Read the PNG to see it.
- ffmpeg `-sseof` finds nothing when the last frame is held long. Use `-ss <late> -update 1`.

## Trim the ending

When the client detaches, the cast ends on "Detached from session" and then a cleared screen. Cut
after the last event that draws the end card, and hold it:

```bash
python3 -I ~/.claude/skills/tuios-recording/scripts/trim_cast.py in.cast out.cast --until-text "PR #47" --hold 3.5
```

Pick text unique to the end card. Without `--until-text`, it cuts at the first detach notice or
alternate-screen exit (`?1049l`), which is where the client starts tearing the screen down.

## Show it

- Live while recording: `tuios popup -- tuios attach demo <chrome flags>` adds a second client. It
  may change the session's size, and the final `detach-client` disconnects it too.
- Playback in the terminal: `tuios popup -- asciinema play out.cast`.
- The GIF/MP4 for a PR or slide; mention the size (a 65 s 200x46 take: 1.3 MB GIF, 0.5 MB MP4).

## Cleanup

Stop driver processes you started (`pkill -f <script>`), close the demo surface
(`tuios tml close SURFACE`), and `tuios kill-session demo` when done. Move outputs out of the
scratchpad if the user wants to keep them.
