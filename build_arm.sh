#!/bin/bash

RootPath=$(cd $(dirname $0); pwd)
module=$1

# build arm64 with amd64 docker ubuntu:focal, apt-get install -y gcc-9-aarch64-linux-gnu gcc-aarch64-linux-gnu  g++-9-aarch64-linux-gnu g++-aarch64-linux-gnu
# Support Ubuntu focal, not support CentOS7
function build_linux_arm64_gcc9() {
    export PORTABLE=1
    export ARCH=arm64
    export EXTRA_CFLAGS="-Wno-error=deprecated-copy -fno-strict-aliasing -Wclass-memaccess -Wno-error=class-memaccess -Wpessimizing-move -Wno-error=pessimizing-move"
    export EXTRA_CXXFLAGS=$EXTRA_CFLAGS

    CGO_ENABLED=1 GOOS=linux GOARCH=arm64 make "$module"
}

# wget compress dep
function get_rocksdb_compress_dep() {
   #################################################################
   ## Might check the dep files each in individual if wget failed ##
   #################################################################
    if [ ! -d "${RootPath}/vendor/dep" ]; then
        mkdir -p ${RootPath}/vendor/dep
    fi
    cd ${RootPath}/vendor/dep

    if [ ! -d "${RootPath}/vendor/dep/zlib-1.2.11" ]; then
        wget https://zlib.net/fossils/zlib-1.2.11.tar.gz
        tar zxf zlib-1.2.11.tar.gz
    fi

    if [ ! -d "${RootPath}/vendor/dep/bzip2-1.0.6" ]; then
        wget https://sourceforge.net/projects/bzip2/files/bzip2-1.0.6.tar.gz
        tar zxf bzip2-1.0.6.tar.gz
    fi

    if [ ! -d "${RootPath}/vendor/dep/zstd-1.4.8" ]; then
        wget https://codeload.github.com/facebook/zstd/zip/v1.4.8
        unzip v1.4.8
    fi

    if [ ! -d "${RootPath}/vendor/dep/lz4-1.9.3" ]; then
        wget https://codeload.github.com/lz4/lz4/tar.gz/v1.9.3
        tar zxf v1.9.3
    fi

    #rm -rf zlib-1.2.11.tar.gz bzip2-1.0.6.tar.gz v1.4.8 v1.9.3
    cd ${RootPath}
}

get_rocksdb_compress_dep
build_linux_arm64_gcc9
