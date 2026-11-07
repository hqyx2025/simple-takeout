#!/bin/sh
set -eu

namesrv=${TAKEOUT_ROCKETMQ_NAMESRV_ADDR:-rocketmq-namesrv:9876}
broker=${TAKEOUT_ROCKETMQ_BROKER_ADDR:-rocketmq-broker:10911}
topic=${TAKEOUT_ROCKETMQ_TOPIC:-takeout-domain-events}
group=${TAKEOUT_ROCKETMQ_CONSUMER_GROUP:-takeout-notifications}

# mqadmin prints some RPC exceptions but exits 0. Require its remote-success acknowledgement.
confirmed() {
    expected=$1
    shift
    output=$(sh mqadmin "$@" 2>&1) || { printf '%s\n' "$output" >&2; return 1; }
    printf '%s\n' "$output"
    printf '%s\n' "$output" | grep -Fx "$expected" >/dev/null || {
        printf '%s\n' 'RocketMQ initialization was not confirmed by the broker.' >&2
        return 1
    }
}

confirmed "create topic to $broker success." updateTopic -n "$namesrv" -b "$broker" -t "$topic" -r 4 -w 4
confirmed "create subscription group to $broker success." updateSubGroup -n "$namesrv" -b "$broker" -g "$group"
confirmed "create subscription group to $broker success." updateSubGroup -n "$namesrv" -b "$broker" -g "$group-replay"
