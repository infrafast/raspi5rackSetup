#!/bin/sh

PROJECT="/home/pi/interval/QLCfiles/intervalPI5.qxw"
BACKUP="/home/pi/interval/QLCfiles/backup/intervalPI5.qxw"

# Workspace absent or abnormally small
if [ ! -s "$PROJECT" ] || [ "$(stat -c%s "$PROJECT" 2>/dev/null || echo 0)" -lt 1000 ]; then
    echo "QLC workspace invalid: restoring backup"
    if [ -s "$BACKUP" ]; then
        cp -p "$BACKUP" "$PROJECT"
        sync
    else
        echo "ERROR: no valid QLC backup available" >&2
        exit 1
    fi
fi

exit 0
