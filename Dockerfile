ARG ALPINE_VERSION=3.12.0
FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache postgresql-client zip tini
ADD *.sh wait-for/*.sh /usr/local/bin/

ENTRYPOINT [ "/sbin/tini", "--", "/usr/local/bin/multi.sh" ]