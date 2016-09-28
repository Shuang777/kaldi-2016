#!/bin/bash

wav=$1
dir=$2

length=$(sox $wav -n stat 2>&1 | grep Length | awk '{print $NF}')

seg=20

parts=$(echo "($length + $seg - 1)/ $seg" | bc)

name=${wav%*.wav}

for i in `seq $parts`; do
  partname=${name}_$i.wav
  start=$(((i-1)*$seg))
  sox $wav $dir/$partname trim $start $seg
done
