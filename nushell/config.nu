# config.nu
#
# Installed by:
# version = "0.101.0"
#
# This file is used to override default Nushell settings, define
# (or import) custom commands, or run any other startup tasks.
# See https://www.nushell.sh/book/configuration.html
#
# This file is loaded after env.nu and before login.nu
#
# You can open this file in your default editor using:
# config nu
#
# See `help config nu` for more options
#
# You can remove these comments if you want or leave
# them for future reference.
# plugin add  ~/.cargo/bin/nu_plugin_polars
# plugin add  ~/.cargo/bin/nu_plugin_query

$env.config = {
    table: {
        mode: 'reinforced'
        missing_value_symbol: '❌'
    }
    datetime_format: {
        normal: "%Y/%m/%d %H:%M:%S"
        table: "%Y/%m/%d %H:%M:%S"
    }
    show_banner: false
    buffer_editor:  "nvim"
    history: {
        file_format: "sqlite"
    }
    ls: {
        clickable_links: true
    }
    use_kitty_protocol: true
    completions: {
        case_sensitive: false # set to true to enable case-sensitive completions
        quick: true    # set this to false to prevent auto-selecting completions when only one remains
        partial: true    # set this to false to prevent partial filling of the prompt
        algorithm: "fuzzy"    # prefix or fuzzy
        external: {
            enable: true # set to false to prevent nushell looking into $env.PATH to find more suggestions, `false` recommended for WSL users as this look up may be very slow
            max_results: 100 # setting it lower can improve completion performance at the cost of omitting some options
            completer: null # check 'carapace_completer' above as an example
        }
        use_ls_colors: true # set this to true to enable file/path/directory completions using LS_COLORS
    }
    edit_mode: vi
    shell_integration: {
     # osc2 abbreviates the path if in the home_dir, sets the tab/window title, shows the running command in the tab/window title
        osc2: true
        # osc7 is a way to communicate the path to the terminal, this is helpful for spawning new tabs in the same directory
        osc7: true
        # osc8 is also implemented as the deprecated setting ls.show_clickable_links, it shows clickable links in ls output if your terminal supports it. show_clickable_links is deprecated in favor of osc8
        osc8: true
        # osc9_9 is from ConEmu and is starting to get wider support. It's similar to osc7 in that it communicates the path to the terminal
        osc9_9: false
        # osc133 is several escapes invented by Final Term which include the supported ones below.
        # 133;A - Mark prompt start
        # 133;B - Mark prompt end
        # 133;C - Mark pre-execution
        # 133;D;exit - Mark execution finished with exit code
        # This is used to enable terminals to know where the prompt is, the command is, where the command finishes, and where the output of the command is
        osc133: true
        # osc633 is closely related to osc133 but only exists in visual studio code (vscode) and supports their shell integration features
        # 633;A - Mark prompt start
        # 633;B - Mark prompt end
        # 633;C - Mark pre-execution
        # 633;D;exit - Mark execution finished with exit code
        # 633;E - NOT IMPLEMENTED - Explicitly set the command line with an optional nonce
        # 633;P;Cwd=<path> - Mark the current working directory and communicate it to the terminal
        # and also helps with the run recent menu in vscode
        osc633: true
        # reset_application_mode is escape \x1b[?1l and was added to help ssh work better
        reset_application_mode: true
    }
  #   keybindings: [
  #   {
  #     name: vim_normal_history_complete
  #     mode: vi_normal
  #     modifier: null
  #     keycode: char_$
  #     event: {
  #       send: HistoryHintComplete
  #     }
  #   }
  # ]
}

alias e = explore -i
alias n = nvim
alias la = ls --all
alias gupa = git pull --rebase --autostash
alias gp = git push
alias gca = git commit --verbose --all
alias gc = git commit --verbose


mkdir ($nu.data-dir | path join "vendor/autoload")
starship init nu | save -f ($nu.data-dir | path join "vendor/autoload/starship.nu")

source ~/.zoxide.nu
source ~/.cache/carapace/init.nu
# source ~/.local/share/atuin/init.nu
use ~/.cache/starship/init.nu

overlay use ~/overlays/logs.nu
overlay use ~/overlays/otr.nu
overlay use ~/overlays/aws.nu
overlay use ~/dotfiles/nushell/functions/nittedal.nu
overlay use ~/overlays/evn-validator.nu

use ($nu.default-config-dir | path join mise.nu)
