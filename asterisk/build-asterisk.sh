#!/bin/bash
PROGNAME=$(basename $0)

if test -z ${ASTERISK_VERSION}; then
    echo "${PROGNAME}: ASTERISK_VERSION required" >&2
    exit 1
fi

set -ex

useradd --system asterisk

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --no-install-suggests \
    autoconf \
    binutils-dev \
    build-essential \
    ca-certificates \
    curl \
    file \
    gnupg2 \
    iproute2 \
    libcurl4-openssl-dev \
    libedit-dev \
    libgsm1-dev \
    libogg-dev \
    libpopt-dev \
    libresample1-dev \
    libspandsp-dev \
    libspeex-dev \
    libspeexdsp-dev \
    libsqlite3-dev \
    libsrtp0-dev \
    libssl-dev \
    libvorbis-dev \
    libxml2-dev \
    libxslt1-dev \
    procps \
    portaudio19-dev \
    sudo \
    unixodbc \
    unixodbc-bin \
    unixodbc-dev \
    odbcinst \
    odbc-postgresql \
    odbcinst1debian2 \
    uuid \
    uuid-dev \
    xmlstarlet

set +e
# Note, location and names of drivers (Driver and Setup settings) could be different
rm /etc/odbcinst.ini
cat <<EOT > /etc/odbcinst.ini
[PostgreSQL ANSI]
Description=PostgreSQL ODBC driver (ANSI version)
Driver=psqlodbca.so
Setup=libodbcpsqlS.so
Debug=0
CommLog=1
UsageCount=1
Threading=10

[PostgreSQL Unicode]
Description=PostgreSQL ODBC driver (Unicode version)
Driver=psqlodbcw.so
Setup=libodbcpsqlS.so
Debug=0
CommLog=1
UsageCount=1
Threading=10
EOT
odbcinst -q -d

rm /etc/odbc.ini
cat <<EOT > /etc/odbc.ini
[asterisk]
Description           = ODBC Testing
Driver                = PostgreSQL ANSI
Trace                 = No
TraceFile             = sql.log
Database              = postgres
Servername            = __POSTGRES_ASTERISK_HOST__
UserName              = postgres
Password              = __POSTGRES_ASTERISK_PASSWORD__
Port                  = 5432
ReadOnly              = No
RowVersioning         = No
ShowSystemTables      = No
ShowOidColumn         = No
FakeOidIndex          = No
ConnSettings          =
EOT
odbcinst -q -s
set -e

# For development images:
# sngrep and wscat (requires npm)
curl -sL http://packages.irontec.com/public.key | apt-key add -
echo "deb http://packages.irontec.com/debian xenial main" > /etc/apt/sources.list.d/sngrep.list

curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -

DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --no-install-suggests \
  nodejs \
  sngrep

npm install -g wscat

apt-get purge -y --auto-remove
rm -rf /var/lib/apt/lists/*

mkdir -p /usr/src/asterisk
cd /usr/src/asterisk

curl -vsL http://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-${ASTERISK_VERSION}.tar.gz | tar --strip-components 1 -xz || \
curl -vsL http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VERSION}.tar.gz | tar --strip-components 1 -xz || \
curl -vsL http://downloads.asterisk.org/pub/telephony/asterisk/old-releases/asterisk-${ASTERISK_VERSION}.tar.gz | tar --strip-components 1 -xz

# 1.5 jobs per core works out okay
: ${JOBS:=$(( $(nproc) + $(nproc) / 2 ))}

./configure --with-resample \
            --with-pjproject-bundled \
            --with-jansson-bundled
make menuselect/menuselect menuselect-tree menuselect.makeopts

# disable BUILD_NATIVE to avoid platform issues
menuselect/menuselect --disable BUILD_NATIVE menuselect.makeopts

# enable good things
menuselect/menuselect --enable BETTER_BACKTRACES menuselect.makeopts

# # Codecs
# menuselect/menuselect --enable codec_opus menuselect.makeopts
# menuselect/menuselect --enable codec_silk menuselect.makeopts

# we don't need any sounds in docker, they will be mounted as volume
menuselect/menuselect --disable-category MENUSELECT_CORE_SOUNDS
menuselect/menuselect --disable-category MENUSELECT_MOH
menuselect/menuselect --disable-category MENUSELECT_EXTRA_SOUNDS


for i in CORE-SOUNDS-EN MOH-OPSOUND EXTRA-SOUNDS-EN; do
    for j in ULAW ALAW G722 GSM SLN16; do
        # --enable or --disable to download (not download) more sounds
        menuselect/menuselect --disable $i-$j menuselect.makeopts
    done
done

make -j ${JOBS} all
make install

# copy default configs
# cp /usr/src/asterisk/configs/basic-pbx/*.conf /etc/asterisk/
make samples

# set runuser and rungroup
sed -i -E 's/^;(run)(user|group)/\1\2/' /etc/asterisk/asterisk.conf

# Install opus, for some reason menuselect option above does not working
mkdir -p /usr/src/codecs/opus \
  && cd /usr/src/codecs/opus \
  && curl -vsL http://downloads.digium.com/pub/telephony/codec_opus/${OPUS_CODEC}.tar.gz | tar --strip-components 1 -xz \
  && cp *.so /usr/lib/asterisk/modules/ \
  && cp codec_opus_config-en_US.xml /var/lib/asterisk/documentation/

mkdir -p /etc/asterisk/ \
         /var/spool/asterisk/fax

chown -R asterisk:asterisk /etc/asterisk \
                           /var/*/asterisk \
                           /usr/*/asterisk
chmod -R 750 /var/spool/asterisk

cd /
rm -rf /usr/src/asterisk \
       /usr/src/codecs

# # remove *-dev packages
# devpackages=`dpkg -l|grep '\-dev'|awk '{print $2}'|xargs`
# SUDO_FORCE_REMOVE=yes DEBIAN_FRONTEND=noninteractive apt-get --yes purge \
#   autoconf \
#   build-essential \
#   bzip2 \
#   cpp \
#   gnupg2 \
#   m4 \
#   make \
#   patch \
#   perl \
#   perl-modules \
#   pkg-config \
#   sudo \
#   xz-utils \
#   ${devpackages}
rm -rf /var/lib/apt/lists/*

exec rm -f /build-asterisk.sh
