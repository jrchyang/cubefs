#!/bin/bash

source ./check_env.sh

function setup_dependences()
{
    # get consul
    if [ ! -f "$dep_bin_dir/consul" ]; then
        if [ "$cpu_arch" == "x86" ];then
            consul_name="consul_1.11.4_linux_amd64.zip"
        else
            consul_name="consul_1.11.4_linux_arm64.zip"
        fi

        cd "$dep_dir" || exit
        unzip -q "$consul_name"
        mv consul "$dep_bin_dir/"
        cd - || exit
    fi

    # get kafka
    grep -q "export JAVA_HOME" /etc/profile
    if [[ $? -ne 0 ]] && [[ ! -d "$dep_bin_dir/jdk1.8.0_321" ]]; then
        if [ "$cpu_arch" == "x86" ];then
            jdk_name="jdk-8u321-linux-x64.tar.gz"
        else
            jdk_name="jdk-8u321-linux-aarch64.tar.gz"
        fi

        cd "$dep_dir" || exit
        tar -zxf "$jdk_name" -C "$dep_bin_dir/"
        cd - || exit
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
        cd "$dep_dir" || exit
        tar -zxf "$kafka_name" -C "$dep_bin_dir/"
        cd - || exit
    fi
}

dep_dir="/home/blobstore-deps"
dep_bin_dir="/usr/bin/blobstore"
cpu_arch=$(get_cpu_architecture)
consul=$1

setup_dependences

# start consul
if [ "${consul}" == "--consul" ]; then
    nohup /usr/bin/blobstore/consul agent -dev -client 0.0.0.0 >> /var/log/blobstore/consul.log 2>&1 &
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
nohup /usr/bin/clustermgr -f /usr/bin/blobstore/sample.clustermgr1.conf >> /var/log/blobstore/clustermgr1.log  2>&1 &
nohup /usr/bin/clustermgr -f /usr/bin/blobstore/sample.clustermgr2.conf >> /var/log/blobstore/clustermgr2.log  2>&1 &
nohup /usr/bin/clustermgr -f /usr/bin/blobstore/sample.clustermgr3.conf >> /var/log/blobstore/clustermgr3.log  2>&1 &
sleep 5
num=$(ps -ef | egrep /usr/bin/clustermgr |  egrep -v "vi|tail|grep" | wc -l)
if [ $num -ne 3 ]; then
    echo "Failed to start clustermgr"
    exit 1
fi

sleep 15
echo "start clustermgr ok"

# Start the proxy
nohup /usr/bin/proxy -f /usr/bin/blobstore/sample.proxy.conf >> /var/log/blobstore/logs/proxy.log 2>&1 &
sleep 1
num=$(ps -ef | egrep /usr/bin/proxy |  egrep -v "vi|tail|grep" | wc -l)
if [ ${num} -lt 1 ];then
    echo "The proxy start failed."
    exit 1
fi
echo "start proxy ok"

# Start the scheduler
nohup /usr/bin/scheduler -f /usr/bin/blobstore/sample.scheduler.conf >> /var/log/blobstore/scheduler.log 2>&1 &
sleep 1
num=$(ps -ef | egrep /usr/bin/scheduler |  egrep -v "vi|tail|grep" | wc -l)
if [ ${num} -lt 1 ];then
    echo "The scheduler start failed."
    exit 1
fi
echo "start scheduler ok"

mkdir -p /var/run/blobstore/disks/disk{1..8}
# Start the blobnode
nohup /usr/bin/blobnode -f /usr/bin/blobstore/sample.blobnode.conf >> /var/log/blobstore/blobnode.log 2>&1 &
sleep 1
num=$(ps -ef | egrep /usr/bin/blobnode |  egrep -v "vi|tail|grep" | wc -l)
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
nohup /usr/bin/access -f /usr/bin/blobstore/sample.access.conf >> /var/log/blobstore/access.log 2>&1 &
sleep 1
num=$(ps -ef | egrep /usr/bin/access |  egrep -v "vi|tail|grep" | wc -l)
if [ ${num} -lt 1 ];then
    echo "The access start failed."
    exit 1
fi
echo "start blobstore service successfully, wait minutes for internal state preparation"
