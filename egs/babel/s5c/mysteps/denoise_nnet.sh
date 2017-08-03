#!/bin/bash

# Copyright 2012-2013 Karel Vesely, Daniel Povey
# Apache 2.0

# This script does decoding with a neural-net.  If the neural net was built on
# top of fMLLR transforms from a conventional system, you should provide the
# --transform-dir option.
{

set -e
set -o pipefail

# Begin configuration section. 
nnet=               # non-default location of DNN (optional)
srcdir=             # non-default location of DNN-dir (decouples model dir from decode dir)
feature_transform=  # non-default location of feature_transform (optional)
model=              # non-default location of transition model (optional)

stage=0 # stage=1 skips lattice generation
nj=4
cmd=run.pl

use_gpu="no" # yes|no|optionaly
feat_type=raw

# End configuration section.

echo "$0 $@"  # Print the command line for logging

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

if [ $# != 3 ]; then
   echo "Usage: $0 [options] <data-dir> <nnet-dir> <tgt-dir>"
   exit 1;
fi

data=$1
dir=$2
tgt=$3

[ -z $srcdir ] && srcdir=`dirname $dir`; # Default model directory one level up from decoding directory.
sdata=$data/split$nj;

[ -d $dir/log ] || mkdir -p $dir/log

mkdir -p $dir/log

[[ -d $sdata && $data/feats.scp -ot $sdata ]] || split_data.sh $utt_opts $data $nj

echo $nj > $dir/num_jobs

# Select default locations to model files (if not already set externally)
if [ -z "$nnet" ]; then nnet=$srcdir/final.nnet; fi
if [ -z "$feature_transform" ]; then feature_transform=$srcdir/final.feature_transform; fi

# Check that files exist
for f in $sdata/1/feats.scp $nnet $feature_transform; do
  [ ! -f $f ] && echo "$0: missing file $f" && exit 1;
done

norm_vars=`cat $srcdir/norm_vars 2>/dev/null` || norm_vars=falsenorm_vars=`cat $srcdir/norm_vars 2>/dev/null` || norm_vars=false

# Create the feature stream:
case $feat_type in
  raw) feats="scp:$sdata/JOB/feats.scp ark:- |";;
  cmvn|traps) feats="ark,s,cs:apply-cmvn --norm-vars=$norm_vars --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- |";;
  delta) feats="ark,s,cs:apply-cmvn --norm-vars=$norm_vars --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- | add-deltas ark:- ark:- |";;
  *) echo "$0: invalid feature type $feat_type" && exit 1;
esac

mfccdir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $dir ${PWD}`

# Run the decoding in the queue
if [ $stage -le 0 ]; then
  $cmd $parallel_opts JOB=1:$nj $dir/log/denoise.JOB.log \
    nnet-forward --feature-transform=$feature_transform --frames-per-batch=2048 \
    --use-gpu=$use_gpu $nnet "$feats" ark,scp:$mfccdir/raw_mfcc.JOB.ark,$mfccdir/raw_mfcc.JOB.scp
fi

utils/copy_data_dir.sh $data $tgt
for i in `seq $nj`; do
  cat $dir/raw_mfcc.$i.scp
done > $tgt/feats.scp

steps/compute_cmvn_stats.sh $tgt $dir/log $dir

}
