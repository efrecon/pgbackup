#!/bin/sh

# All (good?) defaults
VERBOSE=0
KEEP=""
DESTINATION="."
COMPRESS=0
THEN=""
PASSWORD=""

# Dynamic vars
cmdname=$(basename "${0}")

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
while getopts ":k:s:d:c:vt:w:W:" opt; do
    case $opt in
        k)
            KEEP="$OPTARG"
            ;;
        d)
            DESTINATION="$OPTARG"
            ;;
        c)
            COMPRESS="$OPTARG"
            ;;
        v)
            VERBOSE=1
            ;;
        t)
            THEN="$OPTARG"
            ;;
        w)
            PASSWORD="$OPTARG"
            ;;
        W)
            PASSWORD=$(cat "$OPTARG")
            ;;
        \?)
            echo "Invalid option: $opt" >& 2
            usage 1
            ;;
        :)
            echo "Option $opt requires an argument" >& 2
            usage 1
            ;;
    esac
done
shift $((OPTIND-1))

if [ $# -eq 0 ]; then
    echo "You need to specify sources to copy for offline backup" >& 2
    exit 1
fi

# Decide upon which compressor to use. Prefer zip to be able to encrypt
ZEXT=
COMPRESSOR=
ZIP=$(which zip)
if [ -n "${ZIP}" ]; then
    ZEXT="zip"
    COMPRESSOR=${ZIP}
else
    GZIP=$(which gzip)
    if [ -n "${GZIP}" ]; then
        ZEXT="gz"
        COMPRESSOR=${GZIP}
    fi
fi

# Conditional logging
log() {
    local txt=$1

    if [ "$VERBOSE" == "1" ]; then
        echo "$txt"
    fi
}

# Create destination directory if it does not exist (including all leading
# directories in the path)
if [ ! -d "${DESTINATION}" ]; then
    log "Creating destination directory ${DESTINATION}"
    mkdir -p "${DESTINATION}"
fi

# Create temporary directory for storage of compressed and encrypted files.
TMPDIR=$(mktemp -d -t offline.XXXXXX)

LATEST=$(ls $@ -1 | sort | tail -n 1)
if [ -n "$LATEST" ]; then
    if [ "$COMPRESS" -gt "0" -a -n "$COMPRESSOR" ]; then
        ZTGT=${TMPDIR}/$(basename $LATEST).${ZEXT}
        SRC=
        log "Compressing $LATEST to $ZTGT"
        case "$ZEXT" in
            gz)
                gzip -${COMPRESS} -c ${LATEST} > ${ZTGT}
                SRC="$ZTGT"
                ;;
            zip)
                # ZIP in directory of latest file to have relative directories
                # stored in the ZIP file
                cwd=$(pwd)
                cd $(dirname ${LATEST})
                zip -${COMPRESS} -P ${PASSWORD} ${ZTGT} $(basename ${LATEST})
                cd ${cwd}
                SRC="$ZTGT"
                ;;
        esac
    else
        SRC="$LATEST"
    fi

    if [ -n "${SRC}" ]; then
        log "Copying ${SRC} to ${DESTINATION}"
        cp ${SRC} ${DESTINATION}
    fi
fi

if [ -n "${KEEP}" ]; then
    while [ $(ls $DESTINATION -1 | wc -l) -gt $KEEP ]; do
        DELETE=$(ls $DESTINATION -1 | sort | head -n 1)
        log "Removing old copies $DELETE"
        rm -rf ${DESTINATION}/$DELETE
    done
fi

# Cleanup temporary directory
rm -rf $TMPDIR

if [ -n "${THEN}" ]; then
    log "Executing ${THEN}"
    if [ -e ${DESTINATION}/$(basename ${SRC}) ]; then
        eval "${THEN}" ${DESTINATION}/$(basename ${SRC})
    else
        eval "${THEN}"
    fi
fi
