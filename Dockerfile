FROM alpine

RUN apk update && apk upgrade

RUN apk add --no-cache curl jq

RUN curl -L https://fly.io/install.sh | FLYCTL_INSTALL=/usr/local sh

RUN apk --no-cache add git

RUN which git

RUN apk --no-cache --update add build-base

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
