#!/bin/bash
{
set -e
set -o pipefail

wer_threshold=50

if [ $# != 3 ]; then
  echo "Usage: $0 <decode-dir> <data-name> <dir>"
  echo " e.g.: $0 exp/data_tri3/decode_train_nodev_t1 train_nodev exp/bootstrap"
  exit 1
fi

decode=$1
dataname=$2
dir=$3

[ -d $dir ] || mkdir -p $dir/log

score_dir=$(WERkal $decode | grep '^score' | sort -k5 -n | tr ':' ' ' | awk -v dir=$decode 'NR==1{ printf("%s/%s", dir, $1)}')

echo "score_dir is $score_dir" | tee $dir/log/score_dir.log

grep 'PICT' $score_dir/${dataname}.ctm.sys | \
  awk -v wer_threshold=$wer_threshold '{if ($11 > wer_threshold) print $2, $11}' > $dir/high_err.list

awk '{
  if ($2 != last) {
    count = 0;
  }
  printf("%s_%d %s\n", $2, count, $1);
  count++;
  last = $2;
}' data/${dataname}/segments > $dir/id2utt

awk '
  BEGIN{ mode = "header"; }
  /Speaker sentences/ { mode = "sentence";
    chn=$4; utt_id=$6;}
  { if (mode != "sentence") {
      next;
    }
    if ($1 == "Scores:") {
      num_cor=$6;
      num_sub=$7;
      num_del=$8;
      num_ins=$9;
      wer = (num_sub + num_del + num_ins) / (num_sub + num_del + num_cor)
      printf("%s_%d %.2f %%\n", chn, utt_id, wer*100);
    }
  }
  ' $score_dir/${dataname}.ctm.prf | \
    awk 'NR==FNR{ a[$1]=$2; next } 
      {
        if (!($1 in a)) {
          print "ERROR: $1 not found in id2utt";
          exit;
        }
        print a[$1], $2, $3
      }' $dir/id2utt /dev/stdin > $dir/utt2wer

awk -v wer_threshold=$wer_threshold '{if ($2 > wer_threshold) print}' $dir/utt2wer > $dir/utt.high_err

echo "analyze wer done!"
}
