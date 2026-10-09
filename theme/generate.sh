#!/bin/sh
# Render every template in theme/templates from theme/palette.env.
# Placeholders look like @NAME@. Fails loudly on unknown names or bad colors,
# so a typo never silently ends up in a config.
#
# Outputs are relative to the repo root, or start with ~/ for other repos
# (e.g. ~/my_st/colors.h).
#
# Usage: theme/generate.sh [--check]   (--check: render to a temp dir only)
set -eu

theme_dir=$(dirname "$(readlink -f "$0")")
repo_dir=$(dirname "$theme_dir")
palette="$theme_dir/palette.env"
check_only=${1:-}

# Build a sed script from the palette, validating every entry
sed_script=$(mktemp)
trap 'rm -f "$sed_script"' EXIT
grep -Ev '^[[:space:]]*(#|$)' "$palette" | while IFS='=' read -r name value; do
    case $name in *[!A-Z0-9_]*|'') echo "bad name: '$name'" >&2; exit 1 ;; esac
    printf '%s' "$value" | grep -Eq '^#[0-9a-fA-F]{6}$' || { echo "bad color for $name: '$value'" >&2; exit 1; }
    printf 's|@%s@|%s|g\n' "$name" "$value"
done > "$sed_script"

out_root=$repo_dir
[ "$check_only" = "--check" ] && out_root=$(mktemp -d)

grep -Ev '^[[:space:]]*(#|$)' "$theme_dir/targets" | while read -r template output; do
    # Outputs starting with ~/ live outside this repo (e.g. the st repo)
    # shellcheck disable=SC2088  # literal "~/" pattern match, not expansion
    case $output in
        "~/"*) if [ "$check_only" = "--check" ]; then dest="$out_root/home/${output#\~/}"
               else dest="$HOME/${output#\~/}"; fi ;;
        *)     dest="$out_root/$output" ;;
    esac
    mkdir -p "$(dirname "$dest")"
    sed -f "$sed_script" "$theme_dir/templates/$template" > "$dest.tmp"
    if leftover=$(grep -o '@[A-Z0-9_]*@' "$dest.tmp" | sort -u | tr '\n' ' ') && [ -n "$leftover" ]; then
        rm -f "$dest.tmp"
        echo "$template: unknown placeholder(s): $leftover" >&2
        exit 1
    fi
    mv "$dest.tmp" "$dest"
    echo "rendered $output"
done

[ "$check_only" = "--check" ] && echo "check ok (output in $out_root)"
exit 0
