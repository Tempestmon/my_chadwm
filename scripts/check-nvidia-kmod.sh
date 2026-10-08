#!/bin/sh
# Verify that the NVIDIA kernel module is built for every installed kernel.
# Run after `xbps-install -Su` and BEFORE rebooting.
# Exit code: 0 = all kernels have the module, 1 = at least one is missing.
#
# ROOT_DIR can be overridden for testing (default: the real system, /).
set -eu

root_dir=${ROOT_DIR:-/}
status=0

for dir in "$root_dir"/lib/modules/*/; do
    kver=$(basename "$dir")
    if version=$(modinfo -b "$root_dir" -k "$kver" -F version nvidia 2>/dev/null) \
        && [ -n "$version" ]; then
        printf 'ok       %-14s nvidia %s\n' "$kver" "$version"
    else
        printf 'MISSING  %-14s (do not boot this kernel)\n' "$kver"
        status=1
    fi
done

printf 'running  %s\n' "$(uname -r)"
exit "$status"
