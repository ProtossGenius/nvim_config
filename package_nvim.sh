#!/usr/bin/env bash

set -euo pipefail

script_name=$(basename "$0")
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
target_dir="$script_dir/target"
installer_path="$target_dir/install.sh"

usage() {
  cat <<EOF
Usage: $script_name [-h]

Build a self-extracting Neovim installer at:
  $installer_path

The generated installer embeds:
  - this Neovim config
  - lazy.nvim plugin downloads
  - Mason packages and registries
  - nvim-java managed runtime data
  - optional site/ runtime data if present

Running the generated install.sh will:
  1. Remove existing Neovim config and data directories
  2. Extract and install the bundled config and data

Options:
  -h, --help    Show this help message
EOF
}

case $# in
  0)
    ;;
  1)
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        exit 1
        ;;
    esac
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

mkdir -p "$target_dir"

tmp_dir=$(mktemp -d "$target_dir/.nvim-bundle.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

bundle_root="$tmp_dir/nvim-bundle"
config_root="$bundle_root/config/nvim"
data_root="$bundle_root/data/nvim"

mkdir -p "$config_root" "$data_root"

cp -a \
  "$script_dir/README.md" \
  "$script_dir/docs" \
  "$script_dir/init.lua" \
  "$script_dir/lazy-lock.json" \
  "$script_dir/lua" \
  "$config_root/"

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
source_data_root="$data_home/nvim"

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

copy_data_dir() {
  local name="$1"
  local source="$source_data_root/$name"
  if [ -e "$source" ]; then
    cp -a "$source" "$data_root/$name"
  fi
}

copy_data_dir "lazy"
copy_data_dir "mason"
copy_data_dir "nvim-java"
copy_data_dir "site"

payload_archive="$tmp_dir/payload.tar.gz"
tar -czf "$payload_archive" -C "$tmp_dir" "nvim-bundle"

# Write the installer header to a temp file first, then compute byte offset
installer_header="$tmp_dir/header.sh"
cat >"$installer_header" <<'HEADER'
#!/usr/bin/env bash

set -euo pipefail

script_name=$(basename "$0")

usage() {
  cat <<USAGE
Usage: $script_name [-h] [-y]

Install the bundled Neovim config and data into the current user's XDG paths.

This will REMOVE any existing Neovim configuration before installing.

Targets:
  config -> ${XDG_CONFIG_HOME:-$HOME/.config}/nvim
  data   -> ${XDG_DATA_HOME:-$HOME/.local/share}/nvim

Options:
  -h, --help    Show this help message
  -y, --yes     Skip confirmation prompt
USAGE
}

skip_confirm=false

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    -y|--yes)
      skip_confirm=true
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

config_target="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
data_target="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
BUNDLED_DATA_ROOT=PLACEHOLDER_DATA_ROOT

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

rewrite_embedded_data_paths() {
  local search_root="$1"
  local target_root="$2"
  local from_escaped
  local to_escaped
  local path

  [ -d "$search_root" ] || return 0

  # Rewrite embedded absolute data paths in bundled text files so Mason-managed
  # wrappers and similar launchers still work after installing as another user.
  from_escaped=$(escape_sed_replacement "$BUNDLED_DATA_ROOT")
  to_escaped=$(escape_sed_replacement "$target_root")

  while IFS= read -r -d '' path; do
    sed -i "s|$from_escaped|$to_escaped|g" "$path"
  done < <(grep -rIlZ -F "$BUNDLED_DATA_ROOT" "$search_root" || true)
}

if [ "$skip_confirm" = false ]; then
  echo "This will remove and replace:"
  echo "  config: $config_target"
  echo "  data:   $data_target"
  printf "Continue? [y/N] "
  read -r answer
  case "$answer" in
    [yY]|[yY][eE][sS]) ;;
    *)
      echo "Aborted."
      exit 0
      ;;
  esac
fi

echo "Removing old Neovim config and data..."
rm -rf "$config_target"
rm -rf "$data_target"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# Use byte offset to extract payload (robust against binary content)
HEADER_BYTES=PLACEHOLDER_BYTES
tail -c +"$((HEADER_BYTES + 1))" "$0" | tar -xzf - -C "$tmp_dir"

rewrite_embedded_data_paths "$tmp_dir/nvim-bundle/data/nvim" "$data_target"

mkdir -p "$config_target" "$data_target"

cp -a "$tmp_dir/nvim-bundle/config/nvim"/. "$config_target"/

if [ -d "$tmp_dir/nvim-bundle/data/nvim" ]; then
  for source_path in "$tmp_dir/nvim-bundle/data/nvim"/*; do
    [ -e "$source_path" ] || continue
    name=$(basename "$source_path")
    if [ -d "$source_path" ]; then
      mkdir -p "$data_target/$name"
      cp -a "$source_path"/. "$data_target/$name"/
    else
      cp -a "$source_path" "$data_target/$name"
    fi
  done
fi

echo ""
echo "Installed config to $config_target"
echo "Installed data to   $data_target"
echo "Done! Run 'nvim' to verify."
exit 0
HEADER

# Patch the byte-offset placeholder to the real header size.
# Iterate because replacing the placeholder changes the file size.
bundled_data_root=$(printf '%q' "$source_data_root")
bundled_data_root_escaped=$(escape_sed_replacement "$bundled_data_root")
sed -i "s|^BUNDLED_DATA_ROOT=.*$|BUNDLED_DATA_ROOT=${bundled_data_root_escaped}|" "$installer_header"
prev_bytes=0
header_bytes=$(wc -c < "$installer_header")
while [ "$header_bytes" != "$prev_bytes" ]; do
  prev_bytes=$header_bytes
  sed -i "s/^HEADER_BYTES=.*$/HEADER_BYTES=${header_bytes}/" "$installer_header"
  header_bytes=$(wc -c < "$installer_header")
done

# Assemble: header + binary payload
cat "$installer_header" "$payload_archive" > "$installer_path"
chmod +x "$installer_path"

echo "Created $installer_path ($(du -h "$installer_path" | cut -f1))"
