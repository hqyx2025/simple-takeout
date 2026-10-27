#!/bin/sh
set -eu
umask 077
# Private demo: retain 14 daily copies. Copy backups off the server separately.
host=${MYSQL_BACKUP_HOST:-mysql}
database=${MYSQL_BACKUP_DATABASE:-takeout}
prefix=${MYSQL_BACKUP_PREFIX:-takeout}
case "$database" in ''|*[!a-zA-Z0-9_]*) echo 'Invalid backup database' >&2; exit 1;; esac
case "$prefix" in ''|*[!a-zA-Z0-9_-]*) echo 'Invalid backup prefix' >&2; exit 1;; esac
temporary="/backups/$prefix.dump.tmp.sql"
while true; do
  day=$(date +%Y%m%d)
  file="/backups/$prefix-$day.sql.gz"
  if [ ! -s "$file" ]; then
    if mysqldump --single-transaction --quick --routines --triggers --no-tablespaces \
        -h "$host" -uroot "$database" > "$temporary"; then
      if gzip -c "$temporary" > "$file.tmp" && gzip -t "$file.tmp"; then
        mv "$file.tmp" "$file"
        echo "Backup completed: $prefix $day"
        find /backups -maxdepth 1 -type f -name "$prefix-????????.sql.gz" -mtime +14 -delete
      else
        rm -f "$file.tmp"
        echo 'Backup compression failed' >&2
      fi
    else
      echo 'Database backup failed; retry in one hour' >&2
    fi
    rm -f "$temporary"
  fi
  sleep 3600
done
