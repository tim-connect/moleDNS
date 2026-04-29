FROM alpine:latest

RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories \
    && echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories \
    && echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories \
    && apk update \
    && apk upgrade \
    && apk add --no-cache socat bash tor bind-tools dnscrypt-proxy tini coreutils dnsmasq iptables

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && adduser -D -u 10001 toruser
#RUN mkdir -p /tmp/tor && chown -R toruser:toruser /tmp/tor
#RUN mkdir -p /tmp/tor-clearnet && chown -R toruser:toruser /tmp/tor-clearnet

COPY dnscrypt-proxy.toml /dnscrypt-proxy.toml
COPY dnscrypt-proxy-hidden.toml /dnscrypt-proxy-hidden.toml
COPY hosts /etc/hosts
COPY dnsmasq-servers.conf /dnsmasq-servers.conf
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/entrypoint.sh"]
