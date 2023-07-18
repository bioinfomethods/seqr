FROM python:3.9-bullseye

LABEL maintainer="MCRI Bioinfomethods Group"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    bzip2 \
    curl \
    gcc \
    git \
    libc6-dev \
    libpq-dev \
    cron \
    curl \
    gnupg \
    htop \
    less \
    procps \
    redis-tools \
    vim \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# install gcloud tools
RUN echo "deb http://packages.cloud.google.com/apt cloud-sdk-bullseye main" > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - \
    && apt-get update && apt-get install -y --no-install-recommends \
    google-cloud-sdk \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

COPY ./requirements.txt .

# install seqr python dependencies
RUN pip install --no-cache-dir wheel && \
    pip install --no-cache-dir -U setuptools && \
    pip install --no-cache-dir -r requirements.txt

COPY . .

ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

ENTRYPOINT [ "python3", "/opt/cache-obs.py" ]
