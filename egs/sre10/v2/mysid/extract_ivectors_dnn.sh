#!/bin/bash
{
set -e
set -o pipefail

# Copyright     2013  Daniel Povey
#          2014-2015  David Snyder
#               2015  Johns Hopkins University (Author: Daniel Garcia-Romero)
#               2015  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0.

# This script extracts iVectors for a set of utterances, given
# features and a trained DNN-based iVector extractor.

# Begin configuration section.
nj=30
cmd="run.pl"
cuda_cmd=
stage=0
min_post=0.025 # Minimum posterior to use (posteriors below this are pruned out)
posterior_scale=1.0 # This scale helps to control for successive features being highly
                    # correlated.  E.g. try 0.1 or 0.3.
use_gpu=no
feat_type=raw
transform_dir=
post_from=
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;


if [ $# != 5 ]; then
  echo "Usage: $0 <extractor-dir> <dnn-dir> <data> <data-dnn> <ivector-dir>"
  echo " e.g.: $0 exp/extractor_2048_male data/train_male exp/ivectors_male"
  echo "main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config containing options"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --num-iters <#iters|10>                          # Number of iterations of E-M"
  echo "  --nj <n|10>                                      # Number of jobs (also see num-processes and num-threads)"
  echo "  --num-threads <n|8>                              # Number of threads for each process"
  echo "  --stage <stage|0>                                # To control partial reruns"
  echo "  --num-gselect <n|20>                             # Number of Gaussians to select using"
  echo "                                                   # diagonal model."
  echo "  --min-post <min-post|0.025>                      # Pruning threshold for posteriors"
  exit 1;
fi

srcdir=$1
dnndir=$2
data=$3
data_dnn=$4
dir=$5

for f in $srcdir/final.ie $srcdir/final.ubm $data/feats.scp ; do
  [ ! -f $f ] && echo "No such file $f" && exit 1;
done

# Set various variables.
mkdir -p $dir/log
sdata=$data/split$nj;
utils/split_data.sh $data $nj || exit 1;

sdata_dnn=$data_dnn/split$nj;
utils/split_data.sh $data_dnn $nj || exit 1;

delta_opts=`cat $srcdir/delta_opts 2>/dev/null`

## Set up features.
feats="ark,s,cs:add-deltas $delta_opts scp:$sdata/JOB/feats.scp ark:- | apply-cmvn-sliding --norm-vars=false --center=true --cmn-window=300 ark:- ark:- | select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- |"


case $feat_type in
  raw) 
    nnet_feats="ark,s,cs:apply-cmvn-sliding --center=true scp:$sdata_dnn/JOB/feats.scp ark:- |"
    ;;
  traps) 
    nnet_feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata_dnn/JOB/utt2spk scp:$sdata_dnn/JOB/cmvn.scp scp:$sdata_dnn/JOB/feats.scp ark:- |"
    ;;
  lda|fmllr) 
    [ -z $transform_dir ] && echo "transform_dir empty for lda/fmllr feature" && exit 1
    splice_dir=$transform_dir
    [ ! -f $splice_dir/splice_opts ] && splice_dir=$(dirname $transform_dir)
    splice_opts=`cat $splice_dir/splice_opts` # frame-splicing options
    nnet_feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata_dnn/JOB/utt2spk scp:$sdata_dnn/JOB/cmvn.scp scp:$sdata_dnn/JOB/feats.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $transform_dir/final.mat ark:- ark:- |"
    ;;
esac

if [ $feat_type == fmllr ]; then
  [ ! -f $transform_dir/trans.1 ] && echo "cannot find $transform_dir/trans.1!" && exit 1
  nnet_feats="$nnet_feats transform-feats --utt2spk=ark:$sdata_dnn/JOB/utt2spk ark:$transform_dir/trans.JOB ark:- ark:- |"
fi

if [ $use_gpu == no ]; then
  cuda_cmd=$cmd
  program=nnet-forward
else
  # we only use trunk folder for gpu for now (squids)
  program=/u/drspeech/data/swordfish/users/suhang/projects/kaldi/trunk/src/nnetbin/nnet-forward
  if [ -z $cuda_cmd ]; then cuda_cmd=$cmd; fi
fi

if [ ! -z $post_from ]; then
  post_dir=$post_from
  stage=1
fi

if [ $stage -le 0 ]; then
  echo "$0: generating posts"
  $cuda_cmd JOB=1:$nj $dir/log/gen_posts.JOB.log \
    $program --use-gpu=$use_gpu --feature-transform=$dnndir/final.feature_transform \
    --apply-log=true --frames-per-batch=2048 \
    $dnndir/final.nnet "$nnet_feats" ark:- \
    \| select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- \
    \| logprob-to-post --min-post=$min_post ark:- "ark:|gzip -c >$dir/post.JOB.gz"

  post_dir=$dir
fi

if [ $stage -le 1 ]; then
  echo "$0: extracting iVectors"
  $cmd JOB=1:$nj $dir/log/extract_ivectors.JOB.log \
    ivector-extract --verbose=2 $srcdir/final.ie "$feats" "ark,s,cs:gunzip -c $post_dir/post.JOB.gz|" \
      ark,scp,t:$dir/ivector.JOB.ark,$dir/ivector.JOB.scp
fi

if [ $stage -le 2 ]; then
  echo "$0: combining iVectors across jobs"
  for j in $(seq $nj); do cat $dir/ivector.$j.scp; done >$dir/ivector.scp
fi

if [ $stage -le 3 ]; then
  # Be careful here: the speaker-level iVectors are now length-normalized,
  # even if they are otherwise the same as the utterance-level ones.
  echo "$0: computing mean of iVectors for each speaker and length-normalizing"
  $cmd $dir/log/speaker_mean.log \
    ivector-normalize-length scp:$dir/ivector.scp  ark:- \| \
    ivector-mean ark:$data/spk2utt ark:- ark:- ark,t:$dir/num_utts.ark \| \
    ivector-normalize-length ark:- ark,scp:$dir/spk_ivector.ark,$dir/spk_ivector.scp
fi

}
