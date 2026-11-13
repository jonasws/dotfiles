#!/bin/sh
# Gives a signal-cli install the libsignal native library for 64-bit ARM Linux.
#
# signal-cli's release tarball bundles libsignal's JNI library for x86_64 Linux,
# macOS and Windows only. On a Raspberry Pi it fails at the first Signal call
# until an aarch64 build is put into lib/libsignal-client-<version>.jar, beside
# the bundled ones. The signal-cli wiki points at exquo/signal-libs-build for
# prebuilt ones:
# https://github.com/AsamK/signal-cli/wiki/Provide-native-lib-for-libsignal
#
# Run by mise as the github:AsamK/signal-cli postinstall (mise.toml), so every
# `mise up` that brings a new signal-cli also brings the matching library.
# The library version must match the jar's exactly, so it is read off the jar
# name rather than pinned here.
#
# usage: libsignal-arm64.sh SIGNAL_CLI_INSTALL_DIR

set -eu

dir=${1:?usage: libsignal-arm64.sh SIGNAL_CLI_INSTALL_DIR}
arch=${LIBSIGNAL_ARCH:-$(uname -m)}

case "$arch" in
  aarch64 | arm64) ;;
  *) exit 0 ;; # the bundled x86_64 library already covers this machine
esac

jar=$(ls "$dir"/lib/libsignal-client-*.jar 2>/dev/null | head -n 1)
[ -n "$jar" ] || {
  echo "libsignal-arm64: no libsignal-client jar under $dir/lib" >&2
  exit 1
}
version=$(basename "$jar" .jar | sed 's/^libsignal-client-//')
entry=libsignal_jni_aarch64.so

if unzip -l "$jar" "$entry" >/dev/null 2>&1; then
  echo "libsignal-arm64: $entry already in $(basename "$jar")"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
url="https://github.com/exquo/signal-libs-build/releases/download/libsignal_v${version}/libsignal_jni.so-v${version}-aarch64-unknown-linux-gnu.tar.gz"
echo "libsignal-arm64: fetching libsignal $version for aarch64"
curl -fsSL "$url" -o "$work/lib.tgz"
tar -xzf "$work/lib.tgz" -C "$work" libsignal_jni.so
mv "$work/libsignal_jni.so" "$work/$entry"

# libsignal loads lib<name>_<os.arch>.so from the jar root, the same naming as
# the bundled libsignal_jni_amd64.so and libsignal_jni_aarch64.dylib. The x86_64
# library is dropped too: it is 200 MB this machine can't load.
zip -q -d "$jar" libsignal_jni_amd64.so >/dev/null 2>&1 || true
(cd "$work" && zip -q -j "$jar" "$entry")
echo "libsignal-arm64: added $entry to $(basename "$jar")"
