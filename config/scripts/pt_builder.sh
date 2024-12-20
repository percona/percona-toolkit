#!/usr/bin/env bash

shell_quote_string() {
  echo "$1" | sed -e 's,\([^a-zA-Z0-9/_.=-]\),\\\1,g'
}

usage () {
    cat <<EOF
Usage: $0 [OPTIONS]
    The following options may be given :
        --builddir=DIR      Absolute path to the dir where all actions will be performed
        --get_sources       Source will be downloaded from github
        --build_src_rpm     If it is set - src rpm will be built
        --build_src_deb  If it is set - source deb package will be built
        --build_rpm         If it is set - rpm will be built
        --build_deb         If it is set - deb will be built
        --build_tarball     If it is set - tarball will be built
        --install_deps      Install build dependencies(root privileges are required)
        --branch            Branch for build
        --repo              Repo for build
        --help) usage ;;
Example $0 --builddir=/tmp/BUILD --get_sources=1 --build_src_rpm=1 --build_rpm=1
EOF
        exit 1
}

append_arg_to_args () {
  args="$args "$(shell_quote_string "$1")
}

switch_to_vault_repo() {
    sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
    sed -i 's|#\s*baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
}

parse_arguments() {
    pick_args=
    if test "$1" = PICK-ARGS-FROM-ARGV
    then
        pick_args=1
        shift
    fi

    for arg do
        val=$(echo "$arg" | sed -e 's;^--[^=]*=;;')
        case "$arg" in
            --builddir=*) WORKDIR="$val" ;;
            --build_src_rpm=*) SRPM="$val" ;;
            --build_src_deb=*) SDEB="$val" ;;
            --build_rpm=*) RPM="$val" ;;
            --build_deb=*) DEB="$val" ;;
            --build_tarball=*) BTARBALL="$val" ;;
            --get_sources=*) SOURCE="$val" ;;
            --version=*) VERSION="$val" ;;
            --repo=*) GIT_REPO="$val" ;;
            --branch=*) GIT_BRANCH="$val" ;;
            --install_deps=*) INSTALL="$val" ;;
            --help) usage ;;
            *)
              if test -n "$pick_args"
              then
                  append_arg_to_args "$arg"
              fi
              ;;
        esac
    done
}

check_workdir(){
    if [ "x$WORKDIR" = "x$CURDIR" ]
    then
        echo >&2 "Current directory cannot be used for building!"
        exit 1
    else
        if ! test -d "$WORKDIR"
	then
            echo >&2 "$WORKDIR is not a directory."
            exit 1
        fi
    fi
    return
}

add_percona_yum_repo(){
    yum -y install https://repo.percona.com/yum/percona-release-latest.noarch.rpm
    percona-release disable all
    percona-release enable ppg-12.20 testing
    return
}

get_sources(){
    cd "${WORKDIR}"
    if [ "${SOURCE}" = 0 ]
    then
        echo "Sources will not be downloaded"
        return 0
    fi
    PRODUCT=percona-toolkit
    echo "PRODUCT=${PRODUCT}" > percona-toolkit.properties
    PRODUCT_FULL=${PRODUCT}-${VERSION}
    echo "VERSION=${VERSION}" >> percona-toolkit.properties
    echo "GIT_VERSION=${GIT_VERSION}" >> percona-toolkit.properties
    echo "REVISION=${REVISION}" >> percona-toolkit.properties
    echo "RPM_RELEASE=${RPM_RELEASE}" >> percona-toolkit.properties
    echo "DEB_RELEASE=${DEB_RELEASE}" >> percona-toolkit.properties
    echo "GIT_REPO=${GIT_REPO}" >> percona-toolkit.properties
    BRANCH_NAME="${GIT_BRANCH}"
    echo "BRANCH_NAME=${BRANCH_NAME}" >> percona-toolkit.properties
    echo "PRODUCT_FULL=${PRODUCT_FULL}" >> percona-toolkit.properties
    echo "BUILD_NUMBER=${BUILD_NUMBER}" >> percona-toolkit.properties
    echo "BUILD_ID=${BUILD_ID}" >> percona-toolkit.properties
    echo "GIT_BRANCH=${GIT_BRANCH}" >> percona-toolkit.properties
    rm -rf percona-toolkit*
    git clone ${GIT_REPO} $PRODUCT-$VERSION
    cd $PRODUCT-$VERSION
    git fetch origin
    if [ ! -z ${BRANCH_NAME} ]; then
        git checkout ${BRANCH_NAME}
    fi
    sed -i 's:> 9:> 8:g' config/rpm/percona-toolkit.spec
    sed -i 's:perl(English):perl-English perl-sigtrap perl-Sys-Hostname perl-FindBin:g' config/rpm/percona-toolkit.spec
    REVISION=$(git rev-parse --short HEAD)
    cd ../
    if [ -z "${DESTINATION}" ]; then
        export DESTINATION=experimental
    fi
    echo "REVISION=${REVISION}" >> ${WORKDIR}/percona-toolkit.properties
    echo "DESTINATION=${DESTINATION}" >> percona-toolkit.properties
    echo "UPLOAD=UPLOAD/${DESTINATION}/BUILDS/${PRODUCT}/${PRODUCT_FULL}/${BRANCH_NAME}/${REVISION}/${BUILD_ID}" >> percona-toolkit.properties
    cd ${PRODUCT_FULL}
    rm -fr debian rpm
    cp -ap config/deb/ ./debian
    cp -ap config/rpm/ ./rpm
    cd ${WORKDIR}
    #
    source percona-toolkit.properties
    #

    tar --owner=0 --group=0 -czf ${PRODUCT}-${VERSION}.tar.gz ${PRODUCT_FULL}
    mkdir $WORKDIR/source_tarball
    mkdir $CURDIR/source_tarball
    cp ${PRODUCT_FULL}.tar.gz $WORKDIR/source_tarball
    cp ${PRODUCT_FULL}.tar.gz $CURDIR/source_tarball
    cd $CURDIR
    return
}

get_system(){
    if [ -f /etc/redhat-release ]; then
        RHEL=$(rpm --eval %rhel)
        ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
        OS_NAME="el$RHEL"
        OS="rpm"
    else
        ARCH=$(uname -m)
        OS_NAME="$(lsb_release -sc)"
        OS="deb"
    fi
    return
}

install_go() {
    #wget --no-check-certificate http://jenkins.percona.com/downloads/golang/go1.9.4.linux-amd64.tar.gz -O /tmp/golang1.9.4.tar.gz
    #tar --transform=s,go,go1.9, -zxf /tmp/golang1.9.4.tar.gz
    #rm -rf /usr/local/go /usr/local/go1.8 /usr/local/go1.9
    #mv go1.9 /usr/local/
    #ln -s /usr/local/go1.9 /usr/local/go
    GO_VERSION=1.23.4
    if [ x"$ARCH" = "xx86_64" ]; then
      GO_ARCH="amd64"
    elif [ x"$ARCH" = "xaarch64" ]; then
      GO_ARCH="arm64"
    fi
    wget --progress=dot:giga https://dl.google.com/go/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz -O /tmp/golang.tar.gz
    tar -C /usr/local -xzf /tmp/golang.tar.gz
    update-alternatives --install "/usr/bin/go" "go" "/usr/local/go/bin/go" 0
    update-alternatives --set go /usr/local/go/bin/go
    update-alternatives --install "/usr/bin/gofmt" "gofmt" "/usr/local/go/bin/gofmt" 0
    update-alternatives --set gofmt /usr/local/go/bin/gofmt
    rm /tmp/golang.tar.gz
}

update_go() {
    cd $WORKDIR
    mkdir -p go/src/github.com/percona
    cd go/
    export GOROOT="/usr/local/go/"
    export GOPATH=$(pwd)
    export PATH="/usr/local/go/bin:$PATH:$GOPATH"
    export GOBINPATH="/usr/local/go/bin"
    cd src/github.com/percona
    cp -r $WORKDIR/$PRODUCT_FULL .
    mv ${PRODUCT_FULL} ${PRODUCT}
    cd ${PRODUCT}
    go get -u github.com/golang/dep/cmd/dep
    go install ./...
    if [ x"$ARCH" = "xx86_64" ]; then
      GO_ARCH="amd64"
    elif [ x"$ARCH" = "xaarch64" ]; then
      GO_ARCH="arm64"
    fi
    wget https://github.com/Masterminds/glide/releases/download/v0.13.3/glide-v0.13.3-linux-${GO_ARCH}.tar.gz
    tar -xvzf glide-v0.13.3-linux-${GO_ARCH}.tar.gz
    cp -p linux-${GO_ARCH}/glide /usr/local/go/bin
    go get github.com/pkg/errors
    wget --no-check-certificate https://github.com/golang/dep/releases/download/v0.5.4/dep-linux-${GO_ARCH}
    mv dep-linux-${GO_ARCH} /usr/local/go/bin/dep
    go install github.com/pkg/errors
}

install_deps() {
    if [ $INSTALL = 0 ]
    then
        echo "Dependencies will not be installed"
        return;
    fi
    if [ $( id -u ) -ne 0 ]
    then
        echo "It is not possible to instal dependencies. Please run as root"
        exit 1
    fi
    CURPLACE=$(pwd)

    if [ "x$OS" = "xrpm" ]; then
      if [ "x${RHEL}" = "x7" ]; then
          switch_to_vault_repo
      fi
      yum -y install wget git which tar
      add_percona_yum_repo
#      wget http://jenkins.percona.com/yum-repo/percona-dev.repo
#      mv -f percona-dev.repo /etc/yum.repos.d/
      yum clean all
      yum -y install curl epel-release
      RHEL=$(rpm --eval %rhel)
      yum -y install wget tar findutils coreutils rpm-build perl-ExtUtils-MakeMaker make perl-DBD-MySQL
      install_go
    else
      apt-get -y update
      apt-get -y install curl wget git tar lsb-release
      export DEBIAN_VERSION=$(lsb_release -sc)
      export ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
      apt-get -y install gnupg2
      apt-get update || true
      ENV export DEBIAN_FRONTEND=noninteractive
      apt-get update
      if [ $DEBIAN_VERSION = buster ]; then
          apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0E98404D386FA1D9
          apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 6ED0E7B82643E131
          until DEBIAN_FRONTEND=noninteractive apt-get update --allow-releaseinfo-change; do
              echo "waiting"
              sleep 1
          done
      fi
      if [ $DEBIAN_VERSION = bionic -o $DEBIAN_VERSION = focal -o $DEBIAN_VERSION = bullseye -o $DEBIAN_VERSION = buster -o $DEBIAN_VERSION = bookworm -o $DEBIAN_VERSION = jammy -o $DEBIAN_VERSION = xenial -o $DEBIAN_VERSION = noble ]; then
          until apt-get update; do
              echo "waiting"
              sleep 1
          done
          DEBIAN_FRONTEND=noninteractive apt-get update
          until DEBIAN_FRONTEND=noninteractive apt-get -y install build-essential devscripts debconf debhelper perl; do
              echo "waiting"
              sleep 1
          done
      fi
      install_go
      #update_pat
    fi
    return;
}

get_tar(){
    TARBALL=$1
    TARFILE=$(basename $(find $WORKDIR/$TARBALL -name 'percona-toolkit*.tar.gz' | sort | tail -n1))
    if [ -z $TARFILE ]
    then
        TARFILE=$(basename $(find $CURDIR/$TARBALL -name 'percona-toolkit*.tar.gz' | sort | tail -n1))
        if [ -z $TARFILE ]
        then
            echo "There is no $TARBALL for build"
            exit 1
        else
            cp $CURDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
        fi
    else
        cp $WORKDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
    fi
    return
}

get_deb_sources(){
    param=$1
    echo $param
    FILE=$(basename $(find $WORKDIR/source_deb -name "percona-toolkit*.$param" | sort | tail -n1))
    if [ -z $FILE ]
    then
        FILE=$(basename $(find $CURDIR/source_deb -name "percona-toolkit*.$param" | sort | tail -n1))
        if [ -z $FILE ]
        then
            echo "There is no sources for build"
            exit 1
        else
            cp $CURDIR/source_deb/$FILE $WORKDIR/
        fi
    else
        cp $WORKDIR/source_deb/$FILE $WORKDIR/
    fi
    return
}

build_srpm(){
    if [ $SRPM = 0 ]
    then
        echo "SRC RPM will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" ]
    then
        echo "It is not possible to build src rpm here"
        exit 1
    fi
    cd $WORKDIR
    get_tar "source_tarball"
    rm -fr rpmbuild
    #ls | grep -v tar.gz | xargs rm -rf
    TARFILE=$(find . -name 'percona-toolkit-*.tar.gz' | sort | tail -n1)
    SRC_DIR=${TARFILE%.tar.gz}
    tar xvf ${TARFILE}
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    tar vxzf ${WORKDIR}/${TARFILE} --wildcards '*/rpm' --strip=1
    #
    cp -av rpm/* rpmbuild/SOURCES
    cp -av rpmbuild/SOURCES/percona-toolkit.spec rpmbuild/SPECS
    cd ${WORKDIR}/rpmbuild/SPECS
    echo '%undefine _missing_build_ids_terminate_build' | cat - percona-toolkit.spec > pt.spec && mv pt.spec percona-toolkit.spec
    echo '%define debug_package %{nil}' | cat - percona-toolkit.spec > pt.spec && mv pt.spec percona-toolkit.spec
    if [ x"$ARCH" = "xaarch64" ]; then
	sed -i "s/@@ARCHITECTURE@@/aarch64/" percona-toolkit.spec
    else
	sed -i "s/@@ARCHITECTURE@@/x86_64/" percona-toolkit.spec
    fi

    cd ${WORKDIR}/${PRODUCT_FULL}
    rm -rf bin/govendor
    rm -rf bin/glide
    cd ../
    tar czf ${TARFILE} ${PRODUCT_FULL}

   # wget --no-check-certificate https://download.osgeo.org/postgis/docs/postgis-3.3.1.pdf
    #wget --no-check-certificate https://www.postgresql.org/files/documentation/pdf/12/postgresql-12-A4.pdf
    cd ${WORKDIR}
    #
    mv -fv ${TARFILE} ${WORKDIR}/rpmbuild/SOURCES
   # if [ -f /opt/rh/devtoolset-7/enable ]; then
   #     source /opt/rh/devtoolset-7/enable
   #     source /opt/rh/llvm-toolset-7/enable
   # fi
    rpmbuild -bs --define "_topdir ${WORKDIR}/rpmbuild" --define "version $VERSION" --define "release $RPM_RELEASE" --define "dist .generic" rpmbuild/SPECS/percona-toolkit.spec

    mkdir -p ${WORKDIR}/srpm
    mkdir -p ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${WORKDIR}/srpm
    return
}

build_rpm(){
    if [ $RPM = 0 ]
    then
        echo "RPM will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" ]
    then
        echo "It is not possible to build rpm here"
        exit 1
    fi
    SRC_RPM=$(basename $(find $WORKDIR/srpm -name 'percona-toolkit*.src.rpm' | sort | tail -n1))
    if [ -z $SRC_RPM ]
    then
        SRC_RPM=$(basename $(find $CURDIR/srpm -name 'percona-toolkit*.src.rpm' | sort | tail -n1))
        if [ -z $SRC_RPM ]
        then
            echo "There is no src rpm for build"
            echo "You can create it using key --build_src_rpm=1"
            exit 1
        else
            cp $CURDIR/srpm/$SRC_RPM $WORKDIR
        fi
    else
        cp $WORKDIR/srpm/$SRC_RPM $WORKDIR
    fi
    cd $WORKDIR
    rm -fr rpmbuild
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    cp $SRC_RPM rpmbuild/SRPMS/
    cd $WORKDIR
    RHEL=$(rpm --eval %rhel)
    ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
    echo "RHEL=${RHEL}" >> percona-toolkit.properties
    echo "ARCH=${ARCH}" >> percona-toolkit.properties
    rpmbuild --target=x86_64 --define "version $VERSION" --define "VERSION $VERSION" --define "dist .el${RHEL}" --define "release $RPM_RELEASE.el${RHEL}" --define "_topdir ${WORKDIR}/rpmbuild" --rebuild rpmbuild/SRPMS/${SRC_RPM}

    return_code=$?
    if [ $return_code != 0 ]; then
        exit $return_code
    fi
    mkdir -p ${WORKDIR}/rpm
    mkdir -p ${CURDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${WORKDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${CURDIR}/rpm
}

build_source_deb(){
    if [ $SDEB = 0 ]
    then
        echo "source deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrpm" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    get_tar "source_tarball"
    rm -f *.dsc *.orig.tar.gz *.debian.tar.gz *.changes
    #
    TARFILE=$(basename $(find . -name 'percona-toolkit-*.tar.gz' | sort | tail -n1))
    DEBIAN=$(lsb_release -sc)
    ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
    tar zxf ${TARFILE}
    BUILDDIR=${TARFILE%.tar.gz}
    mv ${TARFILE} ${PRODUCT}_${VERSION}.orig.tar.gz
    update_go
    cd ${WORKDIR}/${BUILDDIR}
    if [ x"$ARCH" = "xaarch64" ]; then
	sed -i 's/@@ARCHITECTURE@@/arm64/' debian/control
    else
	sed -i 's/@@ARCHITECTURE@@/amd64/' debian/control
    fi
    cd debian
    echo "${PRODUCT} (${VERSION}) unstable; urgency=low" > changelog
    echo "  * Initial Release." >> changelog
    echo " -- Percona Toolkit Developers <toolkit-dev@percona.com>  $(date -R)" >> changelog
    echo "override_dh_builddeb:" >> rules
    echo "	dh_builddeb -- -Zgzip" >> rules
    cd ../
    dch -D unstable --force-distribution -v "${VERSION}-${DEB_RELEASE}" "Update to new upstream release Percona-Toolkit ${VERSION}-${DEB_RELEASE}"
    dpkg-buildpackage -S
    cd ../
    mkdir -p $WORKDIR/source_deb
    mkdir -p $CURDIR/source_deb
    #cp *.tar.xz* $WORKDIR/source_deb
    cp *_source.changes $WORKDIR/source_deb
    cp *.dsc $WORKDIR/source_deb
    cp *.orig.tar.gz $WORKDIR/source_deb
    cp *.diff.gz $WORKDIR/source_deb
   # cp *.tar.xz* $CURDIR/source_deb
    cp *_source.changes $CURDIR/source_deb
    cp *.dsc $CURDIR/source_deb
    cp *.orig.tar.gz $CURDIR/source_deb
    cp *.diff.gz $CURDIR/source_deb
}

build_tarball(){
    if [ $BTARBALL = 0 ]
    then
        echo "Binary tarball will not be created"
        return;
    fi
    export DEBIAN_VERSION=$(lsb_release -sc)
    export BUILD_GO=1
    export QUIET=1
    export UPDATE=0
    export CHECK=0
    cd $WORKDIR
    mkdir TARGET
    get_tar "source_tarball"
    TARBALL=$(find . -type f -name 'percona-toolkit*.tar.gz')
    #VERSION_TMP=$(echo ${TARBALL}| awk -F '-' '{print $2}')
   # echo $VERSION_TMP
   # VERSION=${VERSION_TMP%.tar.gz}
   # DIRNAME=${NAME}-${VERSION}
    tar xzf ${TARBALL}
    update_go
    cd ${WORKDIR}/go/src/github.com/percona/${PRODUCT}
    sed -i 's:make $OS_ARCH:VERSION=$VERSION make linux-amd64:' util/build-packages
    bash -x util/build-packages ${VERSION} docs/release_notes.rst
    cp release/${PRODUCT}-${VERSION}.tar.gz ${WORKDIR}/${PRODUCT}-${VERSION}_x86_64.tar.gz
    cd ${WORKDIR}
#    rm -rf `ls | grep -v x86_64.tar.gz| grep -v percona-toolkit.properties`
    mkdir -p $CURDIR/tarball
    mkdir -p $WORKDIR/tarball
    cp $WORKDIR/*x86_64*tar.gz $WORKDIR/tarball
    cp $WORKDIR/*x86_64*tar.gz $CURDIR/tarball
}

build_deb(){
    if [ $DEB = 0 ]
    then
        echo "source deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrmp" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    for file in 'dsc' 'orig.tar.gz' 'changes'
    do
        get_deb_sources $file
    done
    cd $WORKDIR
    tar xvf ${PRODUCT}_${VERSION}.orig.tar.gz
    rm -fv *.deb
    #
    export DEBIAN_VERSION=$(lsb_release -sc)
    export DEBIAN=$(lsb_release -sc)
    export ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
    export DIRNAME=$(echo ${DSC%.dsc} | sed -e 's:_:-:g')
    #export VERSION=$(echo ${DSC%.dsc} | awk -F'_' '{print $2}')
    #
    echo "ARCH=${ARCH}" >> percona-toolkit.properties
    echo "DEBIAN_VERSION=${DEBIAN_VERSION}" >> percona-toolkit.properties
    echo VERSION=${VERSION} >> percona-toolkit.properties
    #
    DSC=$(basename $(find . -name '*.dsc' | sort | tail -n1))
    #
    dpkg-source -x ${DSC}
    #
    cd ${PRODUCT}-${VERSION}
    echo 9 > debian/compat
    if [ x"$ARCH" = "xaarch64" ]; then
        sed -i 's/@@ARCHITECTURE@@/arm64/' debian/control
    else
        sed -i 's/@@ARCHITECTURE@@/amd64/' debian/control
    fi
    export GOBINPATH="$(pwd)/go/bin"
    echo ${GOBINPATH}
    cp /usr/local/go/bin/dep ${GOBINPATH}/
    cp /usr/local/go/bin/glide ${GOBINPATH}/
    rm -rf bin/pt-mongo*
    cd src/go
    sed -i "s|dep ensure|${GOBINPATH}/dep ensure|g" Makefile
    if [ x"$ARCH" = "xx86_64" ]; then
	VERSION=$VERSION make linux-amd64
    else
	VERSION=$VERSION make linux-arm64
    fi
    cd ../../
    dch -b -m -D "all" --force-distribution -v "${VERSION}-${DEB_RELEASE}.${DEBIAN_VERSION}" 'Update distribution'
    dpkg-buildpackage -rfakeroot -us -uc -b
    mkdir -p $CURDIR/deb
    mkdir -p $WORKDIR/deb
    cp $WORKDIR/*.*deb $WORKDIR/deb
    cp $WORKDIR/*.*deb $CURDIR/deb
    if [ "x$DEBIAN_VERSION" = "xjammy" -o "x$DEBIAN_VERSION" = "xnoble" ]; then
        for dir in $WORKDIR/deb $CURDIR/deb; do
	    cd $dir
            COMP=gzip
            for i in *.deb; do
                echo "$i"
                mkdir "$i.extract"
                dpkg-deb -R "$i" "$i.extract"
                rm "$i"
                dpkg-deb -b "-Z$COMP" "$i.extract" "$i"
                rm -rf "$i.extract"
            done
        done
    fi
    cd $WORKDIR
}
#===========================
#main
export GIT_SSL_NO_VERIFY=1
CURDIR=$(pwd)
VERSION_FILE=$CURDIR/percona-toolkit.properties
args=
WORKDIR=
SRPM=0
SDEB=0
RPM=0
DEB=0
TARBALL=0
BTARBALL=0
SOURCE=0
OS_NAME=
ARCH=
OS=
INSTALL=0
RPM_RELEASE=1
DEB_RELEASE=1
REVISION=0
GIT_BRANCH=${GIT_BRANCH}
GIT_REPO=https://github.com/percona/percona-toolkit.git
PRODUCT=percona-toolkit
DEBUG=0
parse_arguments PICK-ARGS-FROM-ARGV "$@"
VERSION=${VERSION}
RELEASE='1'
PRODUCT_FULL=${PRODUCT}-${VERSION}

check_workdir
get_system
install_deps
get_sources
build_srpm
build_source_deb
build_rpm
build_deb
build_tarball
