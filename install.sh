#!/usr/bin/env bash
# Install (or repair) AirMedia Share for the current user. No sudo; nothing system-wide.
#
#   ./install.sh            install or update from this folder
#   ./install.sh --repair   rebuild the Python environment (e.g. after a distro upgrade);
#                           works from the installed copy too:
#                           ~/.local/share/airmedia-share/install.sh --repair
#
# Installs:
#   ~/.local/share/airmedia-share/     app code (lib/), private venv (venv/), these scripts
#   ~/.local/bin/airmedia-share        launcher
#   ~/.local/share/applications/airmedia-share.desktop
# Settings live in ~/.config/airmedia-share/, the log in ~/.cache/airmedia-share/.
# Undo with ./uninstall.sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_HOME="$DATA/airmedia-share"
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/airmedia-share"
DESKTOP="$DATA/applications/airmedia-share.desktop"
REPAIR=0
[[ "${1:-}" == "--repair" ]] && REPAIR=1

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

# Where the sources are: a checkout (./airmedia_share) or the installed copy (./lib).
if [[ -d "$HERE/airmedia_share" ]]; then
    SRC_PKG="$HERE/airmedia_share"
elif [[ -d "$HERE/lib/airmedia_share" ]]; then
    SRC_PKG="$HERE/lib/airmedia_share"
else
    echo "Cannot find airmedia_share next to $0" >&2; exit 1
fi

# ---- system requirements (reported, never installed with sudo behind your back)
# Names verified on the distros listed; anything else only gets the generic list.
case "$(. /etc/os-release 2>/dev/null; echo "${ID:-} ${ID_LIKE:-}")" in
    *debian*|*ubuntu*)
        PM_INSTALL="sudo apt install"
        PKGS=(python3-venv python3-gi gir1.2-gtk-3.0 gir1.2-wnck-3.0 gir1.2-notify-0.7
              pulseaudio-utils zenity)
        have_pkg() {
            dpkg-query -W -f='${Status}' "$1" 2>/dev/null \
                | grep -q "install ok installed"
        }
        ;;
    *fedora*|*rhel*)
        # Verified on Fedora 44 (2026-11-12): the Gtk/Wnck/Notify typelibs ship in the
        # library packages themselves, python3-gobject pulls in the cairo bindings a
        # GTK app needs, and venv comes with python3 — there is no python3-venv.
        PM_INSTALL="sudo dnf install"
        PKGS=(python3-gobject gtk3 libwnck3 libnotify pulseaudio-utils zenity)
        have_pkg() { rpm -q "$1" >/dev/null 2>&1; }
        ;;
    *)
        PM_INSTALL=""
        PKGS=()
        ;;
esac

if ((${#PKGS[@]})); then
    missing=()
    for pkg in "${PKGS[@]}"; do
        have_pkg "$pkg" || missing+=("$pkg")
    done
    if ((${#missing[@]})); then
        echo "Missing system packages, so nothing was installed yet. Install them, then" >&2
        echo "run this again:" >&2
        echo "    $PM_INSTALL ${missing[*]}" >&2
        exit 1
    fi
else
    # Unknown distro: check what the app actually calls for, not package names.
    missing=()
    for tool in parec pactl zenity; do
        command -v "$tool" >/dev/null || missing+=("$tool")
    done
    /usr/bin/python3 - <<'EOF' 2>/dev/null || missing+=("Python GTK3 bindings (Gtk 3.0, Wnck 3.0, Notify 0.7)")
import gi
for ns, ver in (("Gtk", "3.0"), ("Wnck", "3.0"), ("Notify", "0.7")):
    gi.require_version(ns, ver)
    __import__("gi.repository", fromlist=[ns])
EOF
    /usr/bin/python3 -c "import venv, ensurepip" 2>/dev/null \
        || missing+=("Python venv support (ensurepip)")
    if ((${#missing[@]})); then
        echo "This distro is not one install.sh knows package names for, and these" >&2
        echo "requirements are not met yet:" >&2
        printf '    %s\n' "${missing[@]}" >&2
        echo "Install your distro's equivalents and run this again. Please report the" >&2
        echo "names that worked: https://github.com/Just-Antonio/airmedia-share/issues/1" >&2
        exit 1
    fi
fi

if [[ "${XDG_SESSION_TYPE:-x11}" == "wayland" ]]; then
    echo "Note: this session is Wayland. AirMedia Share captures the screen and lists"
    echo "      windows through X11 (libwnck), which does not work under Wayland."
    echo "      Log out and pick an X11/Xorg session for your desktop, then run it there."
fi

# ---- private Python environment
# --system-site-packages only for the distro's GTK bindings (python3-gi);
# PYTHONNOUSERSITE keeps ~/.local/lib/python3.* out of it entirely.
export PYTHONNOUSERSITE=1
mkdir -p "$APP_HOME"
if ((REPAIR)) || [[ ! -x "$APP_HOME/venv/bin/python" ]] || ! "$APP_HOME/venv/bin/python" -c "" 2>/dev/null; then
    say "Creating Python environment"
    rm -rf "$APP_HOME/venv"
    /usr/bin/python3 -m venv --system-site-packages "$APP_HOME/venv"
fi
REQS="$HERE/requirements.txt"
say "Installing pinned Python packages"
"$APP_HOME/venv/bin/python" -m pip install --quiet --disable-pip-version-check \
    --upgrade pip
"$APP_HOME/venv/bin/python" -m pip install --quiet --disable-pip-version-check \
    --ignore-installed -r "$REQS"

# ---- app files (skip when repairing from the installed copy itself)
if [[ "$SRC_PKG" != "$APP_HOME/lib/airmedia_share" ]]; then
    say "Copying the app"
    rm -rf "$APP_HOME/lib"
    mkdir -p "$APP_HOME/lib"
    cp -r "$SRC_PKG" "$APP_HOME/lib/"
    find "$APP_HOME/lib" -name __pycache__ -prune -exec rm -rf {} +
    cp "$HERE/install.sh" "$HERE/uninstall.sh" "$REQS" "$APP_HOME/"
    mkdir -p "$APP_HOME/data" "$APP_HOME/bin"
    cp "$HERE/data/airmedia-share.desktop.in" "$APP_HOME/data/"
    cp "$HERE/bin/airmedia-share" "$APP_HOME/bin/"
fi
mkdir -p "$BIN_DIR" "$(dirname "$DESKTOP")"
install -m 755 "$APP_HOME/bin/airmedia-share" "$BIN"
sed "s|@BIN@|$BIN|g" "$APP_HOME/data/airmedia-share.desktop.in" > "$DESKTOP"
update-desktop-database "$(dirname "$DESKTOP")" 2>/dev/null || true

# ---- settings: carry over the first version's preferences, add site TVs
PYTHONPATH="$APP_HOME/lib" "$APP_HOME/venv/bin/python" - "$HERE/site.json" <<'PY'
import os, sys
from airmedia_share.settings import Settings, merge_site_file, migrate_from_share_to_office_tv
s = Settings()
fresh = not os.path.exists(s.path)
if fresh and migrate_from_share_to_office_tv(s):
    print("==> Carried over sound settings from Share to Office TV")
site = sys.argv[1]
if os.path.exists(site):
    n = merge_site_file(s, site)
    if n:
        print(f"==> Added {n} TV(s) from site.json")
s.save()
if not s["tvs"]:
    print("==> No TVs saved yet. The app asks for one when it first opens. To bring your")
    print("    TVs from another computer, copy its ~/.config/airmedia-share/settings.json")
    print("    to the same place here (or next to install.sh as site.json) and rerun.")
PY

# ---- retire the first version (Share to Office TV), if present
old_found=0
for old in "$HOME/.local/bin/share-to-office-tv" \
           "$DATA/applications/share-to-office-tv.desktop" \
           "$DATA/share-to-office-tv" \
           "$HOME/.cache/share-to-office-tv" \
           "$HOME/.config/share-to-office-tv"; do
    if [[ -e "$old" ]]; then
        old_found=1
        rm -rf "$old"
    fi
done
((old_found)) && say "Removed the old Share to Office TV install (settings were carried over)"
update-desktop-database "$(dirname "$DESKTOP")" 2>/dev/null || true

say "Installed. Self-check:"
"$BIN" --check || true
echo
echo "Open “AirMedia Share” from the app menu, or run: airmedia-share"
