# Simple Automated Backup Solution for PostgreSQL

This project covers two intertwined usecases:

1. Continuous and regular dumps of one or all PostgreSQL databases at a given
   host in a format that permits recovery in case of disasters.
2. Continuous and regular copying of these dumps in a compressed for to a
   (supposedly) remote directory in order to facilitate offsite backup and
   recovery in case of disasters.

The project is tuned for usage within a Dockerised environment.  Typical
scenarios will periodically restart containers based on this image using a
host-wide cron-like daemon such as
[dockron](https://github.com/efrecon/dockron).