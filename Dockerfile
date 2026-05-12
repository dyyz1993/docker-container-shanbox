FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    nginx \
    supervisor \
    curl \
    cron \
    ca-certificates \
    openssl \
    gettext-base \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/* \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

RUN mkdir -p /var/run/sshd /root/.ssh \
    && chmod 700 /root/.ssh \
    && sed -i 's/#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

RUN rm -f /etc/nginx/sites-enabled/default \
    && mkdir -p /usr/share/nginx/auth /etc/nginx/ssl /etc/nginx/routes.d /var/www

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY supervisord.conf /etc/supervisor/supervisord.conf

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/access-control.conf /etc/nginx/conf.d/access-control.conf
COPY nginx/server.conf.template /etc/nginx/templates/server.conf.template
COPY nginx/auth.html /usr/share/nginx/auth/auth.html

COPY scripts/ /root/scripts/
RUN chmod +x /root/scripts/*.sh

WORKDIR /root

EXPOSE 22 80 443

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n"]
