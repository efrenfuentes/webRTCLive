#!/bin/sh
# Run once from the repository root; never replace existing deployment secrets.
set -eu
if [ -e .env ]; then
  echo '.env already exists; leaving it unchanged.'
  exit 0
fi
umask 077
secret=$(openssl rand -hex 64)
turn_secret=$(openssl rand -hex 32)
db_password=$(openssl rand -hex 32)
sed -e "s/replace-with-a-random-secret/$secret/" \
    -e "s/replace-with-a-random-turn-secret/$turn_secret/" \
    -e "s/replace-with-a-random-database-password/$db_password/g" .env.example > .env
