FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
RUN apt-get update \
 && apt-get install -y --no-install-recommends gettext \
 && rm -rf /var/lib/apt/lists/*
ARG SUPERCRONIC_VERSION=v0.2.33
ARG TARGETARCH
ADD https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${TARGETARCH} /usr/local/bin/supercronic
RUN chmod +x /usr/local/bin/supercronic
WORKDIR /app
COPY requirements/ requirements/

FROM base AS dev
RUN pip install -r requirements/dev.txt
COPY . .
RUN chmod +x entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]

FROM base AS prod
RUN pip install -r requirements/prod.txt
COPY . .
# collectstatic loads the settings, which need these variables; the real values come from .env at runtime.
RUN chmod +x entrypoint.sh \
 && DJANGO_SETTINGS_MODULE=config.settings.prod \
    DJANGO_SECRET_KEY=build-only \
    DATABASE_URL=sqlite:////tmp/build.db \
    python manage.py collectstatic --noinput
RUN useradd --create-home app && chown -R app /app
USER app
ENTRYPOINT ["./entrypoint.sh"]
CMD ["gunicorn", "config.wsgi:application", "-b", "0.0.0.0:8000", "-w", "3"]