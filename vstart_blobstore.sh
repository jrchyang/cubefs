#!/bin/bash

set -e

source ./check_env.sh

bin_dir="/usr/bin"
dep_dir="/home/blobstore-deps"
dep_bin_dir="/usr/bin/blobstore"
sample_conf_dir="/usr/bin/blobstore"
log_dir="/var/log/blobstore"
run_dir="/var/run/blobstore"
cpu_arch=$(check_cpu_architecture)
consul=$1

function INIT()
{
    # get consul
    if [ ! -f "$dep_bin_dir/consul" ]; then
        if [ "$cpu_arch" == "x86" ];then
            consul_name="consul_1.11.4_linux_amd64.zip"
        else
            consul_name="consul_1.11.4_linux_arm64.zip"
        fi

        cd "$dep_dir"
        unzip -q "$consul_name"
        mv consul "$dep_bin_dir/"
        cd -
    fi

    # get kafka
    grep -q "export JAVA_HOME" /etc/profile
    if [[ $? -ne 0 ]] && [[ ! -d "$dep_bin_dir/jdk1.8.0_321" ]]; then
        if [ "$cpu_arch" == "x86" ];then
            jdk_name="jdk-8u321-linux-x64.tar.gz"
        else
            jdk_name="jdk-8u321-linux-aarch64.tar.gz"
        fi

        cd "$dep_dir"
        tar -zxf "$jdk_name" -C "$dep_bin_dir/"
        cd -
    fi

    # init java
    grep -q "export JAVA_HOME" /etc/profile
    if [ $? -ne 0 ]; then
       if [ ! -f "$dep_bin_dir/profile" ]; then
         touch "$dep_bin_dir/profile"
       fi
       echo "export JAVA_HOME=$dep_bin_dir/jdk1.8.0_321" > "$dep_bin_dir/profile"
       echo "export PATH=$JAVA_HOME/bin:$PATH" >> "$dep_bin_dir/profile"
       echo "export CLASSPATH=$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar" >> "$dep_bin_dir/profile"
       source "$dep_bin_dir/profile"
    fi

    if [ ! -d "$dep_bin_dir/kafka_2.13-3.1.0" ]; then
        kafka_name="kafka_2.13-3.1.0.tgz"
        cd "$dep_dir"
        tar -zxf "$kafka_name" -C "$dep_bin_dir/"
        cd -
    fi
}

if [ ! -d "$log_dir" ];then
    mkdir -p "$log_dir"
fi

# start consul
if [ "${consul}" == "--consul" ]; then
    nohup "$dep_bin_dir"/consul agent -dev -client 0.0.0.0 >> "$log_dir"/consul.log 2>&1 &
    # check consul running
    sleep 1
    num=$(ps -ef | egrep "$dep_bin_dir/consul" | egrep -v "grep|vi|tail" | wc -l)
    if [ ${num} -lt 1 ];then
        echo "Failed to start consul."
        exit 1
    fi
fi

# start kafka
if [ "$cpu_arch" == "arm" ];then
    # patch java options
    sed -i 's/  nohup "\$JAVA"/  nohup "\$JAVA" -XX:+UnlockExperimentalVMOptions/' "$dep_bin_dir"/kafka_2.13-3.1.0/bin/kafka-run-class.sh
    sed -i 's/  exec "\$JAVA"/  exec "\$JAVA" -XX:+UnlockExperimentalVMOptions/' "$dep_bin_dir"/kafka_2.13-3.1.0/bin/kafka-run-class.sh
    chmod +x "$dep_bin_dir/kafka_2.13-3.1.0/bin/kafka-run-class.sh"
fi
uuid=$("$dep_bin_dir"/kafka_2.13-3.1.0/bin/kafka-storage.sh random-uuid)
"$dep_bin_dir"/kafka_2.13-3.1.0/bin/kafka-storage.sh format -t $uuid -c "$dep_bin_dir"/kafka_2.13-3.1.0/config/kraft/server.properties
"$dep_bin_dir"/kafka_2.13-3.1.0/bin/kafka-server-start.sh -daemon "$dep_bin_dir"/kafka_2.13-3.1.0/config/kraft/server.properties
# check kafka running
sleep 1
num=$(ps -ef | grep kafka | grep -v "grep|vi|tail" | wc -l)
if [ ${num} -le 1 ];then
    echo "Failed to start kafka."
    exit 1
fi

# Start the clustermgr
nohup "$bin_dir"/clustermgr -f "$sample_conf_dir"/clustermgr1.conf >> "$log_dir"/clustermgr1.log  2>&1 &
nohup "$bin_dir"/clustermgr -f "$sample_conf_dir"/clustermgr2.conf >> "$log_dir"/clustermgr2.log  2>&1 &
nohup "$bin_dir"/clustermgr -f "$sample_conf_dir"/clustermgr3.conf >> "$log_dir"/clustermgr3.log  2>&1 &
sleep 5
num=$(ps -ef | egrep "$bin_dir/clustermgr" |  egrep -v "vi|tail|grep" | wc -l)
if [ $num -ne 3 ]; then
    echo "Failed to start clustermgr"
    exit 1
fi

sleep 15
echo "start clustermgr ok"

# Start the proxy
nohup "$bin_dir"/proxy -f "$sample_conf_dir"/proxy.conf >> "$log_dir"/logs/proxy.log 2>&1 &
sleep 1
num=$(ps -ef | egrep "$bin_dir"/proxy |  egrep -v "vi|tail|grep" | wc -l)
if [ ${num} -lt 1 ];then
    echo "The proxy start failed."
    exit 1
fi
echo "start proxy ok"

# Start the scheduler
nohup "$bin_dir"/scheduler -f "$sample_conf_dir"/scheduler.conf >> "$log_dir"/scheduler.log 2>&1 &
sleep 1
num=$(ps -ef | egrep "$bin_dir"/scheduler |  egrep -v "vi|tail|grep" | wc -l)
if [ ${num} -lt 1 ];then
    echo "The scheduler start failed."
    exit 1
fi
echo "start scheduler ok"

mkdir -p "$run_dir"/disks/disk{1..8}
# Start the blobnode
nohup "$bin_dir"/blobnode -f "$sample_conf_dir"/blobnode.conf >> "$log_dir"/blobnode.log 2>&1 &
sleep 1
num=$(ps -ef | egrep "$bin_dir"/blobnode |  egrep -v "vi|tail|grep" | wc -l)
if [ ${num} -lt 1 ];then
    echo "The blobnode start failed."
    exit 1
fi
echo "start blobnode ok"

if [ "${consul}" == "--consul" ]; then
  echo "Wait clustermgr register to consul..."
  sleep 80
fi

# Start the access
nohup "$bin_dir"/access -f "$sample_conf_dir"/access.conf >> "$log_dir"/access.log 2>&1 &
sleep 1
num=$(ps -ef | egrep "$bin_dir"/access |  egrep -v "vi|tail|grep" | wc -l)
if [ ${num} -lt 1 ];then
    echo "The access start failed."
    exit 1
fi
echo "start blobstore service successfully, wait minutes for internal state preparation"
