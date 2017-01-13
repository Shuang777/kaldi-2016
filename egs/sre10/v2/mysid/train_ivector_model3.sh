#!/bin/bash
{
set -e
set -o pipefail
# Copyright   2013  Daniel Povey
#             2014  David Snyder
# Apache 2.0.

# This script trains the i-vector extractor.  Note: there are 3 separate levels
# of parallelization: num_threads, num_processes, and num_jobs.  This may seem a
# bit excessive.  It has to do with minimizing memory usage and disk I/O,
# subject to various constraints.  The "num_threads" is how many threads a
# program uses; the "num_processes" is the number of separate processes a single
# job spawns, and then sums the accumulators in memory.  Our recommendation:
#  - Set num_threads to the minimum of (4, or how many virtual cores your machine has).
#    (because of needing to lock various global quantities, the program can't
#    use many more than 4 threads with good CPU utilization).
#  - Set num_processes to the number of virtual cores on each machine you have, divided by 
#    num_threads.  E.g. 4, if you have 16 virtual cores.   If you're on a shared queue
#    that's busy with other people's jobs, it may be wise to set it to rather less
#    than this maximum though, or your jobs won't get scheduled.  And if memory is
#    tight you need to be careful; in our normal setup, each process uses about 5G.
#  - Set num_jobs to as many of the jobs (each using $num_threads * $num_processes CPUs)
#    your queue will let you run at one time, but don't go much more than 10 or 20, or
#    summing the accumulators will possibly get slow.  If you have a lot of data, you
#    may want more jobs, though.

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

srcdir=$1
data=$2
dir=$3

for f in $data/feats.scp ; do
  [ ! -f $f ] && echo "No such file $f" && exit 1;
done

# Set various variables.
mkdir -p $dir/log
sdata=$data/split$nj
utils/split_data.sh $data $nj

delta_opts=`cat $srcdir/delta_opts 2>/dev/null`
if [ -f $srcdir/delta_opts ]; then
  cp $srcdir/delta_opts $dir/ 2>/dev/null
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
  $cmd $dir/log/init.log \
    ivector3-model-init --ivector-dim=$ivector_dim --prior-mode=$prior_mode\
     $srcdir/final.ubm $dir/0.ie || exit 1
fi

cp $srcdir/final.dubm $dir
cp $srcdir/final.ubm $dir

x=0
while [ $x -lt $num_iters ]; do
  if [ $stage -le $x ]; then
    $cmd $parallel_opts JOB=1:$nj $dir/log/acc.$x.JOB.log \
      ivector3-model-acc-stats --num-threads=$num_threads $dir/$x.ie "$feats" "ark,s,cs:gunzip -c $srcdir/post.JOB.gz|" $dir/acc.$x.JOB
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
