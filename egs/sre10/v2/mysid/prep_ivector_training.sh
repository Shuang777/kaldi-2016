#!/bin/bash

{
set -e
set -o pipefail

stage=0
nj=10
cmd="run.pl"
num_gselect=20 # Gaussian-selection using diagonal model: number of Gaussians to select
posterior_scale=1.0 # This scale helps to control for successve features being highly
min_post=0.025 # Minimum posterior to use (posteriors below this are pruned out)

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh


if [ $# != 2 ]; then
  echo "Usage: $0 <fgmm-model-dir> <data>"
  echo " e.g.: $0 exp/ubm_2048_male data/train_male"
  echo "main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config containing options"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --nj <n|10>                                      # Number of jobs (also see num-processes and num-threads)"
  echo "  --num-gselect <n|20>                             # Number of Gaussians to select using"
  echo "                                                   # diagonal model."
  exit 1;
fi

dir=$1
data=$2

for f in $dir/final.ubm $data/feats.scp ; do
  [ ! -f $f ] && echo "No such file $f" && exit 1;
done

# Set various variables.
mkdir -p $dir/log
sdata=$data/split$nj
utils/split_data.sh $data $nj

delta_opts=`cat $dir/delta_opts 2>/dev/null`

## Set up features.
feats="ark,s,cs:add-deltas $delta_opts scp:$sdata/JOB/feats.scp ark:- | apply-cmvn-sliding --norm-vars=false --center=true --cmn-window=300 ark:- ark:- | select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- |"

# Initialize the i-vector extractor using the FGMM input
if [ $stage -le 0 ]; then
  $cmd $dir/log/convert.log \
    fgmm-global-to-gmm $dir/final.ubm $dir/final.dubm
fi 

# Do Gaussian selection and posterior extracion

if [ $stage -le 1 ]; then
  echo $nj > $dir/num_jobs
  echo "$0: doing Gaussian selection and posterior computation"
  $cmd JOB=1:$nj $dir/log/gselect.JOB.log \
    gmm-gselect --n=$num_gselect $dir/final.dubm "$feats" ark:- \| \
    fgmm-global-gselect-to-post --min-post=$min_post $dir/final.ubm "$feats" \
      ark,s,cs:-  ark:- \| \
    scale-post ark:- $posterior_scale "ark:|gzip -c >$dir/post.JOB.gz"
fi

}
