#!/bin/sh
set -eu
umask 077
# Private demo: retain 14 daily copies. Copy backups off the server separately.
while true; do
  day=$(date +%Y%m%d)
  file="/backups/takeout-$day.sql.gz"
  if [ ! -s "$file" ]; then
    if mysqldump --single-transaction --quick --routines --triggers --no-tablespaces \
        -h mysql -uroot takeout > /backups/dump.tmp.sql; then
      if gzip -c /backups/dump.tmp.sql > "$file.tmp" && gzip -t "$file.tmp"; then
        mv "$file.tmp" "$file"
        echo "Backup completed: $day"
        find /backups -maxdepth 1 -type f -name 'takeout-????????.sql.gz' -mtime +14 -delete
      else
        rm -f "$file.tmp"
        echo 'Backup compression failed' >&2
      fi
    else
      echo 'Database backup failed; retry in one hour' >&2
    fi
    rm -f /backups/dump.tmp.sql
  fi
  sleep 3600
done
