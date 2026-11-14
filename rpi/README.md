# Raspberry Pi: pi agents in tuios, served by Rex

A headless Raspberry Pi that runs [pi](https://github.com/earendil-works/pi)
coding agents in [tuios](https://github.com/Gaurav-Gosain/tuios) panes, reached
from Rex for Mac through a [Rex server](https://www.superlogical.com/rex/docs/linux/installation)
on the Pi. pi talks to Anthropic with an API key; the default model is Claude
Sonnet 5.5.

None of the Mac's groups deploy here. [`mise.rpi.toml`](../mise.rpi.toml)
declares four groups and selects only those, and it loads only with
`MISE_ENV=rpi`, so the Mac's `mise dot apply` never sees it.

| Group | Source | Linked to | Holds |
| ----- | ------ | --------- | ----- |
| `rpi-mise` | [`mise/`](mise/) | `~/.config/mise/config.toml` | node, pi and tuios |
| `rpi-pi` | [`pi-agent/`](pi-agent/) | `~/.pi/agent/` (each file) | `settings.json` (Anthropic, `claude-sonnet-5-5`), `AGENTS.md`, and a generated `auth.json` |
| `rpi-tuios` | [`tuios/`](tuios/) | `~/.config/tuios` (the folder) | one Rex status per agent pane |
| `rpi-rex` | [`rex/`](rex/) | `~/.config/rex/init.lua` | the tuios actions, with pi as the agent Start an Agent runs |

## Set up

Needs a 64-bit OS (Rex has no 32-bit ARM build). Nothing here installs
software: [`setup.sh`](setup.sh) checks and stops with what is missing.

```sh
git clone https://github.com/jonasws/dotfiles ~/dotfiles   # dotfiles.root is ~/dotfiles
# install mise and Rex yourself, then once:
rex server install
~/dotfiles/rpi/setup.sh   # links the groups, then stops: node, pi, tuios missing
mise install              # from the linked rpi/mise/config.toml
~/dotfiles/rpi/setup.sh   # asks for the API key once, wires up the integrations
```

`setup.sh`, in order:

1. Checks the machine is aarch64, the repo is at `~/dotfiles`, `mise` and
   `rex` are on `PATH`, and a Rex server answers.
2. Runs `MISE_ENV=rpi mise -C ~/dotfiles dot apply`.
3. Checks `node` (22 or newer), `pi` and `tuios`, with mise's shims on `PATH`.
4. Asks for the Anthropic API key if `~/.config/anthropic/key` is missing,
   and keeps it at mode 600.
5. Runs `rex skill setup --agent pi`, `tuios integration install pi`,
   `tuios integration install rex` and `tuios doctor agents`.

It is safe to run again.

## The API key

`~/.pi/agent/auth.json` is written once by the `rpi-pi` group (it is never
overwritten, and not tracked) and holds a command, not the key:

```json
{"anthropic":{"type":"api_key","key":"!cat \"$HOME/.config/anthropic/key\""}}
```

pi runs it in its shell the first time it needs the key. The Rex server and
the tuios daemon don't start from a login shell, so an `ANTHROPIC_API_KEY`
export in a shell rc would not reach an agent started by `rex do
tuios_start_agent` or `tuios start-agent`; the file does.

## Use

Add the Pi in Rex for Mac with **Add Remote Host…** (`ssh://you@raspberrypi.local`)
and run `tuios` in a pane. Then, from the Rex palette or the CLI:

```sh
rex do tuios_start_agent name=review prompt='Review the diff.' folder=~/src/app
```

`ctrl+b i` opens tuios's Inbox. `rex actions | grep tuios_` lists the rest.

## Changing the Pi's setup

- **Another default model:** `defaultModel` in `pi-agent/settings.json`, or
  `/model` and `Ctrl+S` in pi (which writes through the link).
- **Mac-only `[dotfiles]` entries:** entries in `mise.toml`'s `[dotfiles]`
  table deploy whatever groups are selected. `mise.rpi.toml` turns off the
  fnox wrappers and herdr's rename hook; turn off any new Mac-only entry there
  too.
