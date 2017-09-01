#!/bin/bash
{
set -e
set -o pipefail

# Copyright 2013  Daniel Povey
#      2014-2015  David Snyder
#           2015  Johns Hopkins University (Author: Daniel Garcia-Romero)
#           2015  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0.

# Begin configuration section.
nj=10   # this is the number of separate queue jobs we run, but each one 
        # contains num_processes sub-jobs.. the real number of threads we 
        # run is nj * num_processes * num_threads, and the number of
        # separate pieces of data is nj * num_processes.
num_threads=4
cmd="run.pl"
stage=-4
num_gselect=20 # Gaussian-selection using diagonal model: number of Gaussians to select
ivector_dim=400 # dimension of the extracted i-vector
use_weights=false # set to true to turn on the regression of log-weights on the ivector.
num_iters=10
min_post=0.025 # Minimum posterior to use (posteriors below this are pruned out)
num_samples_for_weights=3 # smaller than the default for speed (relates to a sampling method)
cleanup=true
posterior_scale=1.0 # This scale helps to control for successve features being highly
                    # correlated.  E.g. try 0.1 or 0.3
sum_accs_opt=
post_from=
feat_type=raw
transform_dir=
splice_opts=
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;


if [ $# != 5 ]; then
  echo "Usage: $0 <fgmm-model> <dnn-dir> <data-speaker-id> <data-dnn> <extractor-dir>"
  echo " e.g.: $0 exp/sup_ubm/final.ubm exp/dnn data/train data/train_dnn exp/extractor_male"
  echo "main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config containing options"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --num-iters <#iters|10>                          # Number of iterations of E-M"
  echo "  --nj <n|10>                                      # Number of jobs (also see num-processes and num-threads)"
  echo "  --num-threads <n|4>                              # Number of threads for each process (can't be usefully"
  echo "                                                   # increased much above 4)"
  echo "  --stage <stage|-4>                               # To control partial reruns"
  echo "  --num-gselect <n|20>                             # Number of Gaussians to select using"
  echo "                                                   # diagonal model."
  echo "  --sum-accs-opt <option|''>                       # Option e.g. '-l hostname=a15' to localize"
  echo "                                                   # sum-accs process to nfs server."
  exit 1;
fi

fgmm_model=$1
dnndir=$2
data=$3
data_dnn=$4
dir=$5

srcdir=$(dirname $fgmm_model)

for f in $fgmm_model $data/feats.scp ; do
  [ ! -f $f ] && echo "No such file $f" && exit 1;
done

# Set various variables.
mkdir -p $dir/log
sdata=$data/split$nj;
utils/split_data.sh $data $nj || exit 1;

sdata_dnn=$data_dnn/split$nj;
utils/split_data.sh $data_dnn $nj || exit 1;

delta_opts=`cat $srcdir/delta_opts 2>/dev/null`
if [ -f $srcdir/delta_opts ]; then
  cp $srcdir/delta_opts $dir/ 2>/dev/null
fi

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

parallel_opts="-pe smp $num_threads"
## Set up features.
feats="ark,s,cs:add-deltas $delta_opts scp:$sdata/JOB/feats.scp ark:- | apply-cmvn-sliding --norm-vars=false --center=true --cmn-window=300 ark:- ark:- | select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- |"

# Initialize the i-vector extractor using the FGMM input
if [ $stage -le -2 ]; then
  cp $fgmm_model $dir/final.ubm || exit 1;
  $cmd $dir/log/convert.log \
    fgmm-global-to-gmm $dir/final.ubm $dir/final.dubm || exit 1;
  $cmd $dir/log/init.log \
    ivector-extractor-init --ivector-dim=$ivector_dim --use-weights=$use_weights \
     $dir/final.ubm $dir/0.ie || exit 1;
fi 

# Do Gaussian selection and posterior extracion
if [ ! -z $post_from ]; then
  post_dir=$post_from
  if ! [ $nj -eq $(cat $post_dir/num_jobs) ]; then
    echo "Num-jobs mismatch $nj versus $(cat $post_dir/num_jobs)"
    exit 1
  fi
elif [ $stage -le -1 ]; then
  echo $nj > $dir/num_jobs
  echo "$0: doing DNN posterior computation"
  $cmd JOB=1:$nj $logdir/gen_post.JOB.log \
    python3 steps_tf/nnet_forward.py --transform $transform_dir/$trans \
    $sdata_dnn/JOB $dnndir/$model_name \| \
    select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- \| \
    prob-to-post --min-post=$min_post ark:- "ark:|gzip -c > $dir/post.JOB.gz"

  post_dir=$dir
else
  if ! [ $nj -eq $(cat $dir/num_jobs) ]; then
    echo "Num-jobs mismatch $nj versus $(cat $dir/num_jobs)"
    exit 1
  fi
  post_dir=$dir
fi

x=0
while [ $x -lt $num_iters ]; do
  if [ $stage -le $x ]; then
    $cmd $parallel_opts JOB=1:$nj $dir/log/acc.$x.JOB.log \
      ivector-extractor-acc-stats --num-threads=$num_threads \
      --num-samples-for-weights=$num_samples_for_weights $dir/$x.ie \
      "$feats" "ark,s,cs:gunzip -c $post_dir/post.JOB.gz|" $dir/acc.$x.JOB

  	accs=""
  	for j in $(seq $nj); do
  	  accs+="$dir/acc.$x.$j "
  	done
  	echo "Summing accs (pass $x)"
  	$cmd $sum_accs_opt $dir/log/sum_acc.$x.log \
  	  ivector-extractor-sum-accs $accs $dir/acc.$x
      echo "Updating model (pass $x)"
  	
    $cmd -pe smp $num_threads $dir/log/update.$x.log \
      ivector-extractor-est --num-threads=$num_threads $dir/$x.ie $dir/acc.$x $dir/$[$x+1].ie
  	rm $dir/acc.$x.*
    if $cleanup; then
      rm $dir/acc.$x
      # rm $dir/$x.ie
    fi
  fi
  x=$[$x+1]
done

ln -s $x.ie $dir/final.ie
}
