#!/bin/bash 

# Copyright 2012  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0
# To be run from .. (one directory up from here)
# see ../run.sh for example

# Begin configuration section.
nj=4
cmd=run.pl
compress=true
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 5 ]; then
   echo "Usage: $0 [options] <data-dir> <raw-feat-dir> <ref-dir> <log-dir> <path-to-mfccdir>";
   echo "e.g.: $0 data/train exp/make_mfcc/train mfcc"
   echo "options: "
   echo "  --mfcc-config <config-file>                      # config passed to compute-mfcc-feats "
   echo "  --nj <nj>                                        # number of parallel jobs"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   exit 1;
fi

data=$1
raw_feat_dir=$2
refdir=$3
logdir=$4
mfccdir=$5


# make $mfccdir an absolute pathname.
mfccdir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $mfccdir ${PWD}`

# use "name" as part of name of the archive.
name=`basename $data`

mkdir -p $mfccdir || exit 1;
mkdir -p $logdir || exit 1;


if [ -f $data/feats.scp ]; then
  mkdir -p $data/.backup
  echo "$0: moving $data/feats.scp to $data/.backup"
  mv $data/feats.scp $data/.backup
fi

$cmd JOB=1:$nj $logdir/process_tifeat_${name}.JOB.log \
  for i in \`awk \'{print \$1}\' $refdir/split$nj/JOB/feats.scp\`\; do \
    awk -F',' 'BEGIN {a=split(ARGV[1], arr, "/"); split(arr[a],arr,"."); printf("%s [ ", arr[1]);} { printf("\n "); printf(" %d", $12); for(i=1; i<=11; i++) printf(" %d", $i); } END {print " ]"; }' $raw_feat_dir/\$i.wav.csv\; done \| \
    process-ti-feats ark:- ark:- \| \
    map-feat2feat ark:- scp:$refdir/split$nj/JOB/feats.scp \
      ark,scp:$mfccdir/raw_mfcc_$name.JOB.ark,$mfccdir/raw_mfcc_$name.JOB.scp


if [ -f $logdir/.error.$name ]; then
  echo "Error producing mfcc features for $name:"
  tail $logdir/make_mfcc_${name}.1.log
  exit 1;
fi

# concatenate the .scp files together.
for n in $(seq $nj); do
  cat $mfccdir/raw_mfcc_$name.$n.scp || exit 1;
done > $data/feats.scp

rm $logdir/wav_${name}.*.scp  $logdir/segments.* 2>/dev/null

nf=`cat $data/feats.scp | wc -l` 
nu=`cat $data/utt2spk | wc -l` 
if [ $nf -ne $nu ]; then
  echo "It seems not all of the feature files were successfully processed ($nf != $nu);"
  echo "consider using utils/fix_data_dir.sh $data"
fi

if [ $nf -lt $[$nu - ($nu/20)] ]; then
  echo "Less than 95% the features were successfully generated.  Probably a serious error."
  exit 1;
fi

echo "Succeeded processing TI MFCC features for $name"
