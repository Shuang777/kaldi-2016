#!/bin/bash
{
set -e
set -o pipefail

# Copyright   2016  Hang Su
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
num_iters=5
min_post=0.025 # Minimum posterior to use (posteriors below this are pruned out)
num_samples_for_weights=3 # smaller than the default for speed (relates to a sampling method)
cleanup=true
posterior_scale=1.0 # This scale helps to control for successve features being highly
                    # correlated.  E.g. try 0.1 or 0.3
prior_mode=false
update_prior=false
sum_accs_opt=
lambda=1.0

feat_type=raw     # we also support lda
splice_opts=
transform_dir=
uttspk=utt
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;


if [ $# != 3 ]; then
  echo "Usage: $0 <fgmm-model-dir> <data> <extractor-dir>"
  echo " e.g.: $0 exp/ubm_2048_male/final.ubm data/train_male exp/extractor_male"
  echo "main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config containing options"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --num-iters <#iters|10>                          # Number of iterations of E-M"
  echo "  --nj <n|10>                                      # Number of jobs (also see num-processes and num-threads)"
  echo "  --num-processes <n|4>                            # Number of processes for each queue job (relates"
  echo "                                                   # to summing accs in memory)"
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
data=$2
dir=$3

srcdir=$(dirname $fgmm_model)

for f in $data/feats.scp ; do
  [ ! -f $f ] && echo "No such file $f" && exit 1;
done

# Set various variables.
mkdir -p $dir/log
sdata=$data/split$nj
utils/split_data.sh $data $nj

if [ -f $srcdir/delta_opts ]; then
  cp $srcdir/delta_opts $dir/ 2>/dev/null
  delta_opts=`cat $srcdir/delta_opts`
fi

parallel_opts="-pe smp $num_threads"
## Set up features.
if [ $feat_type == raw ]; then
  feats="ark,s,cs:add-deltas $delta_opts scp:$sdata/JOB/feats.scp ark:- | apply-cmvn-sliding --norm-vars=false --center=true --cmn-window=300 ark:- ark:- | select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- |"
elif [ $feat_type == lda ] || [ $feat_type == fmllr ] ; then
  [ -z $transform_dir ] && echo "no transform_dir given" && exit 1
  feats="ark:apply-cmvn --norm-vars=false --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $transform_dir/final.mat ark:- ark:- |"
else
  echo "feat_type $feat_type not supported" && exit 1
fi

if [ $feat_type == fmllr ]; then
  [ ! -f $transform_dir/trans.1 ] && echo "$transform_dir/trans.1 not found!" && exit 1
  feats="$feats transform-feats --utt2spk=ark:$sdata/JOB/utt2spk 'ark:cat $transform_dir/trans.*|' ark:- ark:- |"
fi

if [ $uttspk == spk ]; then
  feats="$feats concat-feats-spk ark:- ark:$sdata/JOB/utt2spk ark:- |"
fi

# Initialize the i-vector extractor using the FGMM input
if [ $stage -le -2 ]; then
  cp $fgmm_model $dir/final.ubm || exit 1;
  $cmd $dir/log/convert.log \
    fgmm-global-to-gmm $dir/final.ubm $dir/final.dubm || exit 1;
  $cmd $dir/log/init.log \
    ivector3-model-init --ivector-dim=$ivector_dim --prior-mode=$prior_mode --lambda=$lambda \
     $srcdir/final.ubm $dir/0.ie || exit 1
fi

# Do Gaussian selection and posterior extracion

if [ $stage -le -1 ]; then
  echo $nj > $dir/num_jobs
  echo "$0: doing Gaussian selection and posterior computation"
  $cmd JOB=1:$nj $dir/log/gselect.JOB.log \
    gmm-gselect --n=$num_gselect $dir/final.dubm "$feats" ark:- \| \
    fgmm-global-gselect-to-post --min-post=$min_post $dir/final.ubm "$feats" \
      ark,s,cs:-  ark:- \| \
    scale-post ark:- $posterior_scale "ark:|gzip -c >$dir/post.JOB.gz" || exit 1;
else
  if ! [ $nj -eq $(cat $dir/num_jobs) ]; then
    echo "Num-jobs mismatch $nj versus $(cat $dir/num_jobs)"
    exit 1
  fi
fi

x=0
while [ $x -lt $num_iters ]; do
  if [ $stage -le $x ]; then
    $cmd $parallel_opts JOB=1:$nj $dir/log/acc.$x.JOB.log \
      ivector3-model-acc-stats --num-threads=$num_threads $dir/$x.ie "$feats" "ark,s,cs:gunzip -c $dir/post.JOB.gz|" $dir/acc.$x.JOB
    accs=""
    for j in $(seq $nj); do
      accs+="$dir/acc.$x.$j "
    done
    echo "Summing accs (pass $x)"
    $cmd $sum_accs_opt $dir/log/sum_acc.$x.log \
      ivector3-model-sum-stats $accs $dir/acc.$x
      echo "Updating model (pass $x)"
    $cmd -pe smp $num_threads $dir/log/update.$x.log \
      ivector3-model-est --num-threads=$num_threads --update-prior=$update_prior $dir/$x.ie $dir/acc.$x $dir/$[$x+1].ie
    rm $dir/acc.$x.*
    if $cleanup; then
      rm $dir/acc.$x
      # rm $dir/$x.ie
    fi
  fi
  x=$[$x+1]
done

[ -f $dir/final.ie ] && rm $dir/final.ie
ln -s $x.ie $dir/final.ie
}
