#!/bin/bash

script_path=$(readlink -f "$0")
script_dir=$(dirname "$script_path")
source "$script_dir/check_env.sh"

function setup_dependences()
{
    # get consul
    if [ ! -f "$DEP_DIR/consul" ]; then
        [ "$cpu_arch" == "x86" ] && consul_name="consul_1.11.4_linux_amd64.zip" || consul_name="consul_1.11.4_linux_arm64.zip"
        cd "$TAR_DIR" || exit
        unzip -q "$consul_name"
        mv consul "$DEP_DIR/"
        cd - || exit
    fi

    # get kafka
    grep -q "export JAVA_HOME" /etc/profile
    if [[ $? -ne 0 ]] && [[ ! -d "$DEP_DIR/jdk1.8.0_321" ]]; then
        [ "$cpu_arch" == "x86" ] && jdk_name="jdk-8u321-linux-x64.tar.gz" || jdk_name="jdk-8u321-linux-aarch64.tar.gz"
        cd "$TAR_DIR" || exit
        tar -zxf "$jdk_name" -C "$DEP_DIR/"
        cd - || exit
    fi

    # init java
    grep -q "export JAVA_HOME" /etc/profile
    if [ $? -ne 0 ]; then
       if [ ! -f "$DEP_DIR/profile" ]; then
         touch "$DEP_DIR/profile"
       fi
       echo "export JAVA_HOME=$DEP_DIR/jdk1.8.0_321" > "$DEP_DIR/profile"
       echo "export PATH=$JAVA_HOME/bin:$PATH" >> "$DEP_DIR/profile"
       echo "export CLASSPATH=$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar" >> "$DEP_DIR/profile"
       source "$DEP_DIR/profile"
    fi

    if [ ! -d "$DEP_DIR/kafka_2.13-3.1.0" ]; then
        kafka_name="kafka_2.13-3.1.0.tgz"
        cd "$TAR_DIR" || exit
        tar -zxf "$kafka_name" -C "$DEP_DIR/"
        cd - || exit
    fi
}

TAR_DIR="/home/blobstore-deps"
BIN_DIR="/usr/bin"
DEP_DIR="/usr/bin/blobstore"
RUN_DIR="/var/run/blobstore"
LOG_DIR="/var/log/blobstore"
CONF_DIR="$script_dir/../config"
cpu_arch=$(get_cpu_architecture)
consul=$1

setup_dependences

# start consul
if [ "${consul}" == "--consul" ]; then
    nohup "$DEP_DIR"/consul agent -dev -client 0.0.0.0 >> "$LOG_DIR"/consul.log 2>&1 &
    # check consul running
    sleep 1
    num=$(ps -ef | egrep "$DEP_DIR/consul" | egrep -v "grep|vi|tail" | wc -l)
    if [ ${num} -lt 1 ];then
        echo "Failed to start consul."
        exit 1
    fi
fi

# start kafka
if [ "$cpu_arch" == "arm" ];then
    # patch java options
    sed -i 's/  nohup "\$JAVA"/  nohup "\$JAVA" -XX:+UnlockExperimentalVMOptions/' "$DEP_DIR"/kafka_2.13-3.1.0/bin/kafka-run-class.sh
    sed -i 's/  exec "\$JAVA"/  exec "\$JAVA" -XX:+UnlockExperimentalVMOptions/' "$DEP_DIR"/kafka_2.13-3.1.0/bin/kafka-run-class.sh
    chmod +x "$DEP_DIR/kafka_2.13-3.1.0/bin/kafka-run-class.sh"
fi
uuid=$("$DEP_DIR"/kafka_2.13-3.1.0/bin/kafka-storage.sh random-uuid)
"$DEP_DIR"/kafka_2.13-3.1.0/bin/kafka-storage.sh format -t "$uuid" -c "$DEP_DIR"/kafka_2.13-3.1.0/config/kraft/server.properties
"$DEP_DIR"/kafka_2.13-3.1.0/bin/kafka-server-start.sh -daemon "$DEP_DIR"/kafka_2.13-3.1.0/config/kraft/server.properties
# check kafka running
sleep 1
num=$(ps -ef | grep kafka | grep -v "grep|vi|tail" | wc -l)
if [ ${num} -le 1 ];then
    echo "Failed to start kafka."
    exit 1
fi

# Start the clustermgr
nohup "$BIN_DIR"/clustermgr -f "$CONF_DIR"/clustermgr1.conf >> "$LOG_DIR"/clustermgr1.log  2>&1 &
nohup "$BIN_DIR"/clustermgr -f "$CONF_DIR"/clustermgr2.conf >> "$LOG_DIR"/clustermgr2.log  2>&1 &
nohup "$BIN_DIR"/clustermgr -f "$CONF_DIR"/clustermgr3.conf >> "$LOG_DIR"/clustermgr3.log  2>&1 &
sleep 5
num=$(ps -ef | egrep "$BIN_DIR"/clustermgr |  egrep -v "vi|tail|grep" | wc -l)
if [ $num -ne 3 ]; then
    echo "Failed to start clustermgr"
    exit 1
fi

sleep 15
echo "start clustermgr ok"

# Start the proxy
nohup "$BIN_DIR"/proxy -f "$CONF_DIR"/proxy.conf >> "$LOG_DIR"/proxy.log 2>&1 &
sleep 1
num=$(ps -ef | egrep "$BIN_DIR"/proxy |  egrep -v "vi|tail|grep" | wc -l)
if [ ${num} -lt 1 ];then
    echo "The proxy start failed."
    exit 1
fi
echo "start proxy ok"

# Start the scheduler
nohup "$BIN_DIR"/scheduler -f "$CONF_DIR"/scheduler.conf >> "$LOG_DIR"/scheduler.log 2>&1 &
sleep 1
num=$(ps -ef | egrep "$BIN_DIR"/scheduler |  egrep -v "vi|tail|grep" | wc -l)
if [ ${num} -lt 1 ];then
    echo "The scheduler start failed."
    exit 1
fi
echo "start scheduler ok"

mkdir -p "$RUN_DIR"/disks/disk{1..8}
# Start the blobnode
nohup "$BIN_DIR"/blobnode -f "$CONF_DIR"/blobnode.conf >> "$LOG_DIR"/blobnode.log 2>&1 &
sleep 1
num=$(ps -ef | egrep "$BIN_DIR"/blobnode |  egrep -v "vi|tail|grep" | wc -l)
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
nohup "$BIN_DIR"/access -f "$CONF_DIR"/access.conf >> "$LOG_DIR"/access.log 2>&1 &
sleep 1
num=$(ps -ef | egrep "$BIN_DIR"/access |  egrep -v "vi|tail|grep" | wc -l)
if [ ${num} -lt 1 ];then
    echo "The access start failed."
    exit 1
fi
echo "start blobstore service successfully, wait minutes for internal state preparation"
