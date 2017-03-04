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
nj=40
cmd="run.pl"
stage=-2
delta_window=3
delta_order=2
subsample=1
min_post=0.025 # Minimum posterior to use (posteriors below this are pruned out)

feat_type=raw
transform_dir=
use_gpu=no
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


for f in $data/feats.scp $data/vad.scp ${data_dnn}/feats.scp \
    $dnndir/final.nnet; do
  [ ! -f $f ] && echo "No such file $f" && exit 1;
done

mkdir -p $dir/log
echo $nj > $dir/num_jobs
sdata=$data/split$nj;
utils/split_data.sh $data $nj || exit 1;

sdata_dnn=$data_dnn/split$nj;
utils/split_data.sh $data_dnn $nj || exit 1;

delta_opts="--delta-window=$delta_window --delta-order=$delta_order"
echo $delta_opts > $dir/delta_opts

logdir=$dir/log
splice_opts=`cat $dnndir/splice_opts 2>/dev/null` # frame-splicing options           

case $feat_type in
  raw) 
    nnet_feats="ark,s,cs:apply-cmvn-sliding --center=true scp:$sdata_dnn/JOB/feats.scp ark:- |"
    ;;
  traps) 
    nnet_feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata_dnn/JOB/utt2spk scp:$sdata_dnn/JOB/cmvn.scp scp:$sdata_dnn/JOB/feats.scp ark:- |"
    ;;
  lda|fmllr) 
    [ -z $transform_dir ] && echo "transform_dir empty for lda/fmllr feature" && exit 1
    nnet_feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata_dnn/JOB/utt2spk scp:$sdata_dnn/JOB/cmvn.scp scp:$sdata_dnn/JOB/feats.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $transform_dir/final.mat ark:- ark:- |"
    ;;
esac


if [ $feat_type == fmllr ]; then
  [ ! -f $transform_dir/trans.1 ] && echo "cannot find $transform_dir/trans.1!" && exit 1
  nnet_feats="$nnet_feats transform-feats --utt2spk=ark:$sdata_dnn/JOB/utt2spk ark:$transform_dir/trans.JOB ark:- ark:- |"
fi

feats="ark,s,cs:add-deltas $delta_opts scp:$sdata/JOB/feats.scp ark:- | \
apply-cmvn-sliding --norm-vars=false --center=true --cmn-window=300 ark:- ark:- | \
select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- | subsample-feats --n=$subsample ark:- ark:- |"

# Parse the output of nnet-am-info to find the size of the output layer
# of the TDNN.  This will also correspond to the number of components
# in the ancillary GMM.
num_components=$(nnet-info $dnndir/final.nnet | grep output-dim | head -1 | awk '{print $2}')
if [ $use_gpu == no ]; then
  cuda_cmd=$cmd
  program=nnet-forward
else
  # we only use trunk folder for gpu for now (squids)
  program=/u/drspeech/data/swordfish/users/suhang/projects/kaldi/trunk/src/nnetbin/nnet-forward
fi

if [ $stage -le 0 ]; then
  $cuda_cmd JOB=1:$nj $logdir/gen_post.JOB.log \
    $program --use-gpu=$use_gpu --feature-transform=$dnndir/final.feature_transform \
    --apply-log=true --frames-per-batch=2048 \
    $dnndir/final.nnet "$nnet_feats" ark:- \
    \| select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- \
    \| logprob-to-post --min-post=$min_post ark:- "ark:|gzip -c > $dir/post.JOB.gz"
fi

if [ $stage -le 1 ]; then
  $cmd JOB=1:$nj $logdir/make_stats.JOB.log \
    copy-post --subsample=$subsample "ark:gunzip -c $dir/post.JOB.gz |" ark:- \| \
    fgmm-global-acc-stats-post ark:- $num_components "$feats" \
    $dir/stats.JOB.acc
fi

if [ $stage -le 2 ]; then
  $cmd $dir/log/init.log \
    fgmm-global-init-from-accs --verbose=2 \
    "fgmm-global-sum-accs - $dir/stats.*.acc |" $num_components \
    $dir/final.ubm
fi

exit 0;
}
