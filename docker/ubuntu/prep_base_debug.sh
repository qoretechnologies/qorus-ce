#!/bin/bash

# The following script downloads sources for Qore, necessary modules, Qorus and
# required libraries, and then builds everything. After building, everything
# is moved to /buildroot directory from where it is copied to the next stage.
# Also clean up is done after this so that the stage doesn't occupy unnecessary
# space after everything is done.

set -e
set -x

# get CPU architecture
arch=`uname -m`

export WORKDIR=/tmp
export INSTALL_PREFIX=/opt
export OMQ_DIR=/opt/qorus
export MAKE_JOBS=4

export ORACLE_INSTANT_CLIENT=/usr/lib/oracle
export ORACLE_HOME=${ORACLE_INSTANT_CLIENT}
export TNS_ADMIN=${ORACLE_INSTANT_CLIENT}

export PATH=${INSTALL_PREFIX}/bin:$PATH
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS} -Dfile.encoding=UTF8"

if [ "$arch" = "aarch64" ]; then
    export LD_LIBRARY_PATH=${ORACLE_INSTANT_CLIENT}:${INSTALL_PREFIX}/lib:${INSTALL_PREFIX}/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH}
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64
else
    export LD_LIBRARY_PATH=${ORACLE_INSTANT_CLIENT}:${INSTALL_PREFIX}/lib:${INSTALL_PREFIX}/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
fi

export QORE_BRANCH="develop"
export MODULE_BRANCH="develop"
export WEBAPP_BRANCH="develop"

export AUTO_MODULES="sybase"
export CMAKE_MODULES="oracle python jni json linenoise magic odbc openldap ssh2 sysconf uuid xml xmlsec yaml zmq process fsevent pgsql mysql"
export MODULES="$AUTO_MODULES $CMAKE_MODULES"

# needed to install Java
mkdir -p /usr/share/man/man1 ${INSTALL_PREFIX}

# install necessary packages for Qore
echo "-- installing Qore packages --"
apt-get -y update
ln -fs /usr/share/zoneinfo/Europe/Prague /etc/localtime
apt-get install -y tzdata
dpkg-reconfigure --frontend noninteractive tzdata

apt-get -y install --no-install-recommends \
    netbase \
    ca-certificates \
    gnupg1 \
    wget \
    curl \
    apt-transport-https \
    unzip \
    bzip2 \
    git \
    g++ \
    make \
    automake \
    cmake \
    pkg-config \
    libtool \
    flex \
    bison \
    libmpfr-dev \
    libpcre3-dev \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libxmlsec1-dev \
    doxygen

# install necessary packages for modules
echo && echo "-- installing module packages --"
apt-get -y update
apt-get -y install --no-install-recommends \
    libmagic-dev \
    libmariadb-dev \
    libmariadb-dev-compat \
    libaio-dev \
    unixodbc-dev \
    libldap2-dev \
    postgresql-server-dev-14 \
    uuid-dev \
    freetds-dev \
    libxml2-dev \
    libyaml-dev \
    libzmq3-dev \
    libczmq-dev \
    nodejs \
    yarn \
    python3-dev \
    libpython3.10 \
    python-is-python3 \
    openjdk-17-jdk

# install go
cd $WORKDIR
GO_VER="1.16.4"
if [ "$arch" = "aarch64" ]; then
    GO_TAR=go${GO_VER}.linux-arm64.tar.gz
else
    GO_TAR=go${GO_VER}.linux-amd64.tar.gz
fi
wget https://dl.google.com/go/${GO_TAR}
tar xzf ${GO_TAR}
rm ${GO_TAR}
mv go /usr/local
export GOPATH=$HOME/go
export GOROOT=/usr/local/go
export PATH=${GOROOT}/bin:${GOPATH}/bin:${PATH}

# download Oracle Instant Client
if [ "$arch" = "aarch64" ]; then
    BRANCH=arm64
else
    BRANCH=master
fi

echo && echo "-- downloading Oracle Instant Client --"
cd $WORKDIR
git clone -b $BRANCH --single-branch --depth 1 https://gitlab+deploy-token-2:Vry5iWuzRQQkyXga912D@git.qoretechnologies.com/infrastructure/oracle-instant-client.git
rm -rf oracle-instant-client/.git
mv oracle-instant-client /usr/lib/oracle
export ORACLE_INSTANT_CLIENT=/usr/lib/oracle

# build our own libssh2 1.10.0, as 1.8.0 isn't working
echo && echo "-- building libssh2 1.10.0 --"
cd $WORKDIR
SSH2_SRC=libssh2-1.10.0
wget https://www.libssh2.org/download/${SSH2_SRC}.tar.gz
tar xvf ${SSH2_SRC}.tar.gz
cd ${SSH2_SRC}
mkdir build
cd build
if [ "$arch" = "aarch64" ]; then
    ../configure --prefix=/opt --disable-static --libdir=/opt/lib/aarch64-linux-gnu --disable-examples-build
else
    ../configure --prefix=/opt --disable-static --libdir=/opt/lib/x86_64-linux-gnu --disable-examples-build
fi
make -j${MAKE_JOBS} install
if [ "$arch" = "aarch64" ]; then
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:/opt/lib/aarch64-linux-gnu/pkgconfig"
else
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:/opt/lib/x86_64-linux-gnu/pkgconfig"
fi
cd ..
rm -rf ${SSH2_SRC}

# build and install Qore
echo && echo "-- building Qore --"
cd $WORKDIR
git clone -b ${QORE_BRANCH} --single-branch --depth 1 https://github.com/qorelanguage/qore.git
cd qore
mkdir build
cd build
cmake .. -DCMAKE_BUILD_TYPE=debug -DSINGLE_COMPILATION_UNIT=1 -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}
make -j${MAKE_JOBS}
make install

# clone all modules
echo && echo "-- cloning modules --"
cd $WORKDIR
for mod in $MODULES; do
    modname="module-$mod"
    test -d $modname || git clone -b ${MODULE_BRANCH} --single-branch --depth 1 https://github.com/qorelanguage/${modname}.git
done

# build and install cmake modules
echo && echo "-- building cmake modules --"
for mod in $CMAKE_MODULES; do
    echo && echo "-- building module-$mod --"
    cd ${WORKDIR}/module-$mod
    test -d build || mkdir build
    cd build
    cmake -DCMAKE_BUILD_TYPE=debug -DCMAKE_INSTALL_PREFIX:PATH=${INSTALL_PREFIX} ..
    make -j${MAKE_JOBS}
    make install
done

# build and install autotools modules
echo "-- building autotools modules --"
for mod in $AUTO_MODULES; do
    echo && echo "-- building module-$mod --"
    cd ${WORKDIR}/module-$mod
    ./reconf.sh
    ./configure --enable-debug --prefix=${INSTALL_PREFIX} --with-qore-dir=${INSTALL_PREFIX}
    make -j${MAKE_JOBS}
    make install
done

# build Qorus and install
echo && echo "-- building Qorus --"
cd $WORKDIR/qorus
mkdir build
cd build
cmake .. -DCMAKE_BUILD_TYPE=debug
make -j${MAKE_JOBS}
make install

# prepare OMQ_DIR
mkdir -p ${OMQ_DIR}/etc.default ${OMQ_DIR}/init ${OMQ_DIR}/log ${OMQ_DIR}/releases ${OMQ_DIR}/user

cd ${WORKDIR}/qorus/docker/ubuntu
cp entrypoint.sh env.sh init.sh min_init.sh ${OMQ_DIR}/bin/
chmod 755 ${OMQ_DIR}/bin/*.sh

rm -f ${OMQ_DIR}/etc/dbparams.example ${OMQ_DIR}/etc/qorus-bash-completion.sh
rm -f ${OMQ_DIR}/templates/install.sh-system

mv ${OMQ_DIR}/etc/options.example ${OMQ_DIR}/etc/options
#echo "qorus.debug-qorus-internals: true" >> ${OMQ_DIR}/etc/options
cp -r ${OMQ_DIR}/etc/* ${OMQ_DIR}/etc.default/

# install webapp
echo && echo "-- downloading webapp --"
cd ${OMQ_DIR}
WEBAPP_PKG="qorus-webapp-${WEBAPP_BRANCH}.zip"
wget "https://hq.qoretechnologies.com/~pchalupny/ui-builds/${WEBAPP_PKG}"
unzip ${WEBAPP_PKG}
mv ${WEBAPP_BRANCH}/webapp ./
rm -rf ${WEBAPP_BRANCH} ${WEBAPP_PKG}

# install webide
echo && echo "-- downloading webide --"
cd ${OMQ_DIR}
WEBIDE_PKG="qorus-webide-${WEBAPP_BRANCH}.zip"
wget "https://hq.qoretechnologies.com/~pchalupny/ui-builds/${WEBIDE_PKG}"
unzip ${WEBIDE_PKG}
mv ${WEBAPP_BRANCH}/webide .
rm -rf ${WEBAPP_BRANCH} ${WEBIDE_PKG}

# prepare release file
cd $WORKDIR/qorus
VERSION=`./get-version.sh | sed 's/ *$//'`
LOADING_FILE="${OMQ_DIR}/releases/qorus-$VERSION.qrf"
LOAD_DATA_MODEL=`cat $OMQ_DIR/qlib/QorusVersion.qm | grep "const load_datamodel" | cut -f2 -d\" | sed 's/ *$//'`

cd ${OMQ_DIR}/system
echo "verify-load-schema ${LOAD_DATA_MODEL}" > ${LOADING_FILE}
find . -name "*.yaml" -printf "load system/%f\n" >> ${LOADING_FILE}

# prepare runit service for Qorus
mkdir -p /etc/service/qorus /etc/service/qorus-core
cp $WORKDIR/qorus/docker/ubuntu/runit_qorus_run.sh /etc/service/qorus/run
cp $WORKDIR/qorus/docker/ubuntu/runit_qorus_core_run.sh /etc/service/qorus-core/run
chmod 755 /etc/service/qorus/run /etc/service/qorus-core/run

if [ "$arch" != "aarch64" ]; then
    # download Prometheus and Grafana builds
    cd $WORKDIR
    echo "Downloading Prometheus build"
    curl -o prometheus-build.tar.gz 'https://hq.qoretechnologies.com/~appbuilds/prometheus-build.tar.gz'
    echo "Downloading Grafana build"
    curl -o grafana-build.tar.gz 'https://hq.qoretechnologies.com/~appbuilds/grafana-build.tar.gz'

    # extract the builds
    tar xzf prometheus-build.tar.gz
    tar xzf grafana-build.tar.gz

    # copy Grafana files to OMQ_DIR
    cd ${WORKDIR}/external_apps/grafana/omqdir
    cp -rf ./* ${OMQ_DIR}/

    # copy Prometheus files to OMQ_DIR
    cd ${WORKDIR}/external_apps/prometheus/omqdir
    cp -rf ./* ${OMQ_DIR}/
fi

# prepare build package
echo && echo "-- creating build package --"
cd $WORKDIR
mkdir -p /buildroot

# add Qorus to buildroot
mv /opt /buildroot/

# setup Firebird ODBC access
wget https://qoretechnologies.com/download/ubuntu-22.04-firebird-odbc-${arch}.tar.bz2
cd /buildroot
tar xvf $WORKDIR/ubuntu-22.04-firebird-odbc-${arch}.tar.bz2 --no-overwrite-dir
cd $WORKDIR

# add runit stuff
mkdir -p /buildroot/etc/service/qorus /buildroot/etc/service/qorus-core
mv /etc/service/qorus/* /buildroot/etc/service/qorus/
mv /etc/service/qorus-core/* /buildroot/etc/service/qorus-core/

# add Qore libraries to buildroot
mkdir -p /buildroot/usr/lib
rm -rf /usr/lib/oracle/sdk
mv /usr/lib/oracle /buildroot/usr/lib/

# list sizes of various build files and directories
echo && echo "-- listing size of the build --"
du -hs /buildroot

echo && echo "-- listing all build files --"
ls -R /buildroot

# cleanup packages and apt files
echo && echo "-- cleaning up apt packages and files --"
apt-get -y purge \
    netbase \
    ca-certificates \
    gnupg1 \
    wget \
    curl \
    apt-transport-https \
    unzip \
    bzip2 \
    git \
    g++ \
    make \
    automake \
    cmake \
    pkg-config \
    libtool \
    flex \
    bison \
    libmpfr-dev \
    libpcre3-dev \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libxmlsec1-dev \
    doxygen \
    libmagic-dev \
    libmariadb-dev \
    libmariadb-dev-compat \
    libaio-dev \
    unixodbc-dev \
    libldap2-dev \
    postgresql-server-dev-14 \
    uuid-dev \
    freetds-dev \
    libxml2-dev \
    libyaml-dev \
    libzmq3-dev \
    libczmq-dev \
    nodejs \
    yarn \
    python3-dev \
    libpython3.10 \
    python-is-python3 \
    openjdk-17-jdk

apt-get -y autoremove
apt-get -y clean
rm -rf /var/lib/apt/lists/*

# source /opt/qorus/bin/env.sh automatically with bash if available
mkdir -p /buildroot/root
echo "if [ -f /opt/qorus/bin/env.sh ]; then . /opt/qorus/bin/env.sh; fi" >> /buildroot/root/.bashrc

# clean up sources
echo && echo "-- cleaning up sources --"
cd $WORKDIR
rm -rf module-* qore qorus *.tar.gz external_apps
