#!/bin/sh


# All (good?) defaults
VERBOSE=0
KEEP=""
HOST=localhost
PORT=5432
USER=postgres
PASSWORD=""
PASSWORDFILE=""
DESTINATION="."
NAME="%Y%m%d-%H%M%S.sql"
PENDING=".pending"
DB=""
THEN=""
OUTPUT="sql"

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
while getopts ":k:h:p:u:w:d:n:b:vt:W:o:P:" opt; do
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
        W)
            PASSWORDFILE="$OPTARG"
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
        o)
            OUTPUT="$OPTARG"
            ;;
        P)
            PENDING="$OPTARG"
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

# Returns absolute path for file, from: https://stackoverflow.com/a/20500246
abspath() {
    cd "$(dirname "$1")"
    printf "%s/%s\n" "$(pwd)" "$(basename "$1")"
    cd "$OLDPWD"
}

log() {
    local txt=$1

    if [ "$VERBOSE" == "1" ]; then
        echo "$txt"
    fi
}

csv_dump() {
    local db=$1

    log "Starting $OUTPUT backup of database $db to $FILE"
    mkdir -p ${DESTINATION}/$FILE/$db
    TABLES=$(echo "SELECT table_schema || '.' || table_name FROM information_schema.tables WHERE table_type = 'BASE TABLE' AND table_schema NOT IN ('pg_catalog', 'information_schema');" | psql -h $HOST -p $PORT -U $USER -d $db -q -t)
    for table in $TABLES; do
        DST=${DESTINATION}/$FILE/$db/${table}.csv
        log "Dumping $table to $DST"
        echo "COPY $table TO STDOUT WITH CSV HEADER;" | psql -h $HOST -p $PORT -U $USER -d $db > $DST
    done
}

if [ -n "$PASSWORDFILE" ]; then
    PASSWORD=$(cat $PASSWORDFILE)
fi
export PGPASSWORD=$PASSWORD
FILE=$(date +$NAME)

if [ "$OUTPUT" = "sql" ]; then
    # Decide name of destination file, this takes into account the pending
    # extension, if relevant.
    if [ -n "${PENDING}" ]; then
        DSTFILE=${FILE}.${PENDING##.}
    else
        DSTFILE=${FILE}
    fi

    # Dump one or all database to the destination file.
    if [ -z "${DB}" ]; then
        log "Starting $OUTPUT backup of all databases to $FILE"
        CMD="pg_dumpall -h $HOST -p $PORT -U $USER -w -f ${DESTINATION}/$DSTFILE"
    else 
        log "Starting $OUTPUT backup of database $DB to $FILE"
        CMD="pg_dump -h $HOST -p $PORT -U $USER -w -f ${DESTINATION}/$DSTFILE $DB"
    fi

    # Install (pending) backup file into proper name if relevant, or remove it
    # from disk.
    if $CMD; then
        if [ -n "${PENDING}" ]; then
            mv -f "${DSTFILE}" "${FILE}"
        fi
        log "Backup done"
    else
        echo "Could not create backup!" >& 2
        rm -rf ${DESTINATION}/$DSTFILE
    fi
elif [ "$OUTPUT" = "csv" ]; then
    if [ -z "${DB}" ]; then
        log "Starting $OUTPUT backup of all databases to $FILE"
        DBS=$(psql -h $HOST -p $PORT -U $USER -l -t|cut -d "|" -f 1| sed "s/^\s*//g")
        for db in $DBS; do
            if [ -n "$db" ]; then
                csv_dump $db
            fi
        done
    else
        csv_dump $DB
    fi
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
