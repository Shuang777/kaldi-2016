#!/bin/bash
{
set -e

#begin configuration
lm_score=12
nbest=1
#end configuration

echo "$0 $@"

. parse_options.sh
. ./path.sh

if [ $# -ne 3 ]; then
  echo "Usage: $0 <decode-dir> <graph-dir> <out-transcription>"
  exit 1;
fi

decode=$1
graph=$2
out_trans=$3

if [ -z $decode ] || [ ! -d "$decode" ]; then
  echo decode dir $decode does not exist.
  exit 1
fi

if [ $nbest == 1 ]; then
  lattice-best-path --lm-scale=$lm_score "ark:gunzip -c $decode/lat.*.gz |" \
    ark,t:- ark:/dev/null 2>${out_trans}.score | \
    utils/int2sym.pl -f 2- $graph/words.txt  > ${out_trans}.unsort

  grep 'For utterance' ${out_trans}.score | tr ',' ' ' | \
    awk 'NR==FNR {a[$5] = $(NF-3); next}
        {
           $1 = $1"-1 "a[$1];
           print $0;
        }' /dev/stdin ${out_trans}.unsort > $out_trans

else
  lattice-to-nbest --lm-scale=$lm_score --n=$nbest "ark:gunzip -c $decode/lat.*.gz |" ark:- | \
    lattice-best-path ark:- ark,t:- 2>${out_trans}.score.unsort | \
    utils/int2sym.pl -f 2- $graph/words.txt  > ${out_trans}.unsort

  grep 'For utterance' ${out_trans}.score.unsort | tr ',' ' ' | awk '{print $5, $(NF-3) }' \
        > ${out_trans}.llk.unsort

  local/sort_nbest.py ${out_trans}.unsort ${out_trans}.llk.unsort > $out_trans

fi

}
