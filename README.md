# Simple Automated Backup Solution for PostgreSQL

This project covers two intertwined usecases:

1. Continuous and regular dumps of one or all [PostgreSQL] databases at a given
   host in a format that permits recovery in case of disasters.  This is
   `backup.sh`. 
2. Continuous and regular copying of these dumps in a compressed for to a
   (supposedly) remote directory in order to facilitate offsite backup and
   recovery in case of disasters. This is `offsite.sh`.

The project is tuned for usage within a Dockerised environment and each tool
described below performs only one backup or compression.  Typical scenarios will
periodically restart containers based on this image using a host-wide cron-like
daemon such as [dockron].

  [PostgreSQL]: https://www.postgresql.org/
  [dockron]: https://github.com/efrecon/dockron

## Example

An example [compose] file is provided as a plausible real-life scenario.  The
file `docker-compose.yml` starts up the following containers:

1. `db`, an instance of the PostgreSQL database.
2. `pgbackup`, which runs `backup.sh` once and will perform a backup of all
   databases when it starts.
3. `davbackup`, which runs `offsite.sh` once and will copy the latest backup to
   another volume in compressed form. This could be a WebDAV mounted volume,
   even though it isn't since this is just an example.
4. `pulse`, runs an instance of `efrecon/dockron` and will restart the two
   previous containers from time to time so they can regularily perform their
   operations.

  [compose]: https://docs.docker.com/compose/

## Usage and Command-Line Options

### `backup.sh`

This shell (not bash) script has the following options:

```
Description:
  backup.sh will backup one or all PostgreSQL databases at a given (remote)
  host, and rotate dumps to keep disk usage under control.

Usage:
  backup.sh [-option arg]...

  where all dash-led single options are as follows:
    -v              Be more verbose
    -h host         Specify host to connect to, defaults to localhost
    -p port         Specify port of daemon, defaults to 5432
    -u user         User to authenticate with at database, defaults to postgres.
    -w password     Password for user, defaults to empty
    -W path         Same as -w, but read content of password from file instead
    -d destination  Directory where to place (and rotate) backups.
    -n basename     Basename for file to create, date-tags allowed, defaults to: %Y%m%d-%H%M%S.sql
    -k keep         Number of backups to keep, defaults to empty, meaning keep all backups
    -b database     Name of database to backup, defaults to empty, meaning all databases
    -t command      Command to execute once done, path to backup will be passed as an argument.
```

### `offsite.sh`

This shell (not bash) script has the following options:

```
Description:
  offline.sh will compress the latest file matching a pattern, compress it,
  move it to a destination directory and rotate files in this directory
  to keep disk space under control. Compression via zip is preferred,
  otherwise gzip.

Usage:
  offline.sh [-option arg] pattern

  where all dash-led single options are as follows:
    -v              Be more verbose
    -d destination  Directory where to place (and rotate) compressed copies, default to current dir
    -k keep         Number of compressed copies to keep, defaults to empty, meaning all
    -c level        Compression level, defaults to 0, meaning no compression
    -w password     Password for compressed archive, only when zip available
    -W path         Same as -w, but read content of password from file instead
    -t command      Command to execute once done, path to copy will be passed as an argument
```

### Docker

`multi.sh` is specified as the default entrypoint for the image; it relays both scripts.  The following command would for example request `backup.sh` for help:

```Shell
docker run -it --rm efrecon/pgbackup backup -?
```