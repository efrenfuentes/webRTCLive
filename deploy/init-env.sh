#!/bin/sh
# Run once from the repository root; never replace existing deployment secrets.
set -eu
if [ -e .env ]; then
  echo '.env already exists; leaving it unchanged.'
  exit 0
fi
umask 077
secret=$(openssl rand -hex 64)
sed "s/replace-with-a-random-secret/$secret/" .env.example > .env
