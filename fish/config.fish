# Fish configuration - modularized
# Configuration files are automatically loaded from conf.d/ directory
# Functions are automatically loaded from functions/ directory

# Note: conf.d files are loaded automatically by fish in alphabetical order
# Functions in functions/ directory are loaded on-demand

# Any additional configuration that doesn't fit in conf.d can go here

if status is-interactive
    # Set here rather than in conf.d: config.fish runs after every conf.d file,
    # so nothing loaded earlier can overwrite the theme.
    fish_config theme choose "Catppuccin Mocha"
    set -g fish_key_bindings fish_vi_key_bindings
end
