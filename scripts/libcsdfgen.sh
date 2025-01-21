#!/bin/sh

set -e

VERSION=`cat VERSION`
RELEASE="release-$VERSION"
mkdir $RELEASE

zig build c -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl -p $RELEASE/sdfgen-$VERSION-linux-x86-64
zig build c -Doptimize=ReleaseSafe -Dtarget=aarch64-linux-musl -p $RELEASE/sdfgen-$VERSION-linux-aarch64
zig build c -Doptimize=ReleaseSafe -Dtarget=x86_64-macos -Dc-dynamic=true -p $RELEASE/sdfgen-$VERSION-macos-x86-64
zig build c -Doptimize=ReleaseSafe -Dtarget=aarch64-macos -Dc-dynamic=true -p $RELEASE/sdfgen-$VERSION-macos-aarch64

tar czf $RELEASE/sdfgen-$VERSION-linux-x86-64.tar.gz --strip-components=1 $RELEASE/sdfgen-$VERSION-linux-x86-64
tar czf $RELEASE/sdfgen-$VERSION-linux-aarch64.tar.gz --strip-components=1 $RELEASE/sdfgen-$VERSION-linux-aarch64
tar czf $RELEASE/sdfgen-$VERSION-macos-x86-64.tar.gz --strip-components=1 $RELEASE/sdfgen-$VERSION-macos-x86-64
tar czf $RELEASE/sdfgen-$VERSION-macos-aarch64.tar.gz --strip-components=1 $RELEASE/sdfgen-$VERSION-macos-aarch64
