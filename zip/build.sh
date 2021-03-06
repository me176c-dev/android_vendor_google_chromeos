#!/usr/bin/env bash
set -euo pipefail

# Use consistent environment for reproducible builds
export TZ=UTC
export LC_ALL=C
umask 022

type="${1:-}"
case "$type" in
    widevine) name="Widevine" ;;
    houdini)  name="Houdini" ;;
    "") "$0" widevine && "$0" houdini; exit ;;
    *) echo "Usage: $0 [widevine|houdini]"; exit 1 ;;
esac

cd "$(dirname "$0")"
zip_dir="$PWD"
out_dir="$PWD/out"
main_dir="$(dirname "$PWD")"
version=$(<"$main_dir/proprietary/version")

echo "Building ZIP for $name from ChromeOS $version..."

temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
cd "$temp_dir"

# Generate addond script (runs when upgrading system to restore modifications)
mkdir -p system/addon.d
addond_script="system/addon.d/60-$type.sh"
addond_addon="$zip_dir/addond.$type.sh"
[[ -f "$addond_addon" ]] || addond_addon=""
cat - "$zip_dir/addond.tail.sh" $addond_addon > "$addond_script" <<EOH
#!/sbin/sh
#
# ADDOND_VERSION=1
#
# /$addond_script
# Backup $name (from ChromeOS $version) during upgrades
#

. /tmp/backuptool.functions

list_files() {
cat <<EOF
$(find "$main_dir/proprietary/$type" -type f -printf "%P\n" | sort)
EOF
}
EOH
chmod +x "$addond_script"

# Normalize file modification times for reproducible builds
find system -print0 | xargs -0r touch -hr "$main_dir/proprietary"

# Create tar archive of files to install
source_dir="$main_dir/proprietary/$type"
tar cf "$type.tar" \
    -C "system" "${addond_script#system/}" \
    -C "$source_dir" $(ls "$source_dir") \
    --owner=0 --group=0 --numeric-owner --sort=name

# Generate update-binary (script that handles installation)
mkdir -p META-INF/com/google/android
update_binary_addon="$zip_dir/update-binary.$type.sh"
[[ -f "$update_binary_addon" ]] || update_binary_addon=""
cat - "$zip_dir/update-binary.sh" $update_binary_addon > META-INF/com/google/android/update-binary <<EOF
#!/sbin/sh
TYPE="$type"
NAME="$name"
VERSION="$version"
ADDOND_SCRIPT="/$addond_script"
EOF
echo "# Dummy file; update-binary is a shell script." > META-INF/com/google/android/updater-script

cp "$main_dir/LICENSE" LICENSE

# Normalize file modification times for reproducible builds
find . -print0 | xargs -0r touch -hr "$main_dir/proprietary"

# Generate ZIP file
mkdir -p "$out_dir"
filename="$type-x86-chromeos-$version.zip"
rm -f "$out_dir/$filename"
zip -qX "$out_dir/$filename" \
    META-INF/com/google/android/update-binary \
    META-INF/com/google/android/updater-script \
    LICENSE "$type.tar"
echo "Successfully built: $filename"
