FROM ubuntu:jammy as qorus_base
COPY . /tmp/qorus/
RUN /tmp/qorus/docker/ubuntu/prep_base_debug.sh

FROM ubuntu:jammy as qorus

LABEL maintainer="devs@qoretechnologies.com" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.vendor="Qore Technologies" \
      org.label-schema.name="Qorus Release Image - Ubuntu Jammy Jellyfish"

COPY --from=qorus_base /buildroot /delta
RUN cp -apRxuv /delta/* / && rm -rf /delta

RUN  mkdir -p /usr/share/man/man1 /usr/share/man/man7 \
&&  apt update && apt upgrade -y \
&&  ln -fs /usr/share/zoneinfo/Europe/Prague /etc/localtime \
&&  apt-get install -y tzdata \
&&  dpkg-reconfigure --frontend noninteractive tzdata \
&&  apt-get -y install --no-install-recommends \
        netbase \
        ca-certificates \
        openssl \
        libmpfr6 \
        libpcre3 \
        libssl3 \
        zlib1g \
        runit \
        dumb-init \
        procps \
        iproute2 \
        bzip2 \
        xz-utils \
        curl \
        vim \
        libmagic1 \
        libmariadb3 \
        libaio1 \
        unixodbc \
        odbcinst1debian2 \
        libtommath1 \
        libldap-2.5-0 \
        postgresql-client-14 \
        uuid-runtime \
        freetds-bin \
        libct4 \
        libxml2 \
        libxmlsec1 \
        libxmlsec1-openssl \
        libyaml-0-2 \
        libzmq5 \
        libczmq4 \
        nodejs \
        openjdk-17-jdk \
        libpython3.10 \
        pip \
        python-is-python3 \
        less \
&&  apt -y install software-properties-common dirmngr apt-transport-https lsb-release ca-certificates \
&&  apt-get -y clean \
&&  rm -rf /var/lib/apt/lists/*

EXPOSE 8001 8011

VOLUME /opt/qorus/etc
VOLUME /opt/qorus/log

STOPSIGNAL SIGTERM

ENTRYPOINT ["/opt/qorus/bin/entrypoint.sh"]
