FROM redis:6.2-bullseye

LABEL maintainer="MCRI Bioinfomethods Group"

COPY bashrc /root/.bashrc

COPY redis.conf /usr/local/etc/redis/redis.conf

CMD [ "redis-server", "/usr/local/etc/redis/redis.conf" ]