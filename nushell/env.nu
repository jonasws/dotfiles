# env.nu
#
# Installed by:
# version = "0.101.0"
#
# Previously, environment variables were typically configured in `env.nu`.
# In general, most configuration can and should be performed in `config.nu`
# or one of the autoload directories.
#
# This file is generated for backwards compatibility for now.
# It is loaded before config.nu and login.nu
#
# See https://www.nushell.sh/book/configuration.html
#
# Also see `help config env` for more options.
#
# You can remove these comments if you want or leave
# them for future reference.
use std  "path add"
path add /opt/homebrew/bin
path add /run/current-system/sw/bin

mkdir ~/.cache/starship
starship init nu | save -f ~/.cache/starship/init.nu
zoxide init nushell | save -f ~/.zoxide.nu


# aws-vault stores the capra-auth master creds and the MFA'd STS session
# cache in the macOS `login` keychain, not the default `aws-vault` one.
# AWS profiles resolve via `credential_process = aws-vault export ...`, so
# every SDK call needs this set to hit the keychain that holds the cached
# session — otherwise aws-vault looks in a non-existent `aws-vault`
# keychain, finds no session, and re-prompts for MFA. fish exports the same
# value, but set it here too so nushell run as a non-fish-child still works.
$env.AWS_VAULT_KEYCHAIN_NAME = 'login'

$env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense' # optional
mkdir ~/.cache/carapace
carapace _carapace nushell | save --force ~/.cache/carapace/init.nu
#
# let mise_path = $nu.default-config-dir | path join mise.nu
# ^mise activate nu | save $mise_path --force
