#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

has_command() {
    command -v "$1" >/dev/null 2>&1
}

detect_platform() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        case "${ID:-}" in
            nixos) echo nixos ;;
            arch | cachyos | endeavouros | manjarolinux) echo arch ;;
            debian | ubuntu | pop | linuxmint | kali) echo debian ;;
            *) echo unknown ;;
        esac
    else
        echo unknown
    fi
}

install_arch() {
    if ! has_command makepkg; then
        echo "Arch Linux build tools (base-devel) are required." >&2
        exit 1
    fi

    if [[ -f packaging/arch/PKGBUILD ]]; then
        (cd packaging/arch && makepkg -si)
    else
        echo "Missing packaging/arch/PKGBUILD." >&2
        exit 1
    fi
}

install_debian() {
    if ! has_command dpkg-buildpackage; then
        echo "Debian build tools are required: dpkg-buildpackage, build-essential, cargo, and rustc." >&2
        exit 1
    fi

    dpkg-buildpackage -b -uc -us
    sudo -A sh -c 'dpkg -i ../rini_*.deb'
}

install_nixos() {
    if ! has_command nix; then
        echo "Nix is required to install RiNi on NixOS." >&2
        exit 1
    fi

    nix build .#rini
    echo "Built RiNi at ./result/bin/rini"
    echo "To make it available to a NixOS system, add this checkout's flake to your NixOS configuration."
}

install_source() {
    if ! has_command cargo; then
        echo "Cargo and Rust 1.88 or newer are required." >&2
        exit 1
    fi

    cargo build --release --bin rini
    sudo -A install -Dm755 target/release/rini /usr/local/bin/rini
    sudo -A install -Dm755 resources/rini-session /usr/local/bin/rini-session
    sudo -A install -Dm644 resources/rini.desktop /usr/local/share/wayland-sessions/rini.desktop
    sudo -A install -Dm644 resources/rini.png /usr/local/share/pixmaps/rini.png
    sudo -A install -Dm644 resources/rini-portals.conf /usr/local/share/xdg-desktop-portal/rini-portals.conf
    sudo -A install -Dm644 resources/rini.service /etc/systemd/user/rini.service
    sudo -A install -Dm755 resources/dinit/rini /etc/dinit.d/user/rini
    sudo -A install -Dm755 resources/dinit/rini.target /etc/dinit.d/user/rini.target
}

platform="$(detect_platform)"

case "${1:-}" in
    --arch) platform=arch ;;
    --debian) platform=debian ;;
    --nixos) platform=nixos ;;
    --source) platform=source ;;
    --menu)
        PS3="Choose an installation method: "
        select choice in "Automatic detection" "Arch Linux (PKGBUILD)" "Debian/Ubuntu (package)" "NixOS (flake)" "Source/manual"; do
            case "$choice" in
                "Automatic detection") break ;;
                "Arch Linux (PKGBUILD)") platform=arch; break ;;
                "Debian/Ubuntu (package)") platform=debian; break ;;
                "NixOS (flake)") platform=nixos; break ;;
                "Source/manual") platform=source; break ;;
            esac
        done
        ;;
esac

case "$platform" in
    arch) install_arch ;;
    debian) install_debian ;;
    nixos) install_nixos ;;
    source) install_source ;;
    *)
        echo "Could not auto-detect a supported installer." >&2
        echo "Use --menu, or specify --arch, --debian, --nixos, or --source." >&2
        exit 2
        ;;
esac
