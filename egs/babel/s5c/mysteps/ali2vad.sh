#!/bin/bash

nj=
sil_phone=1
cmd=run.pl

. utils/parse_options.sh

. ./path.sh

if [ $# -ne 2 ]; then
  echo "Usage: $0 <ali-dir> <out-dir>"
  exit 1
fi

alidir=$1
outdir=$2

nj_orig=$(cat $alidir/num_jobs)

if [ -z $nj ]; then
  nj=$nj_orig
elif [ $nj -ne $nj_orig ]; then
  echo "nj = $nj does not match num_jobs = $nj_orig in $alidir"
  exit 1
fi

[ -d $outdir ] || mkdir -p $outdir

$cmd JOB=1:$nj $outdir/log/ali2vad.JOB.log \
  ali-to-phones --per-frame=true $alidir/final.mdl "ark:gunzip -c $alidir/ali.JOB.gz |" ark,t:- \| \
  awk -v sil_phone=$sil_phone '{
    utt = $1;
    printf("%s [ ", utt);
    for (i=2; i<=NF; i++) {
      if ($i == sil_phone) {
        printf("0 ");
      } else {
        printf("1 ");
      }
    }
    printf("]\n");
  }' \| copy-vector ark:- ark,scp:`pwd`/$outdir/vad.JOB.ark,$outdir/vad.JOB.scp

for i in `seq $nj`; do
  cat $outdir/vad.$i.scp
done > $outdir/vad.scp
