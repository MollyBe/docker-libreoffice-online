FROM tiredofit/debian:buster as builder
LABEL maintainer="Dave Conroy (dave at tiredofit dot ca)"

### Buildtime arguments
ARG LIBREOFFICE_BRANCH
ARG LIBREOFFICE_VERSION
ARG LIBREOFFICE_REPO_URL
ARG LOOL_BRANCH
ARG LOOL_VERSION
ARG LOOL_REPO_URL
ARG MAX_CONNECTIONS
ARG MAX_DOCUMENTS

### Environment Variables
ENV LIBREOFFICE_BRANCH=${LIBREOFFICE_BRANCH:-"master"} \
    LIBREOFFICE_VERSION=${LIBREOFFICE_VERSION:-"cp-6.4-23"} \
    LIBREOFFICE_REPO_URL=${LIBREOFFICE_REPO_URL:-"https://github.com/LibreOffice/core"} \
    #
    LOOL_BRANCH=${LOOL_BRANCH:-"master"} \
    LOOL_VERSION=${LOOL_VERSION:-"cp-6.4.6-2"} \
    LOOL_REPO_URL=${LOOL_REPO_URL:-"https://github.com/CollaboraOnline/online"} \
    #
    MAX_CONNECTIONS=${MAX_CONNECTIONS:-"5000"} \
    ## Uses Approximately 20mb per document open
    MAX_DOCUMENTS=${MAX_DOCUMENTS:-"5000"}

### Get Updates
RUN set -x && \
### Add Repositories
    apt-get update && \
    apt-get -o Dpkg::Options::="--force-confold" upgrade -y && \
    echo "deb-src http://deb.debian.org/debian buster main" >> /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian buster contrib" >> /etc/apt/sources.list && \
    curl -sL https://deb.nodesource.com/setup_10.x | bash - && \
    \
### Setup Distribution
    echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections && \
    \
    mkdir -p /home/lool && \
    useradd lool -G sudo && \
    chown lool:lool /home/lool -R && \
    \
    BUILD_DEPS=' \
            adduser \
            automake \
            build-essential \
            cpio \
            default-jre \
            devscripts \
            fontconfig \
            g++ \
            git \
            inotify-tools \
            libcap-dev \
            libcap2-bin \
            libcppunit-dev \
            libghc-zlib-dev \
            libkrb5-dev \
            libpam-dev \
            libpam0g-dev \
            libpng16-16 \
            libpoco-dev \
            libssl-dev \
            libtool \
            libubsan1 \
            locales-all \
            m4 \
            nasm \
            nodejs \
            openssl \
            pkg-config \
            procps \
            python3-lxml \
            python3-polib \
            python-polib \
            sudo \
            translate-toolkit \
            ttf-mscorefonts-installer \
            wget \
    ' && \
    ## Add Build Dependencies
    apt-get install -y \
            ${BUILD_DEPS} \
            && \
    \
    apt-get build-dep -y \
            libreoffice \
            && \
    \
### Build Fetch LibreOffice - This will take a while..
    git clone -b ${LIBREOFFICE_BRANCH} ${LIBREOFFICE_REPO_URL} /usr/src/libreoffice-core && \
    cd /usr/src/libreoffice-core && \
    git checkout ${LIBREOFFICE_VERSION} && \
    echo "--prefix=/opt/libreoffice" >> /usr/src/libreoffice-core/distro-configs/LibreOfficeOnline.conf  && \
    ./autogen.sh --with-distro="LibreOfficeOnline" && \
    chown -R lool /usr/src/libreoffice-core && \
    sudo -u lool make fetch && \
    sudo -u lool make -j$(nproc) build-nocheck && \
    mkdir -p /opt/libreoffice && \
    chown -R lool /opt/libreoffice && \
    sudo -u lool make install && \
    cp -R /usr/src/libreoffice-core/instdir/* /opt/libreoffice/ && \
    \
    ### Build LibreOffice Online (Not as long as above)
    git clone -b ${LOOL_BRANCH} ${LOOL_REPO_URL} /usr/src/libreoffice-online && \
    cd /usr/src/libreoffice-online && \
    git checkout ${LOOL_VERSION} && \
    ./autogen.sh && \
    ./configure --enable-silent-rules \
                --with-lokit-path="/usr/src/libreoffice-core/include" \
                --with-lo-path=/opt/libreoffice \
                --with-max-connections=${MAX_CONNECTIONS} \
                --with-max-documents=${MAX_DOCUMENTS} \
                --with-logfile=/var/log/lool/lool.log \
                --prefix=/opt/lool \
                --sysconfdir=/etc \
                --localstatedir=/var \
                && \
    \
    ( scripts/locorestrings.py /usr/src/libreoffice-online /usr/src/libreoffice-core/translations ) && \
    ( scripts/unocommands.py --update /usr/src/libreoffice-online /usr/src/libreoffice-core ) && \
    ( scripts/unocommands.py --translate /usr/src/libreoffice-online /usr/src/libreoffice-core/translations ) && \
    make -j$(nproc) && \
    mkdir -p /opt/lool && \
    chown -R lool /opt/lool && \
    cp -R loolwsd.xml /opt/lool/ && \
    cp -R loolkitconfig.xcu /opt/lool && \
    make install && \
    \
    ### Cleanup
    cd / && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /usr/src/* && \
    rm -rf /usr/share/doc && \
    rm -rf /usr/share/man && \
    rm -rf /usr/share/locale && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /var/log/*

FROM tiredofit/debian:buster
LABEL maintainer="Dave Conroy (dave at tiredofit dot ca)"

### Set Defaults
ENV ADMIN_USER=admin \
    ADMIN_PASS=libreoffice \
    LOG_LEVEL=warning \
    DICTIONARIES="en_GB en_US" \
    ENABLE_SMTP=false \
    PYTHONWARNINGS=ignore

### Grab Compiled Assets from builder image
COPY --from=builder /opt/ /opt/

### Install Dependencies
RUN set -x && \
    adduser --quiet --system --group --home /opt/lool lool && \
    \
### Add Repositories
    echo "deb http://deb.debian.org/debian buster contrib" >> /etc/apt/sources.list && \
    curl -sL https://deb.nodesource.com/setup_10.x | bash - && \
    \
    echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections && \
    apt-get -o Dpkg::Options::="--force-confold" upgrade -y && \
    apt-get install -y\
             apt-transport-https \
             cpio \
             fontconfig \
             fonts-droid-fallback \
             fonts-hack \
             fonts-liberation \
             fonts-noto-cjk \
             fonts-wqy-microhei \
             fonts-wqy-zenhei \
             fonts-ocr-a \
             fonts-ocr-b \
             fonts-open-sans \
             hunspell \
             hunspell-en-ca \
             hunspell-en-gb \
             hunspell-en-us \
             inotify-tools \
             libcap2-bin \
             libcups2 \
             libfontconfig1 \
             libfreetype6 \
             libgl1-mesa-glx \
             libpam0g \
             libpng16-16 \
             libpoco-dev \
             libsm6 \
             libubsan0 \
             libubsan1 \
             libxcb-render0 \
             libxcb-shm0 \
             libxinerama1 \
             libxrender1 \
             locales \
             locales-all \
             openssl \
             openssh-client \
             procps \
             python3-requests \
             python3-websocket \
             ttf-mscorefonts-installer \
             && \
    \
### Setup Directories and Permissions
    mkdir -p /etc/loolwsd && \
    mv /opt/lool/loolwsd.xml /etc/loolwsd/ && \
    mv /opt/lool/loolkitconfig.xcu /etc/loolwsd/ && \
    chown -R lool /etc/loolwsd && \
    mkdir -p /opt/lool/child-roots && \
    chown -R lool /opt/* && \
    mkdir -p /var/cache/loolwsd && \
    chown -R lool /var/cache/loolwsd && \
    setcap cap_fowner,cap_chown,cap_mknod,cap_sys_chroot=ep /opt/lool/bin/loolforkit && \
    mkdir -p /usr/share/hunspell && \
    mkdir -p /usr/share/hyphen && \
    mkdir -p /usr/share/mythes && \
    \
### Setup LibreOffice Online Jails
    sudo -u lool /opt/lool/bin/loolwsd-systemplate-setup /opt/lool/systemplate /opt/libreoffice && \
    \
    apt-get autoremove -y && \
    apt-get clean && \
    \
    rm -rf /usr/src/* && \
    rm -rf /usr/share/doc && \
    rm -rf /usr/share/man && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /var/log/* && \
    rm -rf /tmp/*

### Networking Configuration
EXPOSE 9980

### Assets
ADD install /
