#!/bin/bash

function get_cpu_architecture() {
    arch=$(uname -m)
    case $arch in
        x86_64|i386|i686)
            echo "x86"
            ;;
        armv*|aarch64)
            echo "arm"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

function get_gcc_version() {
    gcc_version=$(gcc -dumpversion)
    echo "$gcc_version"
}
