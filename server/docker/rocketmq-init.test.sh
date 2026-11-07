#!/bin/sh
set -eu
scripts=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat > "$work/mqadmin" <<'STUB'
#!/bin/sh
if [ "$1" = "${FAIL_STAGE:-}" ]; then
    echo 'SubCommandException: injected RPC failure'
    exit 0
fi
case "$1" in
    updateTopic) echo 'create topic to broker:10911 success.' ;;
    updateSubGroup) echo 'create subscription group to broker:10911 success.' ;;
esac
STUB
for stage in updateTopic updateSubGroup; do
    if (cd "$work"; FAIL_STAGE=$stage TAKEOUT_ROCKETMQ_BROKER_ADDR=broker:10911 sh "$scripts/rocketmq-init.sh"); then
        echo "Failed to reject $stage RPC failure" >&2
        exit 1
    fi
done
(cd "$work"; TAKEOUT_ROCKETMQ_BROKER_ADDR=broker:10911 sh "$scripts/rocketmq-init.sh")
echo 'Initialization acknowledgement checks passed.'
