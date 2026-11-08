---
name: show-image
description: Show an image file (PNG, JPG, GIF, WebP) as a real picture in a new tuios pane, using `kitten icat` run through `mise exec`. Use whenever the user asks to show, open, view, display or preview an image, screenshot, chart or rendered diagram "in a pane", "in the terminal" or "here", including a PNG you just rendered from Mermaid or a plotting script. Needs TUIOS_ENV=1; the terminal is Ghostty, which draws kitty graphics.
---

# Show an image in a tuios pane

tuios has no image viewer of its own. It passes kitty graphics (and sixel) from a
program in a pane through to Ghostty, so the pane needs a viewer that speaks the kitty
graphics protocol. `kitten icat` is the reference one, and kitty ships `kitten` as a
standalone binary, so it runs through mise with no kitty install and no Homebrew.

Ghostty has no `imgcat` of its own, and wezterm's `imgcat` is not an option here.

## The command

```bash
tuios new-window <name> --no-focus --keep-open -- \
  mise exec 'github:kovidgoyal/kitty[bin=kitten,matching=kitten-darwin-arm64]' -- \
  kitten icat <absolute-path>
```

- `--keep-open`: icat draws and exits at once; without it the window closes and the
  picture goes with it. The pane then shows "[The program exited with status 0.]"
  under the image, which is expected.
- `--no-focus` leaves the user where they are; drop it when they asked to look now.
- Pass an absolute path. The new window starts in the caller's directory, but the
  scratchpad and other agents' files are elsewhere.
- Name the window after the image (`lkw-timeline`), so it can be closed or reused
  with `-w <name>` later.
- The first run downloads kitty's release (a few seconds); later runs use mise's
  cache.

## Check it worked

`tuios capture-pane -w <name>` (or the `tuios_capture_pane` MCP tool) returns text
only, so it cannot show the picture. Exit status 0 with no error text means icat drew
it. Ask the user to confirm they see it rather than claiming so.

If the pane shows an error instead:

- `mise` cannot find a matching asset: the release changed its asset names. Look at
  the latest `kovidgoyal/kitty` release and adjust `matching=`.
- icat says the terminal does not support graphics: no attached client answered
  tuios's kitty graphics query (for example a detached session, or a client in a
  terminal without graphics). Ask the user to attach from Ghostty and run it again.

## Diagrams

For a Mermaid diagram, render it to PNG first (`sketch file.mmd -o file.png -scale 3`)
and show the PNG, so the user sees exactly the file they will share. When they want a
live view that redraws on save instead, `tuios mermaid --watch --fit file.mmd` in a new
window draws the diagram itself, with no image file.

## Sharing

For Slack, share the PNG. Slack does not render SVG inline, and sketch's SVG has no
background, so it reads badly in dark mode.
