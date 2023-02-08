#!/bin/bash

# The following script downloads sources for Qore, necessary modules, Qorus and
# required libraries, and then builds everything. After building, everything
# is moved to /buildroot directory from where it is copied to the next stage.
# Also clean up is done after this so that the stage doesn't occupy unnecessary
# space after everything is done.

# EXCLUDES: oracle, prometheus, grafana

set -e
set -x

export WORKDIR=/tmp
export INSTALL_PREFIX=/opt
export OMQ_DIR=/opt/qorus
export MAKE_JOBS=4

export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS} -Dfile.encoding=UTF8"
export JAVA_HOME=/usr/lib/jvm/default-jvm

export LD_LIBRARY_PATH=${INSTALL_PREFIX}/lib:${INSTALL_PREFIX}/lib:${LD_LIBRARY_PATH}
export PATH=${INSTALL_PREFIX}/bin:${JAVA_HOME}/bin:$PATH

export QORE_BRANCH="develop"
export MODULE_BRANCH="develop"
export WEBAPP_BRANCH="develop"

export AUTO_MODULES="sybase"
export CMAKE_MODULES_BUILDABLE="jni json linenoise magic odbc ssh2 sysconf uuid xml xmlsec yaml zmq process python mysql pgsql"
export CMAKE_MODULES="${CMAKE_MODULES_BUILDABLE} fsevent"
export MODULES="$AUTO_MODULES $CMAKE_MODULES"

# needed to install Java
mkdir -p /usr/share/man/man1 ${INSTALL_PREFIX}

echo "-- installing Qore packages --"
apk update
apk add tzdata
cp /usr/share/zoneinfo/Europe/Prague /etc/localtime
echo "Europe/Prague" >  /etc/timezone

apk --no-cache add \
    autoconf \
    automake \
    bison \
    boost-dev \
    bzip2-dev \
    cmake \
    curl \
    czmq-dev \
    doxygen \
    file \
    file-dev \
    flex \
    freetds-dev \
    g++ \
    git \
    gmp-dev \
    go \
    libaio-dev \
    libc-dev \
    libgcrypt \
    libmagic \
    libssh2-dev \
    libtool \
    libxml2-dev \
    linux-headers \
    make \
    mariadb-dev \
    mpfr-dev \
    nodejs \
    openjdk17-jdk \
    openjdk17-jre-headless \
    openldap-dev \
    openssl-dev \
    pcre-dev \
    postgresql-dev \
    python3-dev \
    unixodbc-dev \
    unzip \
    xmlsec-dev \
    yaml-dev \
    yarn

# fix for compiling the openldap module on Alpine
echo -n "INPUT ( libldap.so )" > /usr/lib/libldap_r.so

# build and install Qore
echo && echo "-- building Qore --"
cd $WORKDIR
git clone -b ${QORE_BRANCH} --single-branch --depth 1 https://github.com/qorelanguage/qore.git
cd qore
mkdir build
cd build
cmake .. -DCMAKE_BUILD_TYPE=release -DSINGLE_COMPILATION_UNIT=1 -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}
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
for mod in $CMAKE_MODULES_BUILDABLE; do
    echo && echo "-- building module-$mod --"
    cd ${WORKDIR}/module-$mod
    test -d build || mkdir build
    cd build
    cmake -DCMAKE_BUILD_TYPE=release -DCMAKE_INSTALL_PREFIX:PATH=${INSTALL_PREFIX} ..
    make -j${MAKE_JOBS}
    make install
done

# build and install autotools modules
echo "-- building autotools modules --"
for mod in $AUTO_MODULES; do
    echo && echo "-- building module-$mod --"
    cd ${WORKDIR}/module-$mod
    ./reconf.sh
    ./configure --disable-debug --prefix=${INSTALL_PREFIX} --with-qore-dir=${INSTALL_PREFIX}
    make -j${MAKE_JOBS}
    make install
done

# build Qorus and install
echo && echo "-- building Qorus --"
cd $WORKDIR/qorus
mkdir build
cd build
cmake .. -DCMAKE_BUILD_TYPE=release
make
make install

# prepare OMQ_DIR
mkdir -p ${OMQ_DIR}/etc.default ${OMQ_DIR}/init ${OMQ_DIR}/log ${OMQ_DIR}/releases ${OMQ_DIR}/user

cd ${WORKDIR}/qorus/docker/alpine
cp entrypoint.sh env.sh init.sh min_init.sh ${OMQ_DIR}/bin/
chmod 755 ${OMQ_DIR}/bin/*.sh

rm -f ${OMQ_DIR}/etc/dbparams.example ${OMQ_DIR}/etc/qorus-bash-completion.sh
rm -f ${OMQ_DIR}/templates/install.sh-system

mv ${OMQ_DIR}/etc/options.example ${OMQ_DIR}/etc/options
cp -r ${OMQ_DIR}/etc/* ${OMQ_DIR}/etc.default/

# install webapp
echo && echo "-- downloading webapp --"
cd ${OMQ_DIR}
WEBAPP_PKG="qorus-webapp-${WEBAPP_BRANCH}.zip"
wget "https://hq.qoretechnologies.com/~pchalupny/ui-builds/${WEBAPP_PKG}"
unzip ${WEBAPP_PKG}
mv ${WEBAPP_BRANCH}/webapp .
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

cd ${OMQ_DIR}
echo "verify-load-schema ${LOAD_DATA_MODEL}" > ${LOADING_FILE}
find system -name "*.yaml" -exec echo load {} >> ${LOADING_FILE} \;

# prepare runit service for Qorus
mkdir -p /etc/service/qorus /etc/service/qorus-core
cp $WORKDIR/qorus/docker/alpine/runit_qorus_run.sh /etc/service/qorus/run
cp $WORKDIR/qorus/docker/alpine/runit_qorus_core_run.sh /etc/service/qorus-core/run
chmod 755 /etc/service/qorus/run /etc/service/qorus-core/run

# prepare build package
echo && echo "-- creating build package --"
cd $WORKDIR
mkdir -p /buildroot

# add Qorus to buildroot
mv /opt /buildroot/

# add runit stuff
mkdir -p /buildroot/etc/service/qorus /buildroot/etc/service/qorus-core
mv /etc/service/qorus/* /buildroot/etc/service/qorus/
mv /etc/service/qorus-core/* /buildroot/etc/service/qorus-core/

# add Qore libraries to buildroot
mkdir -p /buildroot/usr/lib

echo && echo "-- listing all build files --"
ls -R /buildroot

echo && echo "-- listing size of the build --"
du -hs /buildroot

# cleanup packages and apk files
echo && echo "-- cleaning up apt packages and files --"
apk del \
    autoconf \
    automake \
    bison \
    boost-dev \
    bzip2-dev \
    cmake \
    curl \
    czmq-dev \
    doxygen \
    file \
    file-dev \
    flex \
    freetds-dev \
    g++ \
    git \
    gmp-dev \
    go \
    libaio-dev \
    libc-dev \
    libgcrypt \
    libmagic \
    libssh2-dev \
    libtool \
    libxml2-dev \
    linux-headers \
    make \
    mariadb-dev \
    mpfr-dev \
    nodejs \
    openjdk17-jdk \
    openldap-dev \
    openssl-dev \
    pcre-dev \
    postgresql-dev \
    python3-dev \
    unixodbc-dev \
    unzip \
    xmlsec-dev \
    yaml-dev \
    yarn

rm -rf /var/cache/apk/*

# source /opt/qorus/bin/env.sh automatically with bash if available
mkdir -p /buildroot/root
echo "if [ -f /opt/qorus/bin/env.sh ]; then . /opt/qorus/bin/env.sh; fi" >> /buildroot/root/.profile

# clean up sources
echo && echo "-- cleaning up sources --"
cd $WORKDIR
rm -rf module-* qore qorus
