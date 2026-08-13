#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# claude-config setup -- macOS (Homebrew) and Debian/Ubuntu Linux (apt).
#
# Installs the CLI tools the tracked slash commands assume:
#
#   gh      GitHub CLI      -- GitHub Issues and PRs on personal projects
#   bb      Bitbucket CLI   -- PR create/merge on Results Direct repos
#   sqlcmd  SQL Server CLI  -- database work
#
# Detects what is already present, installs only what is missing, prints a
# summary, and exits non-zero if anything is still missing. Absence is never
# smoothed into a pass -- that is the convention across this repo.
#
# Idempotent: running it twice is safe and boring.
#
#   ./setup.sh              install what is missing
#   ./setup.sh --check      report status only, install nothing
#   ./setup.sh --dry-run    print the commands it would run
#
# The Windows equivalent is setup.ps1 (winget).
#
# NOTE ON HONESTY: package names on macOS/Linux are probed at runtime
# (`brew info` / `apt-cache policy`) rather than assumed. Where a package
# cannot be resolved, the script prints the vendor's documented manual step and
# marks the tool FAILED. It never guesses at a formula name -- installing the
# wrong `bb` is worse than telling you to install it by hand (see the decoy
# warning in the bb section below).
# -----------------------------------------------------------------------------

set -uo pipefail

MODE=install # install | check | dry-run

while [ $# -gt 0 ]; do
    case "$1" in
        --check)   MODE=check ;;
        --dry-run) MODE=dry-run ;;
        -h|--help)
            sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "setup.sh: unknown argument '$1' (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

# -- Output helpers -----------------------------------------------------------

if [ -t 1 ]; then
    C_RESET=$'\033[0m'; C_HEAD=$'\033[36m'; C_OK=$'\033[32m'
    C_BAD=$'\033[31m';  C_WARN=$'\033[33m'
else
    C_RESET=''; C_HEAD=''; C_OK=''; C_BAD=''; C_WARN=''
fi

head_() { printf '\n%s%s%s\n' "$C_HEAD" "$1" "$C_RESET"; }
warn_() { printf '%s%s%s\n' "$C_WARN" "$1" "$C_RESET"; }
info_() { printf '%s\n' "$1"; }

# -- Result accumulation (indexed arrays only -- macOS ships bash 3.2, which
#    has no associative arrays) ---------------------------------------------
R_NAMES=(); R_STATUS=(); R_VERSION=(); R_DETAIL=()

record() { R_NAMES+=("$1"); R_STATUS+=("$2"); R_VERSION+=("$3"); R_DETAIL+=("$4"); }

have() { command -v "$1" >/dev/null 2>&1; }

first_line() { awk 'NF {print; exit}'; }

tool_version() {
    case "$1" in
        sqlcmd)
            # Two different binaries answer to `sqlcmd` on Unix: the Go-based
            # go-sqlcmd (understands --version) and the ODBC mssql-tools sqlcmd
            # (rejects it; prints its banner under -?).
            local v
            v="$(sqlcmd --version 2>&1 | first_line)"
            if printf '%s' "$v" | grep -Eq '[0-9]+\.[0-9]+'; then
                printf '%s\n' "$v"
                return
            fi
            v="$(sqlcmd -? 2>&1 | grep -Eo 'Version[[:space:]]+[0-9][0-9.]*' | first_line)"
            if [ -n "$v" ]; then printf 'sqlcmd (ODBC) %s\n' "${v##* }"; else echo 'version unknown'; fi
            ;;
        *)
            local out
            out="$("$1" --version 2>&1 | first_line)"
            if [ -n "$out" ]; then printf '%s\n' "$out"; else echo 'version unknown'; fi
            ;;
    esac
}

# Run an install command, honouring --dry-run. Returns 0 if it ran and
# succeeded, 1 if it failed, 2 if it was only printed (dry run).
run_install() {
    if [ "$MODE" = dry-run ]; then
        info_ "  DRY RUN, would run: $*"
        return 2
    fi
    info_ "  running: $*"
    "$@"
}

# -- Platform detection -------------------------------------------------------

head_ 'claude-config setup (macOS / Debian-Ubuntu)'

PLATFORM=''
PKGMGR=''
OS_NAME="$(uname -s 2>/dev/null || echo unknown)"

case "$OS_NAME" in
    Darwin)
        PLATFORM='macos'
        PKGMGR='brew'
        info_ 'Platform: macOS -- package manager: Homebrew'
        ;;
    Linux)
        DISTRO_ID=''; DISTRO_LIKE=''; DISTRO_PRETTY='Linux'
        if [ -r /etc/os-release ]; then
            # shellcheck disable=SC1091
            . /etc/os-release
            DISTRO_ID="${ID:-}"
            DISTRO_LIKE="${ID_LIKE:-}"
            DISTRO_PRETTY="${PRETTY_NAME:-Linux}"
        fi
        case " $DISTRO_ID $DISTRO_LIKE " in
            *debian*|*ubuntu*)
                PLATFORM='linux'
                PKGMGR='apt'
                info_ "Platform: $DISTRO_PRETTY -- package manager: apt"
                ;;
            *)
                PLATFORM='linux-unsupported'
                info_ "Platform: $DISTRO_PRETTY (id='$DISTRO_ID' id_like='$DISTRO_LIKE')"
                ;;
        esac
        ;;
    *)
        PLATFORM='unsupported'
        info_ "Platform: $OS_NAME"
        ;;
esac

if [ "$PLATFORM" = 'linux-unsupported' ] || [ "$PLATFORM" = 'unsupported' ]; then
    warn_ 'Unsupported platform. This script covers macOS (Homebrew) and'
    warn_ 'Debian/Ubuntu (apt) only; it deliberately does not reach for another'
    warn_ 'package manager it has not been tested against.'
    info_ ''
    info_ 'Install these three by hand:'
    info_ '  gh      https://cli.github.com/'
    info_ '  bb      https://github.com/gildas/bitbucket-cli/releases'
    info_ '  sqlcmd  https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-utility'
    exit 1
fi

case "$MODE" in
    check)   info_ 'Mode: --check -- reporting only, nothing will be installed.' ;;
    dry-run) info_ 'Mode: --dry-run -- printing commands only, nothing will be installed.' ;;
esac

# -- Elevation: say what is needed up front, not halfway through --------------

SUDO=''
if [ "$MODE" = install ]; then
    if [ "$PKGMGR" = apt ]; then
        if [ "$(id -u)" -eq 0 ]; then
            info_ 'Elevation: running as root; apt-get will be called directly.'
        elif have sudo; then
            warn_ 'Elevation: apt-get needs root. sudo will be used and may prompt for'
            warn_ 'your password. Nothing outside apt-get runs elevated.'
            SUDO='sudo'
        else
            warn_ 'apt-get needs root but neither root nor sudo is available.'
            warn_ 'Re-run as root, or install sudo first. Nothing was changed.'
            exit 1
        fi
    elif [ "$PKGMGR" = brew ] && [ "$(id -u)" -eq 0 ]; then
        warn_ 'Refusing to run as root: Homebrew must not be used under sudo -- it'
        warn_ 'will refuse or leave root-owned files in the prefix. Re-run as your'
        warn_ 'normal user. Nothing was changed.'
        exit 1
    fi
fi

# -- Package-manager availability and metadata probes ------------------------

PKGMGR_OK=1
if ! have "$PKGMGR"; then
    PKGMGR_OK=0
    warn_ "$PKGMGR is not installed."
    if [ "$PKGMGR" = brew ]; then
        warn_ '  Install Homebrew first: https://brew.sh'
    else
        warn_ '  This does not look like a working apt system.'
    fi
fi

# Refresh apt lists once, so that candidate probes below mean something. Skipped
# in check/dry-run mode because it mutates system state (and needs sudo).
if [ "$MODE" = install ] && [ "$PKGMGR" = apt ] && [ "$PKGMGR_OK" -eq 1 ]; then
    info_ ''
    info_ 'Refreshing apt package lists...'
    if ! $SUDO apt-get update -qq; then
        warn_ 'apt-get update failed; candidate lookups below may be stale.'
    fi
fi
if [ "$MODE" != install ] && [ "$PKGMGR" = apt ]; then
    info_ 'Note: apt lists are not refreshed in check/dry-run mode, so a "no candidate"'
    info_ '      result here may just mean `apt-get update` has not been run recently.'
fi

# Does Homebrew know this formula? (`brew info` is metadata only, installs nothing.)
brew_has() {
    [ "$PKGMGR_OK" -eq 1 ] || return 1
    brew info --formula "$1" >/dev/null 2>&1
}

# Does apt have an installable candidate for this package?
apt_has() {
    [ "$PKGMGR_OK" -eq 1 ] || return 1
    local cand
    cand="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    [ -n "$cand" ] && [ "$cand" != '(none)' ]
}

apt_install() {
    run_install $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

# Re-detect after an install: bash caches command lookups, and a fresh binary
# may have landed in a directory that was empty when the shell started.
redetect() { hash -r 2>/dev/null || true; have "$1"; }

# Shared post-install verification. $1 = tool name.
finish_install() {
    local name="$1" rc="$2"
    case "$rc" in
        2)  record "$name" 'MISSING' '-' 'not installed (dry run)'; return ;;
        0)  ;;
        *)  record "$name" 'FAILED' '-' "install command exited $rc"; return ;;
    esac
    if redetect "$name"; then
        local v; v="$(tool_version "$name")"
        info_ "  installed: $(command -v "$name")"
        info_ "  version: $v"
        record "$name" 'installed' "$v" "$(command -v "$name")"
    else
        warn_ "  the package manager reported success but '$name' is not on PATH."
        record "$name" 'INSTALLED (UNVERIFIED)' '-' \
            "installed but not on PATH -- open a new shell and re-run with --check"
    fi
}

# -----------------------------------------------------------------------------
# gh -- GitHub CLI
# -----------------------------------------------------------------------------
do_gh() {
    head_ 'gh -- GitHub CLI'
    if have gh; then
        local v; v="$(tool_version gh)"
        info_ "  already present: $(command -v gh)"
        info_ "  version: $v"
        record gh 'already present' "$v" "$(command -v gh)"
        return
    fi
    info_ '  not found on PATH'

    if [ "$PKGMGR" = brew ]; then
        if [ "$MODE" = check ]; then
            record gh 'MISSING' '-' 'install with: brew install gh'
            info_ '  would install with: brew install gh'
            return
        fi
        if ! brew_has gh; then
            warn_ '  Homebrew does not resolve a formula named gh.'
            record gh 'FAILED' '-' 'no brew formula resolved -- see https://cli.github.com/'
            return
        fi
        run_install brew install gh; finish_install gh $?
        return
    fi

    # apt. GitHub's own repository (cli.github.com) carries newer builds than the
    # distro archive, but adding it means importing a keyring and writing to
    # /etc/apt/sources.list.d -- more third-party system surgery than this script
    # should do behind your back. So: use the distro candidate if there is one and
    # point at GitHub's documented instructions otherwise (or if you want current).
    if [ "$MODE" = check ]; then
        if apt_has gh; then
            info_ '  would install with: apt-get install -y gh'
            record gh 'MISSING' '-' 'install with: apt-get install -y gh'
        else
            info_ '  no apt candidate for gh'
            record gh 'MISSING' '-' \
                'no apt candidate -- add GitHub'\''s repo per https://github.com/cli/cli/blob/trunk/docs/install_linux.md'
        fi
        return
    fi
    if apt_has gh; then
        info_ '  (distro package; for the newest gh, add GitHub'\''s apt repo per'
        info_ '   https://github.com/cli/cli/blob/trunk/docs/install_linux.md)'
        apt_install gh; finish_install gh $?
    else
        warn_ '  No apt candidate for gh.'
        warn_ '  Manual step -- add GitHub'\''s official apt repository following'
        warn_ '  https://github.com/cli/cli/blob/trunk/docs/install_linux.md then re-run.'
        record gh 'FAILED' '-' \
            'no apt candidate -- add GitHub'\''s repo per https://github.com/cli/cli/blob/trunk/docs/install_linux.md'
    fi
}

# -----------------------------------------------------------------------------
# bb -- Bitbucket CLI (Gildas Cherruel: github.com/gildas/bitbucket-cli)
#
# DELIBERATELY NOT AUTO-INSTALLED ON UNIX.
#
# There are at least two unrelated CLIs called "Bitbucket CLI" that both install
# a `bb` command with completely different subcommands -- on Windows, winget
# offers Gildas.Bitbucket-CLI (ours) and dlbroadfoot.bb (not ours, higher version
# number, a trap). The wrong `bb` lands on PATH and silently breaks the PR
# workflow instead of failing loudly.
#
# No Homebrew formula or apt package has been verified as being Gildas' tool, so
# this script only PROBES and reports what it found, and tells you to install the
# release binary by hand. If you confirm a real formula/package exists, add it
# here -- with a comment recording how you verified which `bb` it is.
# -----------------------------------------------------------------------------
BB_RELEASES='https://github.com/gildas/bitbucket-cli/releases'

do_bb() {
    head_ 'bb -- Bitbucket CLI (Gildas)'
    if have bb; then
        local v; v="$(tool_version bb)"
        info_ "  already present: $(command -v bb)"
        info_ "  version: $v"
        if printf '%s' "$v" | grep -qi 'bb version'; then
            record bb 'already present' "$v" "$(command -v bb)"
        else
            # Something answers to `bb`, but it does not look like Gildas' CLI.
            warn_ '  This does not look like Gildas'\'' bb (expected "bb version X.Y.Z").'
            warn_ "  Check which tool it is; our commands need $BB_RELEASES"
            record bb 'PRESENT (WRONG TOOL?)' "$v" \
                "unexpected version banner -- verify this is $BB_RELEASES"
        fi
        return
    fi
    info_ '  not found on PATH'

    # Probe only. Report findings; never install on a guess.
    #
    # Note the names we deliberately DO NOT probe: a bare `bb` is a false positive
    # on both platforms -- Debian/Ubuntu ship a package literally called `bb`,
    # which is the AA-lib ASCII-art demo, nothing to do with Bitbucket. Verified
    # on Ubuntu 24.04, where `apt-cache policy bb` reports a candidate.
    local found=''
    if [ "$PKGMGR" = brew ]; then
        for f in bitbucket-cli gildas/tap/bitbucket-cli; do
            if brew_has "$f"; then found="$found brew:$f"; fi
        done
    else
        for p in bitbucket-cli; do
            if apt_has "$p"; then found="$found apt:$p"; fi
        done
    fi

    if [ -n "$found" ]; then
        warn_ "  Probe found possible package(s):$found"
        warn_ '  NOT installing automatically -- more than one unrelated tool ships a'
        warn_ '  `bb` command, and the wrong one breaks the PR workflow silently.'
        warn_ "  Verify the candidate is $BB_RELEASES before installing it."
        record bb 'MANUAL' '-' "candidate(s) found but unverified:$found -- see $BB_RELEASES"
    else
        warn_ '  No package found for this platform (expected -- it ships as a Go binary).'
        warn_ "  Manual step: download the release for your OS/arch from"
        warn_ "    $BB_RELEASES"
        warn_ '  unpack it, chmod +x the `bb` binary, and put it on your PATH'
        warn_ '  (e.g. /usr/local/bin/bb). Then re-run with --check.'
        record bb 'MANUAL' '-' "install the release binary by hand: $BB_RELEASES"
    fi
}

# -----------------------------------------------------------------------------
# sqlcmd -- SQL Server command-line client
#
# Microsoft ships two: the modern Go-based go-sqlcmd, and the older ODBC one in
# mssql-tools18. Either satisfies this repo's usage. Availability is probed
# before anything is invoked; if neither resolves, the documented Microsoft
# install page is printed and the tool is marked FAILED rather than pretended.
# -----------------------------------------------------------------------------
SQLCMD_DOCS='https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-utility'
SQLCMD_LINUX_DOCS='https://learn.microsoft.com/sql/linux/sql-server-linux-setup-tools'

do_sqlcmd() {
    head_ 'sqlcmd -- SQL Server command-line client'
    if have sqlcmd; then
        local v; v="$(tool_version sqlcmd)"
        info_ "  already present: $(command -v sqlcmd)"
        info_ "  version: $v"
        record sqlcmd 'already present' "$v" "$(command -v sqlcmd)"
        return
    fi
    info_ '  not found on PATH'

    if [ "$PKGMGR" = brew ]; then
        if brew_has sqlcmd; then
            if [ "$MODE" = check ]; then
                info_ '  would install with: brew install sqlcmd'
                record sqlcmd 'MISSING' '-' 'install with: brew install sqlcmd'
                return
            fi
            run_install brew install sqlcmd; finish_install sqlcmd $?
        else
            warn_ '  Homebrew does not resolve a formula named sqlcmd on this machine.'
            warn_ "  Manual step: follow $SQLCMD_DOCS"
            warn_ '  (go-sqlcmd releases: https://github.com/microsoft/go-sqlcmd/releases)'
            record sqlcmd 'FAILED' '-' "no brew formula resolved -- see $SQLCMD_DOCS"
        fi
        return
    fi

    # apt: both candidates live in Microsoft's package repository, so on a box
    # that has not added it neither will resolve -- which is exactly why we probe.
    local pkg=''
    if apt_has sqlcmd; then pkg='sqlcmd'
    elif apt_has mssql-tools18; then pkg='mssql-tools18'
    fi

    if [ -z "$pkg" ]; then
        warn_ '  No apt candidate for sqlcmd or mssql-tools18.'
        warn_ '  Manual step: add Microsoft'\''s package repository, then re-run --'
        warn_ "    $SQLCMD_LINUX_DOCS"
        warn_ "  Reference: $SQLCMD_DOCS"
        record sqlcmd 'FAILED' '-' "no apt candidate -- add Microsoft's repo per $SQLCMD_LINUX_DOCS"
        return
    fi

    if [ "$MODE" = check ]; then
        info_ "  would install with: apt-get install -y $pkg"
        record sqlcmd 'MISSING' '-' "install with: apt-get install -y $pkg"
        return
    fi

    if [ "$pkg" = 'mssql-tools18' ]; then
        # mssql-tools18 requires EULA acceptance and does not put sqlcmd on PATH.
        info_ '  mssql-tools18 requires accepting the Microsoft EULA (ACCEPT_EULA=Y).'
        if [ "$MODE" = dry-run ]; then
            info_ '  DRY RUN, would run: apt-get install -y mssql-tools18 unixodbc-dev (with ACCEPT_EULA=Y)'
            record sqlcmd 'MISSING' '-' 'not installed (dry run)'
            return
        fi
        run_install $SUDO env DEBIAN_FRONTEND=noninteractive ACCEPT_EULA=Y \
            apt-get install -y mssql-tools18 unixodbc-dev
        local rc=$?
        if [ $rc -eq 0 ] && ! redetect sqlcmd; then
            warn_ '  Installed, but sqlcmd is not on PATH: mssql-tools18 puts it in'
            warn_ '  /opt/mssql-tools18/bin. Add that to PATH, then re-run with --check.'
            record sqlcmd 'INSTALLED (UNVERIFIED)' '-' \
                'add /opt/mssql-tools18/bin to PATH, then re-run --check'
            return
        fi
        finish_install sqlcmd $rc
        return
    fi

    apt_install sqlcmd; finish_install sqlcmd $?
}

# -- Run ----------------------------------------------------------------------

do_gh
do_bb
do_sqlcmd

# -- Summary ------------------------------------------------------------------

head_ 'Summary'
bad=0
bad_names=''
i=0
while [ "$i" -lt "${#R_NAMES[@]}" ]; do
    name="${R_NAMES[$i]}"; status="${R_STATUS[$i]}"
    version="${R_VERSION[$i]}"; detail="${R_DETAIL[$i]}"
    case "$status" in
        'already present'|'installed')
            printf '  %s%-8s %-22s %s%s\n' "$C_OK" "$name" "$status" "$version" "$C_RESET"
            ;;
        *)
            printf '  %s%-8s %-22s %s%s\n' "$C_BAD" "$name" "$status" "$version" "$C_RESET"
            printf '           %s\n' "$detail"
            bad=$((bad + 1))
            bad_names="$bad_names $name"
            ;;
    esac
    i=$((i + 1))
done

head_ 'Next steps for this repo'
info_ '  1. gh auth login                 -- authenticate the GitHub CLI'
info_ '  2. ~/.claude/credentials.json    -- bb reads its Bitbucket credentials from here'
info_ '     (the entry whose label starts with "Bitbucket API"). The repo deliberately does NOT'
info_ '     contain this file; recreate it by hand. See README.md.'

if [ "$bad" -gt 0 ]; then
    printf '\n'
    printf '%s%d tool(s) still missing, unverified, or needing a manual step:%s%s\n' \
        "$C_BAD" "$bad" "$bad_names" "$C_RESET"
    exit 1
fi

printf '\n%sAll three CLIs are present.%s\n' "$C_OK" "$C_RESET"
exit 0
