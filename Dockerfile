ARG ALPINE_VERSION=3.18
ARG POSTGRES_VERSION=15
FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache postgresql${POSTGRES_VERSION}-client zip tini
ADD *.sh wait-for/*.sh /usr/local/bin/

ENTRYPOINT [ "/sbin/tini", "--", "/usr/local/bin/multi.sh" ]