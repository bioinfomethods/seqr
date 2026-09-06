FROM python:3.11-slim-bullseye AS build

LABEL maintainer="Broad TGG"

# install commmon utilities, database clients for debugging
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Add Debian's second official security mirror alongside the default and let apt retry.
#
# deb.debian.org and security.debian.org are both CDN fronts for bullseye-security, and
# from some networks each edge serves an incomplete pool: linux-libc-dev 404s on
# deb.debian.org while security.debian.org has it, and libc6-dev 404s on
# security.debian.org while deb.debian.org has it. Either alone fails the install with
# "E: Failed to fetch ... 404 Not Found"; listing both lets apt fall back to whichever
# edge holds the file. Harmless where the default mirror is already complete.
RUN printf 'deb http://security.debian.org/debian-security bullseye-security main\n' \
      >> /etc/apt/sources.list \
    && printf 'Acquire::Retries "3";\n' > /etc/apt/apt.conf.d/80-retries

RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    bzip2 \
    curl \
    gcc \
    # git needed for npm dependencies referenced by git URL
    git \
    libc6-dev \
    libpq-dev \
    # xz-utils: slim images ship tar without xz support, needed for the node tarball
    xz-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# install nodejs 18 LTS from the official distribution tarball.
#
# NOT via NodeSource. Its setup script apt-installs the full `gnupg` metapackage just to
# add a signing key, which drags in gnupg-l10n and gpg-wks-client. Both of those .deb
# files are currently missing from deb.debian.org's bullseye-security pool (404, while
# their siblings in the same directory return 200), so that install fails.
#
# The dangerous part is the failure mode, not the outage: `curl ... | bash -` exits 0
# even when the script errors, so the `&&` chain continued and apt-installed Debian's
# own nodejs 12 -- which ships no npm at all. The build then died much later on `npm ci`
# with "npm: command not found", pointing nowhere near the real cause.
#
# A pinned tarball has no apt or GPG dependency, is checksum-verified, and gives an
# identical node/npm on every machine.
ENV NODE_VERSION=v18.20.8
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) NODE_ARCH=x64 ;; \
        arm64) NODE_ARCH=arm64 ;; \
        *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    TARBALL="node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"; \
    cd /tmp; \
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${TARBALL}" -o "${TARBALL}"; \
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt" -o SHASUMS256.txt; \
    grep " ${TARBALL}\$" SHASUMS256.txt | sha256sum -c -; \
    tar -xJf "${TARBALL}" -C /usr/local --strip-components=1 --no-same-owner; \
    rm -f "${TARBALL}" SHASUMS256.txt; \
    node --version; \
    npm --version

WORKDIR /opt

COPY ./requirements.txt .

# install seqr python dependencies
# NOTE: setuptools must be <71 to retain pkg_resources (needed by django-model-utils/django-notifications-hq)
RUN pip install --no-cache-dir wheel && \
    pip install --no-cache-dir "setuptools>=65,<71" && \
    pip install --no-cache-dir -r requirements.txt

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
# Add Debian's second official security mirror alongside the default and let apt retry.
#
# deb.debian.org and security.debian.org are both CDN fronts for bullseye-security, and
# from some networks each edge serves an incomplete pool: linux-libc-dev 404s on
# deb.debian.org while security.debian.org has it, and libc6-dev 404s on
# security.debian.org while deb.debian.org has it. Either alone fails the install with
# "E: Failed to fetch ... 404 Not Found"; listing both lets apt fall back to whichever
# edge holds the file. Harmless where the default mirror is already complete.
RUN printf 'deb http://security.debian.org/debian-security bullseye-security main\n' \
      >> /etc/apt/sources.list \
    && printf 'Acquire::Retries "3";\n' > /etc/apt/apt.conf.d/80-retries

# Packages the container needs to run. entrypoint.sh calls pg_isready, the healthcheck
# calls curl, psycopg2 needs libpq. A failure here must fail the build.
RUN apt-get update && apt-get install -y --no-install-recommends \
    cron \
    curl \
    groff \
    libpq-dev \
    postgresql-client \
    procps \
    redis-tools \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Interactive conveniences for poking around inside a running container. Installed
# best-effort, because none of them affect whether seqr runs.
#
# This is not blanket error-swallowing: the group is separated precisely so that the
# required packages above still fail the build loudly, and a skip is printed rather than
# hidden. Without the split, one unavailable editor takes down the whole image.
#
# It happens today with vim. Debian's bullseye-security index advertises
# 2:8.2.2434-3+deb11u3, and the file is genuinely on the mirror -- fetching
# .../vim_8.2.2434-3+deb11u3_arm64.deb returns 200 and a valid 1.4MB .deb. But apt
# percent-encodes the '+', and .../vim_8.2.2434-3%2bdeb11u3_arm64.deb returns 404 from
# both deb.debian.org and security.debian.org. apt only ever sends the encoded form, so
# it cannot fetch a file that is sitting right there, and it fails over to the second
# mirror only to get the same 404. The same URL in the main archive
# (vim_8.2.2434-3%2bdeb11u1) returns 200, so this is a per-URL artifact in the security
# pool rather than anything wrong with the package or the mirrors.
ENV SEQR_OPTIONAL_TOOLS="htop less nano screen vim xterm"
RUN apt-get update && { \
        # Try the group first, so the common case is a single fast transaction. apt fails
        # the whole transaction if any one package cannot be fetched, so fall back to
        # installing them individually and keep everything except the broken one.
        apt-get install -y --no-install-recommends ${SEQR_OPTIONAL_TOOLS} \
        || for pkg in ${SEQR_OPTIONAL_TOOLS}; do \
               apt-get install -y --no-install-recommends "$pkg" \
               || echo "WARNING: optional package unavailable from the Debian mirrors, skipping: $pkg"; \
           done; \
    } \
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
