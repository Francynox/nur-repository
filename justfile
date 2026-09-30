set shell := ["bash", "-c"]

# Help: List available recipes
@help:
    just --list --unsorted

#-------------------------------------------------------------------------------
# Packages
#-------------------------------------------------------------------------------

# Build a package against a nixpkgs channel (default: flake pin).
# E.g. `just build kea nixos-26.05` for the stable leg frablab consumes.
[no-exit-message]
build pkg channel="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "{{ channel }}" ]; then
        nix build ".#packages.x86_64-linux.{{ pkg }}" --print-build-logs
    else
        nix build --override-input nixpkgs "github:NixOS/nixpkgs/{{ channel }}" \
            ".#packages.x86_64-linux.{{ pkg }}" --print-build-logs
    fi

# Build a package against all CI channels (mirrors check-pr.yml matrix)
build-matrix pkg:
    #!/usr/bin/env bash
    set -euo pipefail
    for channel in nixpkgs-unstable nixos-unstable nixos-26.05; do
        echo "=== $channel ==="
        nix build --override-input nixpkgs "github:NixOS/nixpkgs/$channel" \
            ".#packages.x86_64-linux.{{ pkg }}" --print-build-logs
    done

#-------------------------------------------------------------------------------
# Updates
#-------------------------------------------------------------------------------

# Update a package (version + hash) via its passthru.updateScript, like CI does.
# E.g. `just update kea`
[no-exit-message]
update pkg:
    #!/usr/bin/env bash
    set -euo pipefail
    nix run nixpkgs#nix-update -- --flake -u "{{ pkg }}"
    rm -f update-git-commits.txt
