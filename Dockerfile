ARG ALPINE_VERSION=3.12.0
FROM alpine:${ALPINE_VERSION}

# Re-define the entire config
RUN apk add --no-cache postgresql-client zip
ADD *.sh /usr/local/bin/

ENTRYPOINT [ "/usr/local/bin/multi.sh" ]