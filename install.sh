#!/usr/bin/env bash
set -euo pipefail

REPO="jolexxa/cow"
INSTALL_DIR="$HOME/.local/lib/cow"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/cow"

info() { printf '\033[1;34m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
error() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Detect platform 
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Darwin)
    case "$ARCH" in
      arm64) PLATFORM="macos_arm64"; EXT="zip" ;;
      *) error "Unsupported macOS architecture: $ARCH (only Apple Silicon is supported)" ;;
    esac
    ;;
  Linux)
    case "$ARCH" in
      x86_64) PLATFORM="linux_x64"; EXT="tar.gz" ;;
      *) error "Unsupported Linux architecture: $ARCH (only x64 is supported)" ;;
    esac
    ;;
  *) error "Unsupported OS: $OS" ;;
esac

info "Detected platform: $PLATFORM"

# Download latest release 
URL="https://github.com/$REPO/releases/latest/download/cow-${PLATFORM}.${EXT}"
TMPDIR="$(mktemp -d)"
ARCHIVE="$TMPDIR/cow.$EXT"

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

info "Downloading $URL"
curl -fSL "$URL" -o "$ARCHIVE"

# Extract 
info "Extracting archive"
EXTRACT_DIR="$TMPDIR/cow"
mkdir -p "$EXTRACT_DIR"

if [ "$EXT" = "zip" ]; then
  unzip -qo "$ARCHIVE" -d "$EXTRACT_DIR"
else
  tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"
fi

# Install 
info "Installing to $INSTALL_DIR"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR" "$BIN_DIR"
cp -R "$EXTRACT_DIR"/* "$INSTALL_DIR"/
chmod +x "$INSTALL_DIR/bin/cow"
ln -sf "$INSTALL_DIR/bin/cow" "$BIN_LINK"

# macOS: de-quarantine 
if [ "$OS" = "Darwin" ]; then
  info "Removing macOS quarantine attributes"
  xattr -rd com.apple.quarantine "$INSTALL_DIR" 2>/dev/null || true
fi

# Check PATH 
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
  warn ""
  warn "~/.local/bin is not in your PATH!"
  warn ""
  warn "Add this to your shell config:"
  warn ""
  if [ -f "$HOME/.zshrc" ] || [ "$OS" = "Darwin" ]; then
    warn "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
  else
    warn "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
  fi
  warn ""
  warn "Then restart your shell or run: source ~/.zshrc (or ~/.bashrc)"
fi

# Done 
info ""
info "Installed cow to $BIN_LINK"
