#!/bin/bash

# The following script downloads sources for Qore, necessary modules, Qorus and
# required libraries, and then builds everything. Builds documentation for Qore,
# modules and Qorus.

set -e
set -x

# get CPU architecture
arch=`uname -m`

# setup QORUS_SRC_DIR env var
cwd=`pwd`
if [ "${QORUS_SRC_DIR}" = "" ]; then
    if [ -d "$cwd/qlib-qorus" ] || [ -e "$cwd/bin/qctl" ] || [ -e "$cwd/cmake/QorusMacros.cmake" ] || [ -e "$cwd/lib/qorus.ql" ]; then
        export QORUS_SRC_DIR=$cwd
    else
        export QORUS_SRC_DIR=$WORKDIR/qorus
    fi
fi

export WORKDIR=/tmp
export INSTALL_PREFIX=/usr
export QORE_INSTALL_PREFIX=$INSTALL_PREFIX
export QORE_GIT_ROOT=$WORKDIR
export OMQ_DIR=/opt/qorus
export MAKE_JOBS=4

export ORACLE_INSTANT_CLIENT=/usr/lib/oracle
export ORACLE_HOME=$ORACLE_INSTANT_CLIENT
export TNS_ADMIN=$ORACLE_INSTANT_CLIENT

export LD_LIBRARY_PATH=$ORACLE_INSTANT_CLIENT:$LD_LIBRARY_PATH

export JAVA_TOOL_OPTIONS="$JAVA_TOOL_OPTIONS -Dfile.encoding=UTF8"

if [ "$arch" = "aarch64" ]; then
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64
else
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
fi

export QORE_BRANCH="develop"
export MODULE_BRANCH="develop"

export AUTO_MODULES="sybase"
export CMAKE_MODULES="fsevent jni json linenoise magic msgpack mysql odbc openldap oracle process pgsql python ssh2 sysconf uuid xml xmlsec yaml zmq"
export MODULES="$AUTO_MODULES $CMAKE_MODULES"

# needed to install Java
mkdir -p /usr/share/man/man1

# install necessary packages for Qore
echo "-- installing Qore packages --"
apt-get -y update
export DEBIAN_FRONTEND=noninteractive
ln -fs /usr/share/zoneinfo/Europe/Prague /etc/localtime
apt-get install -y tzdata
dpkg-reconfigure --frontend noninteractive tzdata

apt-get -y install --no-install-recommends \
    netbase \
    ca-certificates \
    gnupg1 \
    wget \
    unzip \
    git \
    g++ \
    make \
    automake \
    cmake \
    equivs \
    pkg-config \
    libtool \
    flex \
    bison \
    freetds-dev \
    libmpfr-dev \
    libpcre3-dev \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libldap2-dev \
    libxmlsec1-dev \
    graphviz

# build and install fake packages to not download unnecessary dependencies
echo && echo "-- building and installing fake dependency packages --"
mkdir /pkg
cd /pkg
printf "Section: misc\nPriority: optional\nStandards-Version: 3.9.2\nVersion: \
999.0.0\nMaintainer: Qore Technologies, s.r.o <info@qoretechnologies.com>\n\
Architecture: all\nDescription: fake package to block unnecessary dependency\n" > /pkg/templ
printf '#!/bin/bash\nset -e\nset -x\n' >> /pkg/gen.sh
echo "pkgs=\"libasound2 libcups2 libdbus-1-3 libgdk-pixbuf2.0-0 libgif7 libgl1-mesa-glx libpcsclite1 libpulse0 \
adwaita-icon-theme hicolor-icon-theme\"" >> /pkg/gen.sh
printf 'for p in $pkgs; do\ncp templ $p\necho "Package: $p" >> $p\nequivs-build $p\ndone\n' >> /pkg/gen.sh
chmod +x /pkg/gen.sh
/pkg/gen.sh
dpkg -i ./*.deb
cd /
rm -rf /pkg

# install necessary packages for modules
echo && echo "-- installing module packages --"
# [trusted=yes] = temporary workaround for invalid key in opensuse network repo
echo "deb [trusted=yes] http://download.opensuse.org/repositories/network:/messaging:/zeromq:/release-stable/xUbuntu_18.04/ ./" >> /etc/apt/sources.list
wget https://download.opensuse.org/repositories/network:/messaging:/zeromq:/release-stable/xUbuntu_18.04/Release.key -O- | apt-key add

printf "APT::Get::AllowUnauthenticated \"true\";\n" > /etc/apt/apt.conf.d/99-expired-key-workaround

apt-get -y update
apt-get -y install --no-install-recommends \
    libmagic-dev \
    libmariadb-dev \
    libmariadb-dev-compat \
    openjdk-17-jdk \
    libaio-dev \
    unixodbc-dev \
    libldap2-dev \
    postgresql-server-dev-14 \
    libssh2-1-dev \
    uuid-dev \
    libxml2-dev \
    libyaml-dev \
    libzmq3-dev \
    libczmq-dev \
    python3 \
    libpython3-dev

# download and build doxygen 1.9.5
cd $WORKDIR
wget https://www.doxygen.nl/files/doxygen-1.9.5.src.tar.gz
tar xvf doxygen-1.9.5.src.tar.gz
cd doxygen-1.9.5
mkdir build
cd build
cmake .. -DCMAKE_INSTALL_PREFIX=/usr
make -j${MAKE_JOBS} install

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

# build and install Qore
echo && echo "-- building Qore --"
cd $WORKDIR
git clone -b ${QORE_BRANCH} --single-branch --depth 1 https://github.com/qorelanguage/qore.git
cd qore
mkdir build
cd build
# make a debug build to save time
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
for mod in ${CMAKE_MODULES}; do
    echo && echo "-- building module-$mod --"
    cd ${WORKDIR}/module-$mod
    test -d build || mkdir build
    cd build
    cmake -DCMAKE_INSTALL_PREFIX:PATH=${INSTALL_PREFIX} ..
    make -j${MAKE_JOBS}
    make install
    make docs
done

# build and install autotools modules
echo "-- building autotools modules --"
for mod in ${AUTO_MODULES}; do
    echo && echo "-- building module-$mod --"
    cd ${WORKDIR}/module-$mod
    ./reconf.sh
    ./configure --prefix=${INSTALL_PREFIX} --with-qore-dir=/usr
    make -j${MAKE_JOBS}
    make install
    make html
done

# build Qore docs
echo "-- building Qore documentation --"
cd $WORKDIR/qore/build
make docs

# build Qorus and install
echo && echo "-- building Qorus --"
cd ${QORUS_SRC_DIR}
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j${MAKE_JOBS}
make install

echo && echo "-- building Qorus documentation --"
VERBOSE=1 make create-qore-doc-link
make docs
