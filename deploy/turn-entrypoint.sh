#!/bin/sh
set -eu
: "${TURN_SECRET:?Set TURN_SECRET}"
: "${PUBLIC_IP:?Set PUBLIC_IP}"
: "${HOST:?Set HOST}"
# Do not echo the shared secret or put it in the process arguments.
umask 077
printf 'static-auth-secret=%s\n' "$TURN_SECRET" > /tmp/turn-secret.conf
exec turnserver -c /tmp/turn-secret.conf \
  --use-auth-secret --realm="$HOST" --fingerprint \
  --listening-ip="$PUBLIC_IP" --relay-ip="$PUBLIC_IP" \
  --listening-port=3478 --min-port=49160 --max-port=49200 \
  --no-tls --no-tcp-relay --no-cli --no-multicast-peers \
  --denied-peer-ip=0.0.0.0-255.255.255.255 --denied-peer-ip=::-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff \
  --allowed-peer-ip="$PUBLIC_IP" \
  --user-quota=4 --total-quota=40 --max-bps=256000 --bps-capacity=5120000 \
  --no-stun --log-file=stdout --simple-log --pidfile=/tmp/turnserver.pid
