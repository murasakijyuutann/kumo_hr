#!/bin/sh
set -e

echo "Waiting for the database..."
until python -c "import os, psycopg; psycopg.connect(os.environ['DATABASE_URL'], connect_timeout=2).close()" 2>/dev/null
do
    sleep 1
done

if [ -d locale ]; then
    python manage.py compilemessages
fi
python manage.py migrate --noinput
python manage.py createcachetable

exec "$@"