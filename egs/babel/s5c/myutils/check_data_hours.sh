#!/bin/bash

. ./path.sh

if [ $# -ne 1 ]; then
  echo ""
  exit 1
fi

data=$1

if [ -f $data/vad.scp ]; then
  vector-to-len scp:$data/vad.scp
else
  feat-to-len scp:$data/feats.scp
fi | awk '{print $1 / 100 / 3600}' | tee $data/hours
