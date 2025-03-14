#!/bin/bash

set -e

script_path=$(readlink -f "$0")
root_path=$(dirname "$script_path")
source "$root_path/check_env.sh"

echo_error() {
    local msg="$1"
    echo "$msg" >&2
    exit 1
}

build_linux_x86_64() {
     make "$module"
}

# build arm64 with amd64 docker ubuntu:focal, apt-get install -y gcc-9-aarch64-linux-gnu gcc-aarch64-linux-gnu  g++-9-aarch64-linux-gnu g++-aarch64-linux-gnu
# Support Ubuntu focal, not support CentOS7
build_linux_arm64_gcc9() {
    echo "build linux arm64 gcc9"
    get_rocksdb_compress_dep
    export PORTABLE=1
    export ARCH=arm64
 #   export CC=aarch64-linux-gnu-gcc
    export EXTRA_CFLAGS="-Wno-error=deprecated-copy -fno-strict-aliasing -Wclass-memaccess -Wno-error=class-memaccess -Wpessimizing-move -Wno-error=pessimizing-move"
    export EXTRA_CXXFLAGS=$EXTRA_CFLAGS

    CGO_ENABLED=1 GOOS=linux GOARCH=arm64 make "$module"
}

# build arm64 with amd64 docker buntu:xenial , apt-get install -y gcc-4.9-aarch64-linux-gnu gcc-aarch64-linux-gnu  g++-4.9-aarch64-linux-gnu g++-aarch64-linux-gnu
# support CentOS7
#
build_linux_arm64_gcc4() {
    echo "build linux arm64 gcc4.9"
    get_rocksdb_compress_dep
    export PORTABLE=1
    export ARCH=arm64
 #   export CC=aarch64-linux-gnu-gcc
    export EXTRA_CFLAGS=" -fno-strict-aliasing  "
    export EXTRA_CXXFLAGS=$EXTRA_CFLAGS

    CGO_ENABLED=1 GOOS=linux GOARCH=arm64 make "$module"
}

# wget compress dep
get_rocksdb_compress_dep() {
   #################################################################
   ## Might check the dep files each in individual if wget failed ##
   #################################################################
    if [ ! -d "${root_path}/vendor/dep" ]; then
        mkdir -p "${root_path}/vendor/dep"
    fi
    cd "${root_path}/vendor/dep"

    if [ ! -d "${root_path}/vendor/dep/zlib-1.2.11" ]; then
        if [ -n "$offline_build" ];then
            cp "$offline_build/zlib-1.2.11.tar.gz" ./
        else
            wget https://zlib.net/fossils/zlib-1.2.11.tar.gz
        fi
        tar -zxf zlib-1.2.11.tar.gz
    fi

    if [ ! -d "${root_path}/vendor/dep/bzip2-1.0.6" ]; then
        if [ -n "$offline_build" ];then
            cp "$offline_build/bzip2-1.0.6.tar.gz" ./
        else
            wget https://repository.timesys.com/buildsources/b/bzip2/bzip2-1.0.6/bzip2-1.0.6.tar.gz
        fi
        tar -zxf bzip2-1.0.6.tar.gz
    fi

    if [ ! -d "${root_path}/vendor/dep/zstd-1.4.8" ]; then
        if [ -n "$offline_build" ];then
            cp "$offline_build/zstd-v1.4.8.zip" ./
        else
            wget -O zstd-v1.4.8.zip https://codeload.github.com/facebook/zstd/zip/v1.4.8
        fi
        unzip -q zstd-v1.4.8.zip
    fi

    if [ ! -d "${root_path}/vendor/dep/lz4-1.9.3" ]; then
        if [ -n "$offline_build" ];then
            cp "$offline_build/lz4-v1.9.3.tar.gz" ./
        else
            wget -O lz4-v1.9.3.tar.gz https://codeload.github.com/lz4/lz4/tar.gz/v1.9.3
        fi
        tar -zxf lz4-v1.9.3.tar.gz
    fi

    #rm -rf zlib-1.2.11.tar.gz bzip2-1.0.6.tar.gz v1.4.8 v1.9.3
    cd "${root_path}"
}

copy_config() {
    if [ ! -d "$root_path"/build/config ];then
        mkdir -p "$root_path"/build/config
    fi

    cp -f "$root_path"/blobstore/cmd/clustermgr/clustermgr.conf "${root_path}"/build/conf/clustermgr.conf
    cp -f "$root_path"/blobstore/cmd/clustermgr/clustermgr1.conf "${root_path}"/build/conf/clustermgr1.conf
    cp -f "$root_path"/blobstore/cmd/clustermgr/clustermgr2.conf "${root_path}"/build/conf/clustermgr2.conf
    cp -f "$root_path"/blobstore/cmd/clustermgr/clustermgr3.conf "${root_path}"/build/conf/clustermgr3.conf
    cp -f "$root_path"/blobstore/cmd/proxy/proxy.conf "${root_path}"/build/conf/proxy.conf
    cp -f "$root_path"/blobstore/cmd/scheduler/scheduler.conf "${root_path}"/build/conf/scheduler.conf
    cp -f "$root_path"/blobstore/cmd/scheduler/scheduler.leader.conf "${root_path}"/build/conf/scheduler.leader.conf
    cp -f "$root_path"/blobstore/cmd/scheduler/scheduler.follower.conf "${root_path}"/build/conf/scheduler.follower.conf
    cp -f "$root_path"/blobstore/cmd/blobnode/blobnode.conf "${root_path}"/build/conf/blobnode.conf
    cp -f "$root_path"/blobstore/cmd/access/access.conf "${root_path}"/build/conf/access.conf
    cp -f "$root_path"/blobstore/cli/cli/cli.conf "${root_path}"/build/conf/blobstore.cli.conf
}

# build rpm blobstore
build_rpm_blobstore() {
    echo "building blobstore rpm"

    # 获取版本号等信息
    rpm_version=$(git describe --tags --abbrev=0)
    rpm_rversion=$(git log -n1 --format=%h)
    rpm_dirname=$(basename "$root_path")
    rpm_name="blobstore"
    rpm_target="$rpm_name-$rpm_version-$rpm_rversion"

    # 生成 rpm 编译使用的代码
    cp -rp ../"$rpm_dirname" ~/rpmbuild/SOURCES/"$rpm_target"
    cd ~/rpmbuild/SOURCES && tar -zcf "$rpm_target".tar.bz2 "$rpm_target"
    rm -rf ~/rpmbuild/SOURCES/"$rpm_target"
    sed -e "s,@name@,${rpm_name},g" \
        -e "s,@version@,${rpm_version},g" \
        -e "s,@revision@,${rpm_rversion},g" \
        "$root_path"/blobstore.spec.in > ~/rpmbuild/SPECS/${rpm_name}.spec

    # 构建 RPM 包
    rpmbuild -bb --clean ~/rpmbuild/SPECS/${rpm_name}.spec

    cd "${root_path}"
}

# build rpm
build_rpm() {
    if [ "$rpm_target" == "blobstore" ];then
        build_rpm_blobstore
    fi
}

cpu_arch=$(get_cpu_architecture)
gcc_version=$(get_gcc_version)
module="all"
rpm_target=""
offline_build=""

if ! GETOPT_ARGS=$(getopt -q -o r:m:o: --long rpm:,module:,offline_build: -- "$@");then
    echo_error "Error: Invalid option."
fi
eval set -- "$GETOPT_ARGS"

# 获取参数
while [ -n "$1" ]; do
    case "$1" in
        -r|--rpm)
            [ -z "$2" ] && echo_error "Error: -m requires a value."
            rpm_target="$2"
            shift 2
            ;;
        -m|--module)
            [ -z "$2" ] && echo_error "Error: -m requires a value."
            module="$2"
            shift 2
            ;;
        -o|--offline_build)
            [ -z "$2" ] && echo_error "Error: -m requires a value."
            offline_build="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "unimplemented option"
            exit 1
            ;;
    esac
done

if [ -n "$rpm_target" ];then
    build_rpm
else
    if [ "$cpu_arch" == "x86" ];then
        build_linux_x86_64
    elif [ "$cpu_arch" == "arm" ];then
        if [ $((gcc_version + 0)) -ge 9 ];then
            build_linux_arm64_gcc9
        else
            build_linux_arm64_gcc4
        fi
    else
        echo "unknown cpu architecture"
        exit 1
    fi

    copy_config
fi
