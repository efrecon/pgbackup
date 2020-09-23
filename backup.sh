#!/usr/bin/env sh


if [ -t 1 ]; then
    INTERACTIVE=1
else
    INTERACTIVE=0
fi

# All (good?) defaults, we are also able to pick some of the POSTGRES_ led
# variables so as to be able to more easily share secrets with a postgres Docker
# image.
PGBACKUP_VERBOSE=${PGBACKUP_VERBOSE:-0}
PGBACKUP_KEEP=${PGBACKUP_KEEP:-""}
PGBACKUP_HOST=${PGBACKUP_HOST:-${POSTGRES_HOST:-localhost}}
PGBACKUP_PORT=${PGBACKUP_PORT:-${POSTGRES_PORT:-5432}}
PGBACKUP_USER=${PGBACKUP_USER:-${POSTGRES_USER:-postgres}}
PGBACKUP_PASSWORD=${PGBACKUP_PASSWORD:-${POSTGRES_PASSWORD:-""}}
PGBACKUP_PASSWORD_FILE=${PGBACKUP_PASSWORD_FILE:-${POSTGRES_PASSWORD_FILE:-""}}
PGBACKUP_DESTINATION=${PGBACKUP_DESTINATION:-"."}
PGBACKUP_NAME=${PGBACKUP_NAME:-"%Y%m%d-%H%M%S.sql"}
PGBACKUP_PENDING=${PGBACKUP_PENDING:-".pending"}
PGBACKUP_DB=${PGBACKUP_DB:-${POSTGRES_DB:-""}}
PGBACKUP_THEN=${PGBACKUP_THEN:-""}
PGBACKUP_OUTPUT=${PGBACKUP_OUTPUT:-"sql"}

# Dynamic vars
cmdname=$(basename "$(readlink -f "$0")")
appname=${cmdname%.*}

# Print usage on stderr and exit
usage() {
  exitcode="$1"
  cat << USAGE >&2

Description:
  $cmdname will backup one or all PostgreSQL databases at a given (remote)
  host, and rotate dumps to keep disk usage under control.

Usage:
  $cmdname [-option arg]...

  where all dash-led single options are as follows:
    -v              Be more verbose
    -h host         Specify host to connect to, defaults to localhost
    -p port         Specify port of daemon, defaults to 5432
    -u user         User to authenticate with at database, defaults to postgres.
    -w password     Password for user, defaults to empty
    -W path         Same as -w, but read content of password from file instead
    -d destination  Directory where to place (and rotate) backups.
    -n basename     Basename for file/dir to create, date-tags allowed, defaults to: %Y%m%d-%H%M%S.sql
    -k keep         Number of backups to keep, defaults to empty, meaning keep all backups
    -b database     Name of database to backup, defaults to empty, meaning all databases
    -t command      Command to execute once done, path to backup will be passed as an argument.
    -o output       Output type: sql or csv (only tables content).
    -P pending      Extension to give to file while creating backup
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

        -u | --user | --username)
            PGBACKUP_USER=$2; shift 2;;
        --user=* | --username=*)
            PGBACKUP_USER="${1#*=}"; shift 1;;

        -w | --password)
            PGBACKUP_PASSWORD=$2; shift 2;;
        --password=*)
            PGBACKUP_PASSWORD="${1#*=}"; shift 1;;

        -W | --password-file)
            PGBACKUP_PASSWORD_FILE=$2; shift 2;;
        --password-file=*)
            PGBACKUP_PASSWORD_FILE="${1#*=}"; shift 1;;

        -h | --host)
            PGBACKUP_HOST=$2; shift 2;;
        --host=*)
            PGBACKUP_HOST="${1#*=}"; shift 1;;

        -p | --port)
            PGBACKUP_PORT=$2; shift 2;;
        --port=*)
            PGBACKUP_PORT="${1#*=}"; shift 1;;

        -d | --dest | --destination)
            PGBACKUP_DESTINATION=$2; shift 2;;
        --dest=* | --destination=*)
            PGBACKUP_DESTINATION="${1#*=}"; shift 1;;

        -n | --name)
            PGBACKUP_NAME=$2; shift 2;;
        --name=*)
            PGBACKUP_NAME="${1#*=}"; shift 1;;

        -b | --db | --database)
            PGBACKUP_DB=$2; shift 2;;
        --db=* | --database=*)
            PGBACKUP_DB="${1#*=}"; shift 1;;

        -v | --verbose)
            PGBACKUP_VERBOSE=1; shift 1;;

        -t | --then)
            PGBACKUP_THEN=$2; shift 2;;
        --then=*)
            PGBACKUP_THEN="${1#*=}"; shift 1;;

        -o | --output)
            PGBACKUP_OUTPUT=$2; shift 2;;
        --output=*)
            PGBACKUP_OUTPUT="${1#*=}"; shift 1;;

        -P | --pending)
            PGBACKUP_PENDING=$2; shift 2;;
        --pending=*)
            PGBACKUP_PENDING="${1#*=}"; shift 1;;

        -\? | --help)
            usage 0;;
        --)
            shift; break;;
        -*)
            echo "Unknown option: $1 !" >&2 ; usage 1;;
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

csv_dump() {
    log "Starting $PGBACKUP_OUTPUT backup of database $1 to $FILE"
    mkdir -p "${PGBACKUP_DESTINATION}/$FILE/$1"
    TABLES=$(   echo "SELECT table_schema || '.' || table_name FROM information_schema.tables WHERE table_type = 'BASE TABLE' AND table_schema NOT IN ('pg_catalog', 'information_schema');" |
                psql    -h "$PGBACKUP_HOST" \
                        -p "$PGBACKUP_PORT" \
                        -U "$PGBACKUP_USER" \
                        -d "$db" \
                        -q \
                        -t)
    for table in $TABLES; do
        DST=${PGBACKUP_DESTINATION}/$FILE/$1/${table}.csv
        log "Dumping $table to $DST"
        printf "COPY %s TO STDOUT WITH CSV HEADER;\n" "$table" |
        psql    -h "$PGBACKUP_HOST" \
                -p "$PGBACKUP_PORT" \
                -U "$PGBACKUP_USER" \
                -d "$1" > "$DST"
    done
}

if [ -n "$PGBACKUP_PASSWORD_FILE" ]; then
    PGBACKUP_PASSWORD=$(cat "$PGBACKUP_PASSWORD_FILE")
fi
export PGPASSWORD=$PGBACKUP_PASSWORD
FILE=$(date +"$PGBACKUP_NAME")

if [ "$PGBACKUP_OUTPUT" = "sql" ]; then
    # Decide name of destination file, this takes into account the pending
    # extension, if relevant.
    if [ -n "${PGBACKUP_PENDING}" ]; then
        DSTFILE=${FILE}.${PGBACKUP_PENDING##.}
    else
        DSTFILE=${FILE}
    fi

    # Dump one or all database to the destination file.
    if [ -z "${PGBACKUP_DB}" ]; then
        log "Starting $PGBACKUP_OUTPUT backup of all databases to $FILE"
        CMD=pg_dumpall
    else
        log "Starting $PGBACKUP_OUTPUT backup of database $PGBACKUP_DB to $FILE"
        CMD=pg_dump
    fi

    # Install (pending) backup file into proper name if relevant, or remove it
    # from disk.
    if $CMD \
            -h "$PGBACKUP_HOST" \
            -p "$PGBACKUP_PORT" \
            -U "$PGBACKUP_USER" \
            -w \
            -f "${PGBACKUP_DESTINATION}/$DSTFILE" \
            $PGBACKUP_DB; then
        if [ -n "${PGBACKUP_PENDING}" ]; then
            mv -f "${PGBACKUP_DESTINATION}/${DSTFILE}" "${PGBACKUP_DESTINATION}/${FILE}"
        fi
        log "Backup done"
    else
        warn "Could not create backup!"
        rm -rf "${PGBACKUP_DESTINATION:?}/$DSTFILE"
    fi
elif [ "$PGBACKUP_OUTPUT" = "csv" ]; then
    if [ -z "${PGBACKUP_DB}" ]; then
        log "Starting $PGBACKUP_OUTPUT backup of all databases to $FILE"
        PGBACKUP_DBS=$(psql -h "$PGBACKUP_HOST" -p "$PGBACKUP_PORT" -U "$PGBACKUP_USER "-l -t|cut -d "|" -f 1| sed "s/^\s*//g")
        for db in $PGBACKUP_DBS; do
            if [ -n "$db" ]; then
                csv_dump "$db"
            fi
        done
    else
        csv_dump "$PGBACKUP_DB"
    fi
fi

if [ -n "${PGBACKUP_KEEP}" ]; then
    # shellcheck disable=SC2012
    while [ "$(ls "$PGBACKUP_DESTINATION" -1 | wc -l)" -gt "$PGBACKUP_KEEP" ]; do
        DELETE=$(ls "$PGBACKUP_DESTINATION" -1 | sort | head -n 1)
        log "Removing old backup $DELETE"
        rm -rf "${PGBACKUP_DESTINATION:?}/$DELETE"
    done
fi

if [ -n "${PGBACKUP_THEN}" ]; then
    log "Executing ${PGBACKUP_THEN}"
    if [ -f "${PGBACKUP_DESTINATION}/$FILE" ]; then
        eval "${PGBACKUP_THEN}" "${PGBACKUP_DESTINATION}/$FILE"
    else
        eval "${PGBACKUP_THEN}"
    fi
fi
