# Homebrew ahead of /usr/bin, so git, ssh, curl and openssl resolve to
# Homebrew's builds rather than the macOS copies, which lag on security fixes.
# Scripts run with bash read neither file; they inherit PATH from the shell
# that started them, which is why fish sets the same order.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv bash)"
  # Keg-only: shellenv does not link it into /opt/homebrew/bin.
  PATH="$HOMEBREW_PREFIX/opt/curl/bin:$PATH"
fi
