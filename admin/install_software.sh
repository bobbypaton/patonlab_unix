#!/bin/bash
#
# Install the group's standard computational chemistry binaries on a workstation:
# ORCA, xtb, CREST, g-xTB and the OpenMPI that parallel ORCA runs on, at the paths the
# example profile, qsub and autotest expect.
#
# Each package goes into a versioned directory (e.g. /usr/local/xtb-6.7.1) and the
# standard name (/usr/local/xtb) becomes a symlink to it. A previous installation is
# renamed to <name>.pre-<date>, never deleted, so it can be restored.
#
# Usage:
#   sudo admin/install_software.sh --xtb --crest --gxtb
#   sudo admin/install_software.sh --openmpi
#   sudo admin/install_software.sh --orca ~/orca_6_1_1_linux_x86-64_shared_openmpi418.tar.xz
#   admin/install_software.sh --all --orca FILE --dry-run      # show what would happen
#
# ORCA can't be downloaded automatically (it needs a FACCTs login): download the Linux
# x86-64 shared OpenMPI build yourself and pass the tarball with --orca.
#
# Afterwards, as a normal user, run: autotest
#
# Author: Paton Research Group (patonlab@colostate.edu)

set -euo pipefail

# ---- Pinned versions (update the URL and SHA-256 together) -------------------------

XTB_VERSION=6.7.1
XTB_URL=https://github.com/grimme-lab/xtb/releases/download/v6.7.1/xtb-6.7.1-linux-x86_64.tar.xz
XTB_SHA256=62a8d18778286e815292ee53d76ce447daf460a4dea3782c0f25cbac7019b5df

CREST_VERSION=3.0.2
CREST_GNU_URL=https://github.com/crest-lab/crest/releases/download/v3.0.2/crest-gnu-12-ubuntu-latest.tar.xz
CREST_GNU_SHA256=8e5bd18b06f99741ebd7bb71b3a996295f391b2f076aaeab739740f709e9554d
CREST_INTEL_URL=https://github.com/crest-lab/crest/releases/download/v3.0.2/crest-intel-2023.1.0-ubuntu-latest.tar.xz
CREST_INTEL_SHA256=dab8331ac75c27d7876fe93cbdc5159e5bf4c01bbdf8885bcd3579a2959ba26b

GXTB_VERSION=2.0.1
GXTB_URL=https://github.com/grimme-lab/g-xtb/releases/download/v2.0.1/xtb-6.7.1-gxtb-140526-linux-x86_64.tar.xz
GXTB_SHA256=cdfb81164f8d3300fc451dbbf2414528b533e71f7a30ec824b564cd30d6d9e5c

# Built from source: the version FACCTs builds ORCA 6.1 against
OPENMPI_VERSION=4.1.8
OPENMPI_URL=https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-4.1.8.tar.gz
OPENMPI_SHA256=fb41086bbed9300baa2f3d7572491facfe5257412fa524ec5a396aa9101d5c62

# ---- Options ------------------------------------------------------------------------

PREFIX=/usr/local
MPI_BASE=/opt   # OpenMPI goes in /opt, like the existing /opt/openmpi-4.1.6 builds
PREFIX_GIVEN=0
DRY_RUN=0
FORCE=0
DO_XTB=0
DO_CREST=0
DO_GXTB=0
DO_OPENMPI=0
ORCA_TARBALL=""
CREST_BUILD=gnu
STAMP=$(date +%Y%m%d)
ROLLBACK=()   # undo commands, printed at the end

usage() {
    sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
    cat <<EOF
Options:
  --xtb                 xtb ${XTB_VERSION}            -> ${PREFIX}/xtb
  --crest               CREST ${CREST_VERSION}          -> ${PREFIX}/crest (also ${PREFIX}/xtb/crest)
  --gxtb                g-xTB ${GXTB_VERSION}          -> ${PREFIX}/g-xtb, run as xtb-gxtb
  --openmpi             OpenMPI ${OPENMPI_VERSION}, built from source -> ${MPI_BASE}/openmpi
                        (needs gcc and make; takes a few minutes)
  --orca FILE           ORCA from a FACCTs tarball -> ${PREFIX}/ORCA6
  --all                 --xtb --crest --gxtb --openmpi (add --orca FILE for ORCA)
  --crest-build NAME    gnu (default) or intel
  --prefix DIR          install everything under DIR instead of ${PREFIX} and ${MPI_BASE}
  --dry-run             print what would be done, change nothing
  --force               switch even if the old version is in use by running jobs
  -h, --help            show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --xtb) DO_XTB=1 ;;
        --crest) DO_CREST=1 ;;
        --gxtb) DO_GXTB=1 ;;
        --openmpi) DO_OPENMPI=1 ;;
        --all) DO_XTB=1; DO_CREST=1; DO_GXTB=1; DO_OPENMPI=1 ;;
        --orca) shift; ORCA_TARBALL=${1:?--orca needs a tarball path} ;;
        --crest-build) shift; CREST_BUILD=${1:?--crest-build needs gnu or intel} ;;
        --prefix) shift; PREFIX=${1:?--prefix needs a directory}; PREFIX_GIVEN=1 ;;
        --dry-run|-n) DRY_RUN=1 ;;
        --force) FORCE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if [ $DO_XTB -eq 0 ] && [ $DO_CREST -eq 0 ] && [ $DO_GXTB -eq 0 ] && [ $DO_OPENMPI -eq 0 ] && [ -z "$ORCA_TARBALL" ]; then
    usage >&2
    exit 2
fi
[ $PREFIX_GIVEN -eq 1 ] && MPI_BASE=$PREFIX

case "$CREST_BUILD" in
    gnu) CREST_URL=$CREST_GNU_URL; CREST_SHA256=$CREST_GNU_SHA256 ;;
    intel) CREST_URL=$CREST_INTEL_URL; CREST_SHA256=$CREST_INTEL_SHA256 ;;
    *) echo "--crest-build must be gnu or intel" >&2; exit 2 ;;
esac

# ---- Helpers -------------------------------------------------------------------------

say() { echo "==> $*"; }
run() {
    # Print a command; run it unless --dry-run
    echo "    $*"
    [ $DRY_RUN -eq 1 ] || "$@"
}
die() { echo "ERROR: $*" >&2; exit 1; }

IS_ROOT=0; [ "$(id -u)" -eq 0 ] && IS_ROOT=1
if [ $DRY_RUN -eq 0 ] && [ $IS_ROOT -eq 0 ] && [ "$PREFIX" = /usr/local ]; then
    die "run with sudo (or use --dry-run)"
fi
for cmd in curl tar sha256sum xz; do
    command -v $cmd >/dev/null || die "$cmd is required"
done
[ -d "$PREFIX" ] || die "$PREFIX does not exist"
if [ $DO_OPENMPI -eq 1 ]; then
    [ -d "$MPI_BASE" ] || die "$MPI_BASE does not exist"
    for cmd in gcc make gzip; do
        command -v $cmd >/dev/null || die "$cmd is required to build OpenMPI (Ubuntu: apt install build-essential)"
    done
fi
if [ -n "$ORCA_TARBALL" ]; then
    [ -f "$ORCA_TARBALL" ] || die "ORCA tarball not found: $ORCA_TARBALL"
    ORCA_TARBALL=$(cd "$(dirname "$ORCA_TARBALL")" && pwd)/$(basename "$ORCA_TARBALL")
fi

WORK=$(mktemp -d "${TMPDIR:-/var/tmp}/patonlab_install.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# Download a URL and check its SHA-256
fetch() {
    local url=$1 sha=$2 out=$WORK/$(basename "$1")
    say "Downloading $(basename "$url")"
    curl -fsSL --retry 3 -o "$out" "$url" || die "download failed: $url"
    echo "$sha  $out" | sha256sum -c --quiet - || die "checksum mismatch for $(basename "$url")"
    FETCHED=$out
}

# Refuse to switch a package while processes run programs from it. Checks each
# process's executable (needs root to see other users' processes) and command line,
# against the given paths and wherever they really point.
check_not_in_use() {
    local name=$1; shift
    local paths=() p real pid exe args hits=""
    for p in "$@"; do
        paths+=("$p")
        real=$(readlink -f "$p" 2>/dev/null || true)
        [ -n "$real" ] && [ "$real" != "$p" ] && paths+=("$real")
    done
    for pid in /proc/[0-9]*; do
        exe=$(readlink "$pid/exe" 2>/dev/null || true)
        args=$(tr '\0' ' ' < "$pid/cmdline" 2>/dev/null || true)
        case "$args" in *install_software*) continue ;; esac
        for p in "${paths[@]}"; do
            case "$exe $args" in
                *"$p"*) hits="$hits    ${pid#/proc/} $(stat -c %U "$pid" 2>/dev/null) ${args:0:120}"$'\n'; break ;;
            esac
        done
    done
    if [ -n "$hits" ]; then
        printf '%s' "$hits"
        if [ $FORCE -eq 1 ]; then
            echo "    (--force: switching $name anyway; running jobs keep the files they already opened)"
        else
            die "$name is in use by the processes above; wait for them to finish or use --force"
        fi
    fi
}

# Move extracted directory $1 to $BASE/$2 and point the symlink $BASE/$3 at it.
# BASE is $4, default $PREFIX.
install_versioned() {
    local base=${4:-$PREFIX}
    local src=$1 target=$base/$2 link=$base/$3
    if [ -e "$target" ]; then
        echo "    $target already exists; reusing it"
    else
        run mv "$src" "$target"
        [ $IS_ROOT -eq 1 ] && run chown -R root:root "$target"
        run chmod -R u+rwX,go+rX,go-w "$target"
    fi
    if [ -L "$link" ]; then
        ROLLBACK+=("sudo ln -sfn $(readlink "$link") $link")
    elif [ -e "$link" ]; then
        [ -e "$link.pre-$STAMP" ] && die "$link.pre-$STAMP already exists; move it aside first"
        run mv "$link" "$link.pre-$STAMP"
        ROLLBACK+=("sudo rm $link && sudo mv $link.pre-$STAMP $link")
    else
        ROLLBACK+=("sudo rm $link")
    fi
    run ln -s "$target" "$link.new.$$"
    run mv -T "$link.new.$$" "$link"
    echo "    $link -> $target"
}

# ---- xtb -----------------------------------------------------------------------------

if [ $DO_XTB -eq 1 ]; then
    say "xtb $XTB_VERSION"
    check_not_in_use xtb "$PREFIX/xtb/" "$PREFIX/xtb-"
    fetch "$XTB_URL" "$XTB_SHA256"
    tar -C "$WORK" -xJf "$FETCHED"
    # Keep $XTBHOME/crest working (old PATH settings, qsub's fallback). If CREST isn't
    # being installed and only exists inside the old xtb directory, carry it over.
    if [ $DO_CREST -eq 0 ] && [ ! -e "$PREFIX/crest/crest" ] && [ -f "$PREFIX/xtb/crest" ] && [ ! -L "$PREFIX/xtb/crest" ]; then
        cp -p "$PREFIX/xtb/crest" "$WORK/xtb-dist/crest"
    else
        ln -s "$PREFIX/crest/crest" "$WORK/xtb-dist/crest"
    fi
    install_versioned "$WORK/xtb-dist" "xtb-$XTB_VERSION" xtb
fi

# ---- CREST ---------------------------------------------------------------------------

if [ $DO_CREST -eq 1 ]; then
    say "CREST $CREST_VERSION ($CREST_BUILD build)"
    check_not_in_use CREST "$PREFIX/crest" "$PREFIX/xtb/crest"
    fetch "$CREST_URL" "$CREST_SHA256"
    mkdir -p "$WORK/crest-unpack"
    tar -C "$WORK/crest-unpack" -xJf "$FETCHED"
    install_versioned "$WORK/crest-unpack/crest" "crest-$CREST_VERSION" crest
    # An older real crest binary inside a non-symlinked xtb directory would shadow this one
    if [ -f "$PREFIX/xtb/crest" ] && [ ! -L "$PREFIX/xtb/crest" ]; then
        run mv "$PREFIX/xtb/crest" "$PREFIX/xtb/crest.pre-$STAMP"
        run ln -s "$PREFIX/crest/crest" "$PREFIX/xtb/crest"
        ROLLBACK+=("sudo rm $PREFIX/xtb/crest && sudo mv $PREFIX/xtb/crest.pre-$STAMP $PREFIX/xtb/crest")
    fi
fi

# ---- g-xTB ---------------------------------------------------------------------------

if [ $DO_GXTB -eq 1 ]; then
    say "g-xTB $GXTB_VERSION"
    check_not_in_use g-xTB "$PREFIX/g-xtb/" "$PREFIX/g-xtb-"
    fetch "$GXTB_URL" "$GXTB_SHA256"
    tar -C "$WORK" -xJf "$FETCHED"
    # The g-xTB binary is a modified xtb also called "xtb"; expose it only as xtb-gxtb
    # so it never shadows the regular xtb (the older standalone "gxtb" is left alone).
    ln -s bin/xtb "$WORK/xtb-6.7.1/xtb-gxtb"
    install_versioned "$WORK/xtb-6.7.1" "g-xtb-$GXTB_VERSION" g-xtb
fi

# ---- OpenMPI -------------------------------------------------------------------------

if [ $DO_OPENMPI -eq 1 ]; then
    say "OpenMPI $OPENMPI_VERSION"
    check_not_in_use OpenMPI "$MPI_BASE/openmpi/"
    OMPI_TARGET=$MPI_BASE/openmpi-$OPENMPI_VERSION
    OMPI_STAGE=$WORK/ompi-stage
    if [ ! -e "$OMPI_TARGET" ]; then
        fetch "$OPENMPI_URL" "$OPENMPI_SHA256"
        # Configured for its final path, installed into a staging copy, then moved
        # into place by install_versioned. Fortran bindings aren't needed for ORCA.
        # Half the cores, to leave room for running jobs.
        JOBS=$(( ($(nproc) + 1) / 2 ))
        BUILD_LOG=$WORK/openmpi-build.log
        echo "    ./configure --prefix=$OMPI_TARGET --disable-mpi-fortran"
        echo "    make -j$JOBS && make install DESTDIR=$OMPI_STAGE   (log: $BUILD_LOG)"
        if [ $DRY_RUN -eq 0 ]; then
            say "Building OpenMPI (a few minutes)"
            tar -C "$WORK" -xzf "$FETCHED"
            if ! ( cd "$WORK/openmpi-$OPENMPI_VERSION" &&
                   ./configure --prefix="$OMPI_TARGET" --disable-mpi-fortran &&
                   make -j"$JOBS" &&
                   make install DESTDIR="$OMPI_STAGE" ) > "$BUILD_LOG" 2>&1; then
                tail -25 "$BUILD_LOG" >&2
                cp "$BUILD_LOG" "/var/tmp/openmpi-$OPENMPI_VERSION-build.log"
                die "OpenMPI build failed; full log in /var/tmp/openmpi-$OPENMPI_VERSION-build.log"
            fi
        fi
    fi
    install_versioned "$OMPI_STAGE$OMPI_TARGET" "openmpi-$OPENMPI_VERSION" openmpi "$MPI_BASE"
fi

# ---- ORCA ----------------------------------------------------------------------------

if [ -n "$ORCA_TARBALL" ]; then
    say "ORCA from $(basename "$ORCA_TARBALL")"
    check_not_in_use ORCA "$PREFIX/ORCA6/" "$PREFIX/orca_"
    mkdir -p "$WORK/orca-unpack"
    tar -C "$WORK/orca-unpack" -xf "$ORCA_TARBALL"
    ORCA_BIN=$(find "$WORK/orca-unpack" -maxdepth 2 -type f -name orca | head -1)
    [ -n "$ORCA_BIN" ] || die "no orca executable in $ORCA_TARBALL"
    head -c 4 "$ORCA_BIN" | grep -q ELF || die "$ORCA_BIN is not an ELF binary"
    ORCA_DIR=$(dirname "$ORCA_BIN")
    ORCA_VERSION=$(basename "$ORCA_DIR" | grep -oE '[0-9]+_[0-9]+_[0-9]+' | head -1 | tr _ .)
    [ -n "$ORCA_VERSION" ] || ORCA_VERSION=$(grep -aoE 'Program Version [0-9]+\.[0-9]+\.[0-9]+' "$ORCA_BIN" | head -1 | awk '{print $3}')
    [ -n "$ORCA_VERSION" ] || die "could not work out the ORCA version"
    install_versioned "$ORCA_DIR" "orca_$(echo "$ORCA_VERSION" | tr . _)" ORCA6
fi

# ---- Summary -------------------------------------------------------------------------

if [ $DRY_RUN -eq 1 ]; then
    say "Dry run: nothing was changed"
    exit 0
fi
say "Installed versions"
[ $DO_XTB -eq 1 ] && echo "    xtb:   $("$PREFIX/xtb/bin/xtb" --version 2>&1 | grep -m1 -oE 'version [0-9.]+')"
[ $DO_CREST -eq 1 ] && echo "    CREST: $("$PREFIX/crest/crest" --version 2>&1 | grep -m1 -oE 'Version [0-9.a-z]+')"
[ $DO_GXTB -eq 1 ] && echo "    g-xTB: $GXTB_VERSION (xtb $("$PREFIX/g-xtb/xtb-gxtb" --version 2>&1 | grep -m1 -oE 'version [0-9.]+' | cut -d' ' -f2)), run as: xtb-gxtb mol.xyz --gxtb"
[ $DO_OPENMPI -eq 1 ] && echo "    OpenMPI: $("$MPI_BASE/openmpi/bin/mpirun" --version 2>&1 | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+') ($MPI_BASE/openmpi -> $(readlink "$MPI_BASE/openmpi"))"
[ -n "$ORCA_TARBALL" ] && echo "    ORCA:  $ORCA_VERSION ($PREFIX/ORCA6 -> $(readlink "$PREFIX/ORCA6"))"
echo
echo "Previous installations were kept. To undo:"
for cmd in ${ROLLBACK[@]+"${ROLLBACK[@]}"}; do echo "    $cmd"; done
echo "Now, as a normal user, run: autotest"
