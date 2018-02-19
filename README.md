# Simple Automated Backup Solution for PostgreSQL

This project covers two intertwined usecases:

1. Continuous and regular dumps of one or all PostgreSQL databases at a given
   host in a format that permits recovery in case of disasters.  This is
   `backup.sh`. 
2. Continuous and regular copying of these dumps in a compressed for to a
   (supposedly) remote directory in order to facilitate offsite backup and
   recovery in case of disasters. This is `offline.sh`.

The project is tuned for usage within a Dockerised environment and each tool
described below performs only one backup or compression.  Typical scenarios will
periodically restart containers based on this image using a host-wide cron-like
daemon such as [dockron](https://github.com/efrecon/dockron).

## Example

An example, [compose](https://docs.docker.com/compose/) file is
[provided](https://github.com/efrecon/pgbackup/blob/master/docker-compose.yml)
as an example of a real-life scenario.  The file `docker-compose.yml` starts up
the following containers:

1. `db`, an instance of the PostgreSQL database.
2. `pgbackup`, which runs `backup.sh` once and will perform a backup of all
   databases when it starts.
3. `davbackup`, which runs `offline.sh` once and will copy the latest backup to
   another volume in compressed form. This could be a WebDAV mounted volume,
   even though it isn't since this is just an example.
4. `pulse`, runs an instance of `efrecon/dockron` and will restart the two
   previous containers from time to time so they can regularily perform their
   operations.

