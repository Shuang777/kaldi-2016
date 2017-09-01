#!/bin/bash
# Copyright 2015   David Snyder
#           2015   Johns Hopkins University (Author: Daniel Garcia-Romero)
#           2015   Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0
{
set -e
set -o pipefail

# This script derives a full-covariance UBM from DNN posteriors and
# speaker recognition features.

# Begin configuration section.
nj=10
cmd="run.pl"
stage=-2
delta_window=3
delta_order=2
subsample=1
min_post=0.025 # Minimum posterior to use (posteriors below this are pruned out)
feat_type=raw
transform_dir=
model_name=final.model.txt
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 4 ]; then
  echo "Usage: steps/init_full_ubm_from_dnn.sh <data-speaker-id> <data-dnn> <dnn-model> <new-ubm-dir>"
  echo "Initializes a full-covariance UBM from DNN posteriors and speaker recognition features."
  echo " e.g.: steps/init_full_ubm_from_dnn.sh data/train data/train_dnn exp/dnn/final.mdl exp/full_ubm"
  echo "main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config containing options"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --nj <n|16>                                      # number of parallel training jobs"
  echo "  --delta-window <n|3>                             # delta window size"
  echo "  --delta-order <n|2>                              # delta order"
  echo "                                                   # to be equal to the size of the DNN output layer."
  exit 1;
fi

data=$1
data_dnn=$2
dnndir=$3
dir=$4


for f in $data/feats.scp $data/vad.scp ${data_dnn}/feats.scp; do
  [ ! -f $f ] && echo "No such file $f" && exit 1;
done

mkdir -p $dir/log
echo $nj > $dir/num_jobs
sdata=$data/split$nj;
[[ -d $sdata && $data/feats.scp -ot $sdata ]] || split_data.sh $data $nj 

sdata_dnn=$data_dnn/split$nj;
[[ -d $sdata_dnn && $data_dnn/feats.scp -ot $sdata_dnn ]] || split_data.sh $data_dnn $nj 

delta_opts="--delta-window=$delta_window --delta-order=$delta_order"
echo $delta_opts > $dir/delta_opts

logdir=$dir/log
[ -f $dnndir/splice_opts ] && splice_opts=`cat $dnndir/splice_opts 2>/dev/null` # frame-splicing options           
if [ ! -z $transform_dir ]; then
  # we need to verify transforms for fmllr
  [ ! -f $transform_dir/trans.1 ] && echo "Cannot find $transform_dir/trans.1" && exit 1
  nj_orig=$(cat $transform_dir/num_jobs)
  if [ $nj -eq $nj_orig ]; then
    trans=trans.JOB
  else
    for n in $(seq $nj_orig); do cat $transform_dir/trans.$n; done | \
       copy-feats ark:- ark,scp:$dir/$trans.ark,$dir/$trans.scp
    trans=trans.ark
  fi
fi

feats="ark,s,cs:add-deltas $delta_opts scp:$sdata/JOB/feats.scp ark:- | apply-cmvn-sliding --norm-vars=false --center=true --cmn-window=300 ark:- ark:- | select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- |"

# Parse the output of nnet-am-info to find the size of the output layer
# of the TDNN.  This will also correspond to the number of components
# in the ancillary GMM.
num_components=$(cat $dnndir/output_dim)

if [ $stage -le 0 ]; then
  $cmd JOB=1:$nj $logdir/gen_post.JOB.log \
    python3 steps_tf/nnet_forward.py --transform $transform_dir/$trans \
    $sdata_dnn/JOB $dnndir/$model_name \| \
    select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- \| \
    prob-to-post --min-post=$min_post ark:- "ark:|gzip -c > $dir/post.JOB.gz"
fi

if [ $stage -le 1 ]; then
  $cmd JOB=1:$nj $logdir/make_stats.JOB.log \
    fgmm-global-acc-stats-post ark:"gunzip -c $dir/post.JOB.gz |" \
    $num_components "$feats" $dir/stats.JOB.acc
fi

if [ $stage -le 2 ]; then
  $cmd $dir/log/init.log \
    fgmm-global-init-from-accs --verbose=2 \
    "fgmm-global-sum-accs - $dir/stats.*.acc |" $num_components \
    $dir/final.ubm
fi

exit 0;
}
