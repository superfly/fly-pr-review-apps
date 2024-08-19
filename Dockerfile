FROM elixir:1.7.2-alpine

RUN apk add --no-cache curl jq

RUN curl -L https://fly.io/install.sh | FLYCTL_INSTALL=/usr/local sh

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
