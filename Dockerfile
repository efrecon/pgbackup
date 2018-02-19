FROM alpine:3.7

# Re-define the entire config
RUN apk add --no-cache postgresql-client zip
ADD *.sh /usr/local/bin/

ENTRYPOINT [ "/usr/local/bin/multi.sh" ]