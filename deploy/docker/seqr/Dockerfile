FROM python:3.11-slim-bullseye AS build

LABEL maintainer="Broad TGG"

# install commmon utilities, database clients for debugging
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    bzip2 \
    curl \
    gcc \
    # git needed for the nodejs install
    git \
    libc6-dev \
    libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# install nodejs18 LTS via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

COPY ./requirements.txt .

# install seqr python dependencies
# NOTE: setuptools must be <71 to retain pkg_resources (needed by django-model-utils/django-notifications-hq)
RUN pip install --no-cache-dir wheel && \
    pip install --no-cache-dir "setuptools>=65,<71" && \
    pip install --no-cache-dir -r requirements.txt
# Django 3.2.25 LTS is required for clickhouse-backend compatibility

# install seqr nodejs dependencies
WORKDIR /build/ui
# Copy the package configs from the build context -> the temporary build container, for generating node_modules
COPY ./ui/package.json .
COPY ./ui/package-lock.json .
RUN npm ci

COPY ./ui/ .

RUN npm run build

FROM python:3.11-slim-bullseye AS runtime

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install -y --no-install-recommends \
    cron \
    curl \
    groff \
    htop \
    less \
    libpq-dev \
    nano \
    vim \
    postgresql-client \
    procps \
    redis-tools \
    screen \
    xterm \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/venv /opt/venv

# Install AWS CLI (useful for S3 access to data files from ECS tasks)
RUN pip install --no-cache-dir awscli

# Pre-download liftover chain file for offline environments (e.g., AWS Fargate)
RUN mkdir -p /data/liftover && \
    curl -fsSL -o /data/liftover/hg19ToHg38.over.chain.gz \
    https://hgdownload.soe.ucsc.edu/goldenPath/hg19/liftOver/hg19ToHg38.over.chain.gz

WORKDIR /seqr
COPY admin/ ./admin
COPY clickhouse_search/ ./clickhouse_search
COPY matchmaker/ ./matchmaker
COPY mcri_ext/ ./mcri_ext
COPY panelapp/ ./panelapp
COPY reference_data/ ./reference_data
COPY seqr/ ./seqr
COPY scripts/ ./scripts
COPY manage.py settings.py wsgi.py ./
COPY --from=build /build/ui/dist /seqr/ui/dist

ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN ./manage.py collectstatic --no-input

EXPOSE 8000

ENV TERM=xterm

COPY deploy/docker/seqr/readiness_probe /
COPY deploy/docker/seqr/wait_for_routes /
COPY deploy/docker/seqr/bin/*.sh /usr/local/bin/
COPY deploy/docker/seqr/config/*.py ./
COPY deploy/docker/seqr/bashrc /root/.bashrc

COPY deploy/docker/seqr/entrypoint.sh /

CMD [ "/entrypoint.sh" ]
