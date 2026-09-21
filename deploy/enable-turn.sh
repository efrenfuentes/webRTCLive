#!/bin/sh
# Upgrade an existing deployment without rotating its signing secret.
set -eu
test -f .env
if grep -q '^TURN_SECRET=' .env; then
  echo 'TURN_SECRET already configured; leaving it unchanged.'
  exit 0
fi
umask 077
chmod 600 .env
printf '\nTURN_SECRET=%s\n' "$(openssl rand -hex 32)" >> .env
