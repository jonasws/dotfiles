// Generates the complex_modifications of the Default profile in
// ../karabiner/.config/karabiner/karabiner.json. Per-device settings stay in
// that file: karabiner.ts leaves everything but the rules alone.
//
//   bun karabiner.config.ts            write the repo copy
//   bun karabiner.config.ts --dry-run  print the rules instead
import {
  ifApp,
  ifDevice,
  map,
  mapDoubleTap,
  rule,
  writeToProfile,
} from 'karabiner.ts'

const target = {
  name: 'Default profile',
  dryRun: process.argv.includes('--dry-run'),
  karabinerJsonPath: new URL(
    '../karabiner/.config/karabiner/karabiner.json',
    import.meta.url,
  ).pathname,
}

// Apps with their own ctrl+hjkl handling.
const ownsCtrlHjkl = [
  /^com\.github\.wez\.wezterm$/,
  /^com\.mitchellh\.ghostty$/,
  /^com\.superlogical\.rex$/,
  /^dev\.zed\.Zed$/,
  /^dev\.zed\.Zed-Preview$/,
  /^dev\.raycast\.macos$/,
]

// Terminals where Option is Alt (Meta), right Option included, for M- keys in
// Neovim, tuios and herdr: WezTerm's send_composed_key_when_*_alt_is_pressed =
// false, Ghostty's macos-option-as-alt = true.
const optionIsMeta = [
  /^com\.github\.wez\.wezterm$/,
  /^com\.mitchellh\.ghostty$/,
]

const arrows = [
  ['h', 'left_arrow'],
  ['j', 'down_arrow'],
  ['k', 'up_arrow'],
  ['l', 'right_arrow'],
] as const

writeToProfile(
  target,
  [
    rule('Better Shifting: End parenthesis on shift + space').manipulators([
      map('spacebar', 'right_shift')
        .to('0', 'right_shift')
        .to('spacebar'),
    ]),

    rule('Better Shifting: Shift rolls').manipulators([
      map('left_shift', 'right_shift')
        .to('left_shift')
        .to('right_shift')
        .toIfAlone('0', ['right_shift', 'left_shift'])
        .toIfAlone('9', ['right_shift', 'left_shift']),
      map('right_shift', 'left_shift')
        .to('right_shift')
        .to('left_shift')
        .toIfAlone('9', 'right_shift')
        .toIfAlone('0', 'right_shift'),
    ]),

    rule('Better Shifting: Parentheses on shift keys').manipulators([
      map('left_shift').to('left_shift').toIfAlone('9', 'left_shift'),
      map('right_shift').to('right_shift').toIfAlone('0', 'right_shift'),
    ]),

    rule(
      'Right Option Key → Hyper Key (⌃⌥⇧⌘, built-in keyboard only, except in WezTerm and Ghostty where right_option stays Meta for M- keybinds)',
    ).manipulators([
      // Held, it is Hyper. Tapped twice, it sends F19, which Ghostty binds
      // globally to its Quick Terminal (ghostty/config.ghostty).
      mapDoubleTap('right_option', null, 'any')
        .to('f19')
        .singleTap({
          key_code: 'left_shift',
          modifiers: ['left_command', 'left_control', 'left_option'],
        })
        .condition(ifDevice({ is_built_in_keyboard: true }))
        .condition(ifApp(optionIsMeta).unless()),
      // In those terminals a held right Option stays Option, and a double tap
      // still sends F19, so the Quick Terminal also hides from Ghostty itself.
      mapDoubleTap('right_option', null, 'any')
        .to('f19')
        .condition(ifDevice({ is_built_in_keyboard: true }))
        .condition(ifApp(optionIsMeta)),
    ]),

    rule('Hyper + b → Control + b (herdr prefix)').manipulators([
      map('b', ['left_command', 'left_control', 'left_option', 'left_shift'])
        .to('b', 'left_control'),
    ]),

    rule('Post Esc if Caps is tapped, Control if held (except in WezTerm)')
      .manipulators([
        map('caps_lock', null, 'any')
          .to('left_control', undefined, { lazy: true })
          .toIfAlone('escape'),
      ]),

    rule('Change left_control+hjkl to arrow keys').manipulators(
      arrows.map(([key, arrow]) =>
        map(key, 'left_control', 'any')
          .to(arrow)
          .condition(ifApp(ownsCtrlHjkl).unless()),
      ),
    ),
  ],
  { 'basic.to_if_alone_timeout_milliseconds': 250 },
)
