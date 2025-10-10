#!/bin/bash

# Setup script to link fish functions and copy conf.d files
# Run this script to apply the modular fish configuration

set -e

FISH_CONFIG_DIR="$HOME/.config/fish"
DOTFILES_FISH_DIR="$HOME/dotfiles/fish"

echo "Setting up fish configuration links..."

# Create backup of existing config.fish if it's not already a symlink
if [ ! -L "$FISH_CONFIG_DIR/config.fish" ]; then
    echo "Backing up existing config.fish..."
    mv "$FISH_CONFIG_DIR/config.fish" "$FISH_CONFIG_DIR/config.fish.old"
fi

# Link config.fish
echo "Linking config.fish..."
ln -sf "$DOTFILES_FISH_DIR/config.fish" "$FISH_CONFIG_DIR/config.fish"

# Link individual functions
echo "Linking custom functions..."
for func_file in "$DOTFILES_FISH_DIR/functions"/*.fish; do
    if [ -f "$func_file" ]; then
        func_name=$(basename "$func_file")
        echo "  Linking $func_name..."
        ln -sf "$func_file" "$FISH_CONFIG_DIR/functions/$func_name"
    fi
done

# Link individual completions
echo "Linking custom completions..."
for comp_file in "$DOTFILES_FISH_DIR/completions"/*.fish; do
    if [ -f "$comp_file" ]; then
        comp_name=$(basename "$comp_file")
        echo "  Linking $comp_name..."
        ln -sf "$comp_file" "$FISH_CONFIG_DIR/completions/$comp_name"
    fi
done

# Copy conf.d files (don't link to avoid conflicts with fisher)
echo "Copying conf.d files..."
for conf_file in "$DOTFILES_FISH_DIR/conf.d"/*.fish; do
    if [ -f "$conf_file" ]; then
        conf_name=$(basename "$conf_file")
        echo "  Copying $conf_name..."
        cp "$conf_file" "$FISH_CONFIG_DIR/conf.d/$conf_name"
    fi
done

echo "Fish configuration setup complete!"
echo "You can now edit files in $DOTFILES_FISH_DIR and they will be immediately available."
echo "Functions and completions are symlinked, conf.d files are copied."