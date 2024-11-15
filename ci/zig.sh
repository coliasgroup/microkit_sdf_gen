#!/bin/bash

ZIG_VERSION='0.14.0-dev.2245+4fc295dc0'

HOST_ARCH=`uname -m`
HOST_OS=`uname -o`

if [[ "$HOST_ARCH" == "x86_64" ]]; then
    ZIG_ARCH="x86_64"
elif [[ "$HOST_ARCH" == "arm64" ]]; then
    ZIG_ARCH="aarch64"
else
    echo "Unknown host arch: $HOST_ARCH"
    exit 1
fi

if [[ "$HOST_OS" == "GNU/Linux" ]]; then
    ZIG_OS="linux"
elif [[ "$HOST_OS" == "Darwin" ]]; then
    ZIG_OS="macos"
else
    echo "Unknown host arch: $HOST_OS"
    exit 1
fi

echo "zig-$ZIG_OS-$ZIG_ARCH-$ZIG_VERSION"
