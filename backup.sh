#!/bin/sh


# All (good?) defaults
VERBOSE=0
KEEP=""
HOST=localhost
PORT=5432
USER=postgres
PASSWORD=""
DESTINATION="."
NAME="%Y%m%d-%H%M%S.sql"
DB=""
THEN=""

# Dynamic vars
cmdname=$(basename "${0}")

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
    -d destination  Directory where to place (and rotate) backups.
    -n basename     Basename for file to create, date-tags allowed, defaults to: %Y%m%d-%H%M%S.sql
    -k keep         Number of backups to keep, defaults to empty, meaning keep all backups
    -b database     Name of database to backup, defaults to empty, meaning all databases
    -t command      Command to execute once done, path to backup will be passed as an argument.
USAGE
  exit "$exitcode"
}


# Parse options 
while getopts ":k:h:p:u:w:d:n:b:vt:" opt; do
    case $opt in
        k)
            KEEP="$OPTARG"
            ;;
        u)
            USER="$OPTARG"
            ;;
        w)
            PASSWORD="$OPTARG"
            ;;
        h)
            HOST="$OPTARG"
            ;;
        p)
            PORT="$OPTARG"
            ;;
        k)
            KEEP="$OPTARG"
            ;;
        d)
            DESTINATION="$OPTARG"
            ;;
        n)
            NAME="$OPTARG"
            ;;
        b)
            DB="$OPTARG"
            ;;
        v)
            VERBOSE=1
            ;;
        t)
            THEN="$OPTARG"
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

log() {
    local txt=$1

    if [ "$VERBOSE" == "1" ]; then
        echo "$txt"
    fi
}

export PGPASSWORD=$PASSWORD
FILE=$(date +$NAME)
if [ -z "${DB}" ]; then
    log "Starting backup of all databases to $FILE"
    CMD="pg_dumpall -h $HOST -p $PORT -U $USER -w -f ${DESTINATION}/$FILE"
else 
    log "Starting backup of database $DB to $FILE"
    CMD="pg_dump -h $HOST -p $PORT -U $USER -w -f ${DESTINATION}/$FILE $DB"
fi

if $CMD; then
    log "Backup done"
else
    echo "Could not create backup!" >& 2
    rm -rf ${DESTINATION}/$FILE
fi

if [ -n "${KEEP}" ]; then
    while [ $(ls $DESTINATION -1 | wc -l) -gt $KEEP ]; do
        DELETE=$(ls $DESTINATION -1 | sort | head -n 1)
        log "Removing old backup $DELETE"
        rm -rf ${DESTINATION}/$DELETE
    done
fi

if [ -n "${THEN}" ]; then
    log "Executing ${THEN}"
    if [ -e ${DESTINATION}/$FILE ]; then
        eval "${THEN}" ${DESTINATION}/$FILE
    else
        eval "${THEN}"
    fi
fi
