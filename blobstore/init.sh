#!/bin/bash

function check_cpu_architecture() {
    arch=$(uname -m)
    case $arch in
        x86_64|i386|i686)
            echo "x86"
            ;;
        armv*|aarch64)
            echo "arm"
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

function INIT()
{
    # build blobstore
    cd ..
    rootPath=$(cd $(dirname ${BASH_SOURCE[0]}); pwd)
    source build/cgo_env.sh
    make blobstore
    if [ $? -ne 0 ]; then
      echo "build failed"
      exit 1
    fi

    cpu_arch=$(check_cpu_architecture)
    offline_run=$1

    # get consul
    if [ ! -f build/bin/blobstore/consul ]; then
        if [ "$cpu_arch" == "x86" ];then
            consul_name="consul_1.11.4_linux_amd64.zip"
            consul_url="https://ocs-cn-south1.heytapcs.com/blobstore/consul_1.11.4_linux_amd64.zip"
        else
            consul_name="consul_1.11.4_linux_arm64.zip"
            consul_url="https://releases.hashicorp.com/consul/1.11.4/consul_1.11.4_linux_arm64.zip"
        fi
        consul_path="$offline_run/$consul_name"

        if [ -n "$offline_run" ];then
            cp "$consul_path" ./
        else
            wget "$consul_url"
        fi

        unzip -q "$consul_name"
        rm -f "$consul_name"
        mv consul build/bin/blobstore/
        if [ $? -ne 0 ]; then
          echo "prepare consul failed"
          exit 1
        fi
    fi

    # get kafka
    grep -q "export JAVA_HOME" /etc/profile
    if [[ $? -ne 0 ]] && [[ ! -d build/bin/blobstore/jdk1.8.0_321 ]]; then
        if [ "$cpu_arch" == "x86" ];then
            jdk_name="jdk-8u321-linux-x64.tar.gz"
            jdk_url="https://ocs-cn-south1.heytapcs.com/blobstore/jdk-8u321-linux-x64.tar.gz"
            jdk_path="$offline_run/$jdk_name"
        else
            jdk_name="jdk-8u321-linux-aarch64.tar.gz"
            jdk_path="/home/$jdk_name"
        fi

        if [ -n "$offline_run" ];then
            cp "$jdk_path" ./
        else
            wget "$jdk_url"
        fi

        tar -zxf "$jdk_name" -C build/bin/blobstore/
        if [ $? -ne 0 ]; then
          echo "prepare kafka failed"
          exit 1
        fi
        rm -f "$jdk_name"
    fi

    # init java
    grep -q "export JAVA_HOME" /etc/profile
    if [ $? -ne 0 ]; then
       if [ ! -f ./build/bin/blobstore/profile ]; then
         touch ./build/bin/blobstore/profile
       fi
       echo "export JAVA_HOME=$rootPath/build/bin/blobstore/jdk1.8.0_321" > ./build/bin/blobstore/profile
       echo "export PATH=$JAVA_HOME/bin:$PATH" >> ./build/bin/blobstore/profile
       echo "export CLASSPATH=$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar" >> ./build/bin/blobstore/profile
       source build/bin/blobstore/profile
    fi

    if [ ! -d build/bin/blobstore/kafka_2.13-3.1.0 ]; then
        kafka_name="kafka_2.13-3.1.0.tgz"
        kafka_url="https://ocs-cn-south1.heytapcs.com/blobstore/kafka_2.13-3.1.0.tgz"
        kafka_path="$offline_run/$kafka_name"

        if [ -n "$offline_run" ];then
            cp "$kafka_path" ./
        else
            wget "$kafka_url"
        fi

        tar -zxf "$kafka_name" -C build/bin/blobstore/
        if [ $? -ne 0 ]; then
          echo "prepare kafka failed"
          exit 1
        fi
        rm -f "$kafka_name"
    fi
}
