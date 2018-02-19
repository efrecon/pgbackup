#!/bin/sh

MAINDIR=$(dirname "$0")
TGT=${MAINDIR}/"$1".sh
if [ -x ${TGT} ]; then
    shift 1
    exec ${TGT} "${@}"
fi
echo "${TGT} cannot be found!" >& 2