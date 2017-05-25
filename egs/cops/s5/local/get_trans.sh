#!/bin/bash

set -e

lm_score=12
nbest=1

. parse_options.sh
. ./path.sh

if [ $# -ne 3 ]; then
  echo "Usage: $0 <decode-dir> <graph-dir> <out-transcription>"
  exit 1;
fi

decode=$1
graph=$2
out_trans=$3

if [ $nbest == 1 ]; then
  lattice-best-path --lm-scale=$lm_score "ark:gunzip -c $decode/lat.*.gz |" ark,t:- ark:/dev/null | \
    utils/int2sym.pl -f 2- $graph/words.txt  > $out_trans
else
  lattice-to-nbest --lm-scale=$lm_score --n=$nbest "ark:gunzip -c $decode/lat.*.gz |" ark:- | \
    lattice-best-path ark:- ark,t:- 2>${out_trans}.score.unsort | \
    utils/int2sym.pl -f 2- $graph/words.txt  > ${out_trans}.unsort

  grep 'For utterance' ${out_trans}.score.unsort | tr ',' ' ' | awk '{print $5, $(NF-3) }' \
        > ${out_trans}.llk.unsort

  local/sort_nbest.py ${out_trans}.unsort ${out_trans}.llk.unsort > ${out_trans}
fi
