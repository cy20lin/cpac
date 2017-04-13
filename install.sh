#!/bin/sh
##
## Copyright (c) 2017 ChienYu Lin
##
## Author: ChienYu Lin <cy20lin@gmil.com>
## License: MIT
##

this_dir="$(dirname $(readlink -f $0))"

test -z "$1" && echo "Install file." && exit 1
test ! -d "$1/bin" && mkdir -p -- "$1/bin"
cp -f -- "${this_dir}/bin/cpac.sh" "$1/bin/cpac"
test ! -d "$1/etc/cpac.d" && mkdir -p -- "$1/etc/cpac.d"
cp -f -- "${this_dir}/etc/cpac.d/packages.yml" "$1/etc/cpac.d/packages.yml"
