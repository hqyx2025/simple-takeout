#!/bin/sh
set -eu
umask 077
while true; do
  month=$(date +%Y%m)
  file="/backups/takeout-$month.sql.gz"
  if [ ! -s "$file" ]; then
    if mysqldump --single-transaction --quick --routines --triggers --no-tablespaces -h mysql -uroot takeout > /backups/dump.tmp.sql; then
      if gzip -c /backups/dump.tmp.sql > "$file.tmp" && gzip -t "$file.tmp"; then
        mv "$file.tmp" "$file"
        echo "Backup completed: $month"
      else
        rm -f "$file.tmp"
        echo "Backup compression failed" >&2
      fi
    else
      echo "Database backup failed; retry in one hour" >&2
    fi
    rm -f /backups/dump.tmp.sql
  fi
  sleep 3600
done
