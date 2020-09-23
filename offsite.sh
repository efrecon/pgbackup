#!/usr/bin/env sh

if [ -t 1 ]; then
    INTERACTIVE=1
else
    INTERACTIVE=0
fi

# All (good?) defaults
PGBACKUP_VERBOSE=${PGBACKUP_VERBOSE:-0}
PGBACKUP_KEEP=${PGBACKUP_KEEP:-""}
PGBACKUP_DESTINATION=${PGBACKUP_DESTINATION:-"."}
PGBACKUP_COMPRESS=${PGBACKUP_COMPRESS:-0}
PGBACKUP_THEN=${PGBACKUP_THEN:-""}
PGBACKUP_PASSWORD=${PGBACKUP_PASSWORD:-""}
PGBACKUP_PASSWORD_FILE=${PGBACKUP_PASSWORD_FILE:-""}

# Dynamic vars
cmdname=$(basename "$(readlink -f "$0")")
appname=${cmdname%.*}

# Print usage on stderr and exit
usage() {
  exitcode="$1"
  cat << USAGE >&2

Description:
  $cmdname will compress the latest file matching a pattern, compress it,
  move it to a destination directory and rotate files in this directory
  to keep disk space under control. Compression via zip is preferred,
  otherwise gzip.

Usage:
  $cmdname [-option arg] pattern

  where all dash-led single options are as follows:
    -v              Be more verbose
    -d destination  Directory where to place (and rotate) compressed copies, default to current dir
    -k keep         Number of compressed copies to keep, defaults to empty, meaning all
    -c level        Compression level, defaults to 0, meaning no compression
    -w password     Password for compressed archive, only when zip available
    -W path         Same as -w, but read content of password from file instead
    -t command      Command to execute once done, path to copy will be passed as an argument
USAGE
  exit "$exitcode"
}

# Parse options
while [ $# -gt 0 ]; do
    case "$1" in
        -k | --keep)
            PGBACKUP_KEEP=$2; shift 2;;
        --keep=*)
            PGBACKUP_KEEP="${1#*=}"; shift 1;;

        -w | --password)
            PGBACKUP_PASSWORD=$2; shift 2;;
        --password=*)
            PGBACKUP_PASSWORD="${1#*=}"; shift 1;;

        -W | --password-file)
            PGBACKUP_PASSWORD_FILE=$2; shift 2;;
        --password-file=*)
            PGBACKUP_PASSWORD_FILE="${1#*=}"; shift 1;;

        -d | --dest | --destination)
            PGBACKUP_DESTINATION=$2; shift 2;;
        --dest=* | --destination=*)
            PGBACKUP_DESTINATION="${1#*=}"; shift 1;;

        -c | --compress | --level)
            PGBACKUP_COMPRESS=$2; shift 2;;
        --compress=* | --level=*)
            PGBACKUP_COMPRESS="${1#*=}"; shift 1;;

        -t | --then)
            PGBACKUP_THEN=$2; shift 2;;
        --then=*)
            PGBACKUP_THEN="${1#*=}"; shift 1;;

        -v | --verbose)
            PGBACKUP_VERBOSE=1; shift 1;;

        -\? | --help)
            usage 0;;
        --)
            shift; break;;
        -*)
            echo "Unknown option: $1 !" >&2 ; usage 1;;
        *)
            break;;
    esac
done

# Colourisation support for logging and output.
_colour() {
    if [ "$INTERACTIVE" = "1" ]; then
        # shellcheck disable=SC2086
        printf '\033[1;31;'${1}'m%b\033[0m' "$2"
    else
        printf -- "%b" "$2"
    fi
}
green() { _colour "32" "$1"; }
red() { _colour "40" "$1"; }
yellow() { _colour "33" "$1"; }
blue() { _colour "34" "$1"; }

# Conditional logging
log() {
    if [ "$PGBACKUP_VERBOSE" = "1" ]; then
        echo "[$(blue "$appname")] [$(yellow info)] [$(date +'%Y%m%d-%H%M%S')] $1" >&2
    fi
}

warn() {
    echo "[$(blue "$appname")] [$(red WARN)] [$(date +'%Y%m%d-%H%M%S')] $1" >&2
}

# Bail out when no sources specified
if [ "$#" -eq "0" ]; then
    warn "You need to specify sources to copy for offline backup"
    exit 1
fi

# Bail out when specifying the password in different places.
if [ -n "$PGBACKUP_PASSWORD_FILE" ] && [ -n "$PGBACKUP_PASSWORD" ]; then
    warn "You can only have a source for the password, choose one of --password or --password-file!"
    exit 1
fi

# Decide upon which compressor to use. Prefer zip to be able to encrypt. Do this
# only if we should compress. This arranges to set the variable COMPRESSOR in
# the only case when we should compress, and can compress.
ZEXT=
COMPRESSOR=
if [ "$PGBACKUP_COMPRESS" -gt "0" ]; then
    ZIP=$(command -v zip)
    if [ -n "$ZIP" ]; then
        ZEXT="zip"
        COMPRESSOR=$ZIP
    else
        GZIP=$(command -v gzip)
        if [ -n "$GZIP" ]; then
            ZEXT="gz"
            COMPRESSOR=$GZIP
        fi
    fi
    if [ -n "$COMPRESSOR" ]; then
        log "Will use $COMPRESSOR for compressing, extension: $ZEXT"
    else
        warn "No compression possible, could neither find zip, nor gzip binaries"
    fi
fi

# Read password from file if necessary.
if [ -n "$PGBACKUP_PASSWORD_FILE" ]; then
    PGBACKUP_PASSWORD=$(cat "$PGBACKUP_PASSWORD_FILE")
fi

# Create destination directory if it does not exist (including all leading
# directories in the path)
if [ ! -d "$PGBACKUP_DESTINATION" ]; then
    log "Creating destination directory $PGBACKUP_DESTINATION"
    mkdir -p "$PGBACKUP_DESTINATION"
fi

# Create temporary directory for storage of compressed and encrypted files.
TMPDIR=$(mktemp -d -t offline.XXXXXX)

# shellcheck disable=SC2012,SC2068
LATEST=$(ls -1 $@ | sort | tail -n 1)
if [ -n "$LATEST" ]; then
    if [ -n "$COMPRESSOR" ]; then
        ZTGT=${TMPDIR}/$(basename "$LATEST").${ZEXT}
        SRC=
        log "Compressing $LATEST to $ZTGT"
        case "$ZEXT" in
            gz)
                gzip -"$PGBACKUP_COMPRESS" -c "$LATEST" > "$ZTGT"
                SRC="$ZTGT"
                ;;
            zip)
                # ZIP in directory of latest file to have relative directories
                # stored in the ZIP file
                cwd=$(pwd)
                cd "$(dirname "${LATEST}")" || exit
                zip -"$PGBACKUP_COMPRESS" -P "$PGBACKUP_PASSWORD" "$ZTGT" "$(basename "$LATEST")"
                cd "${cwd}" || exit
                SRC="$ZTGT"
                ;;
        esac
    else
        SRC="$LATEST"
    fi

    if [ -n "$SRC" ]; then
        log "Copying ${SRC} to $PGBACKUP_DESTINATION"
        cp "$SRC" "$PGBACKUP_DESTINATION"
    fi
fi

if [ -n "$PGBACKUP_KEEP" ]; then
    # shellcheck disable=SC2046,SC2012
    while [ $(ls "$PGBACKUP_DESTINATION" -1 | wc -l) -gt "$PGBACKUP_KEEP" ]; do
        DELETE=$(ls "$PGBACKUP_DESTINATION" -1 | sort | head -n 1)
        log "Removing old copies $DELETE"
        rm -rf "${PGBACKUP_DESTINATION:?}/$DELETE"
    done
fi

# Cleanup temporary directory
rm -rf "$TMPDIR"

if [ -n "$PGBACKUP_THEN" ]; then
    log "Executing $PGBACKUP_THEN"
    if [ -f "${PGBACKUP_DESTINATION}/$(basename "${SRC}")" ]; then
        eval "$PGBACKUP_THEN" "${PGBACKUP_DESTINATION}/$(basename "${SRC}")"
    else
        eval "$PGBACKUP_THEN"
    fi
fi
