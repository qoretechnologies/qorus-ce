FROM alpine:3.17 as qorus_base
WORKDIR /tmp/qorus
COPY . .
RUN apk add --no-cache bash
RUN ./docker/alpine/prep_base.sh

FROM alpine:3.17 as qorus

LABEL maintainer="devs@qoretechnologies.com" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.vendor="Qore Technologies" \
      org.label-schema.name="Qorus Release Image - Alpine Linux 3.17"

COPY --from=qorus_base /buildroot /

RUN mkdir -p /usr/share/man/man1 /usr/share/man/man7 \
 && apk update \
 && apk add tzdata \
 && cp /usr/share/zoneinfo/Europe/Prague /etc/localtime \
 && echo "Europe/Prague" > /etc/timezone \
 && apk add --no-cache bash \
 && apk add \
        libaio \
        boost-dev \
        boost-filesystem \
        curl \
        czmq \
        freetds \
        libbz2 \
        libgcc \
        libpcrecpp \
        libpq \
        libssh2 \
        libuuid \
        libxml2 \
        mariadb-connector-c \
        mpfr4 \
        openjdk17-jdk \
        openldap \
        openssl \
        runit \
        vim \
        xmlsec \
        yaml
ENV PYTHONUNBUFFERED=1
RUN apk add --update --no-cache python3 && ln -sf python3 /usr/bin/python
RUN python3 -m ensurepip
RUN pip3 install --no-cache --upgrade pip setuptools
RUN ln -sf pip3 /usr/bin/pip

EXPOSE 8001 8011

VOLUME /opt/qorus/etc
VOLUME /opt/qorus/log

STOPSIGNAL SIGTERM

ENTRYPOINT [ "/opt/qorus/bin/entrypoint.sh" ]
