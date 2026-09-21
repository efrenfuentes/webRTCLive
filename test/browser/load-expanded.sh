#!/bin/sh
# Temporarily test 10 direct rooms, restoring production limits even on failure.
# Upload deploy/load-test.compose.yaml to /opt/webrtc-live/deploy first.
set -eu
: "${DEPLOY_SSH_HOST:?Set DEPLOY_SSH_HOST}"
case "$DEPLOY_SSH_HOST" in *[!a-zA-Z0-9_.-]*|'') exit 2;; esac
restore() {
  ssh "$DEPLOY_SSH_HOST" 'cd /opt/webrtc-live && docker compose up -d app'
}
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ssh "$DEPLOY_SSH_HOST" 'cd /opt/webrtc-live && docker compose -f compose.yaml -f deploy/load-test.compose.yaml up -d app'
# The release takes a few seconds to boot; keep certificate verification enabled.
curl --fail --silent --show-error --retry 10 --retry-delay 2 --retry-all-errors --max-time 10 "${BASE_URL:?Set BASE_URL}/health"
ROOMS=10 TURN_TRANSPORT=direct node test/browser/load.mjs
