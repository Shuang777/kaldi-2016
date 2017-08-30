#!/bin/bash

. ./path.sh

if [ $# -ne 1 ]; then
  echo ""
  exit 1
fi

data=$1

vector-to-len --count-vad=true scp:$data/vad.scp | awk '{print $1 / 100 / 3600}' | tee $data/hours_vad
