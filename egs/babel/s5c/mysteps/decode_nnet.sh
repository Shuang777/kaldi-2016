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
feature_transform=  # non-default location of feature_transform (optional)
model=              # non-default location of transition model (optional)
class_frame_counts= # non-default location of PDF counts (optional)
srcdir=             # non-default location of DNN-dir (decouples model dir from decode dir)
transform_dir=      # dir to find fMLLR transforms

stage=0 # stage=1 skips lattice generation
nj=4
cmd=run.pl

acwt=0.10 # note: only really affects pruning (scoring is on lattices).
beam=13.0
latbeam=8.0
max_active=7000 # limit of active tokens
max_mem=50000000 # approx. limit to memory consumption during minimization in bytes

skip_scoring=false
scoring_opts="--min-lmwt 4 --max-lmwt 15"
splice_opts=

num_threads=1 # if >1, will use latgen-faster-parallel
parallel_opts="-pe smp $((num_threads+1))" # use 2 CPUs (1 DNN-forward, 1 decoder)
use_gpu="no" # yes|no|optionaly
align_lex=false
feat_type=
no_softmax=true

utt2spk=
ivector_scp=

utt_mode=false
# End configuration section.

echo "$0 $@"  # Print the command line for logging

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

if [ $# != 3 ]; then
   echo "Usage: $0 [options] <graph-dir> <data-dir> <decode-dir>"
   echo "... where <decode-dir> is assumed to be a sub-directory of the directory"
   echo " where the DNN and transition model is."
   echo "e.g.: $0 exp/dnn1/graph_tgpr data/test exp/dnn1/decode_tgpr"
   echo ""
   echo "This script works on plain or modified features (CMN,delta+delta-delta),"
   echo "which are then sent through feature-transform. It works out what type"
   echo "of features you used from content of srcdir."
   echo ""
   echo "main options (for others, see top of script file)"
   echo "  --transform-dir <decoding-dir>                   # directory of previous decoding"
   echo "                                                   # where we can find transforms for SAT systems."
   echo "  --config <config-file>                           # config containing options"
   echo "  --nj <nj>                                        # number of parallel jobs"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   echo ""
   echo "  --nnet <nnet>                                    # non-default location of DNN (opt.)"
   echo "  --srcdir <dir>                                   # non-default dir with DNN/models, can be different"
   echo "                                                   # from parent dir of <decode-dir>' (opt.)"
   echo ""
   echo "  --acwt <float>                                   # select acoustic scale for decoding"
   echo "  --scoring-opts <opts>                            # options forwarded to local/score.sh"
   echo "  --num-threads <N>                                # N>1: run multi-threaded decoder"
   exit 1;
fi


graphdir=$1
data=$2
dir=$3
[ -z $srcdir ] && srcdir=`dirname $dir`; # Default model directory one level up from decoding directory.
sdata=$data/split$nj;

mkdir -p $dir/log

if $utt_mode; then
  sdata=$data/split${nj}utt;
fi

mkdir -p $dir/log
$utt_mode && utt_opts='--per-utt'

[[ -d $sdata && $data/feats.scp -ot $sdata ]] || split_data.sh $utt_opts $data $nj

echo $nj > $dir/num_jobs

# Select default locations to model files (if not already set externally)
if [ -z "$nnet" ]; then nnet=$srcdir/final.nnet; fi
if [ -z "$model" ]; then model=$srcdir/final.mdl; fi
if [ -z "$feature_transform" ]; then feature_transform=$srcdir/final.feature_transform; fi
if [ -z "$class_frame_counts" ]; then class_frame_counts=$srcdir/ali_train_pdf.counts; fi

# Check that files exist
for f in $sdata/1/feats.scp $nnet $model $feature_transform $class_frame_counts $graphdir/HCLG.fst; do
  [ ! -f $f ] && echo "$0: missing file $f" && exit 1;
done

# Possibly use multi-threaded decoder
thread_string=
[ $num_threads -gt 1 ] && thread_string="-parallel --num-threads=$num_threads" 


# PREPARE FEATURE EXTRACTION PIPELINE
## Set up features.
if [ -z "$feat_type" ]; then
  if [ -f $srcdir/final.mat ]; then feat_type=lda; else feat_type=raw; fi
  echo "$0: feature type is $feat_type"
fi

[ -f $srcdir/cmvn_opts ] && cmvn_opts=`cat $srcdir/cmvn_opts 2>/dev/null`
cmvn_type=channel
[ -f $srcdir/cmvn_type ] && cmvn_type=`cat $srcdir/cmvn_type 2>/dev/null`

if [ $cmvn_type == sliding ]; then
  cmvn_feats="apply-cmvn-sliding $cmvn_opts --center=true --cmn-window=300"
elif [ $cmvn_type == channel ]; then
  cmvn_feats="apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp"
else
  echo "Wrong cmvn_type $cmvn_type" && exit 1
fi

if [ $feat_type == lda ] || [ $feat_type == fmllr ]; then
  if [ -f $srcdir/splice_opts ]; then
    splice_opts=`cat $srcdir/splice_opts 2>/dev/null`
    cp $srcdir/splice_opts $dir 2>/dev/null
  fi
  cp $srcdir/final.mat $dir
  cp $srcdir/tree $dir
fi

# Create the feature stream:
case $feat_type in
  raw) feats="scp:$sdata/JOB/feats.scp ark:- |";;
  cmvn|traps) feats="ark,s,cs:$cmvn_feats scp:$sdata/JOB/feats.scp ark:- |";;
  delta) feats="ark,s,cs:$cmvn_feats scp:$sdata/JOB/feats.scp ark:- | add-deltas ark:- ark:- |";;
  lda|fmllr) feats="ark,s,cs:$cmvn_feats scp:$sdata/JOB/feats.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $srcdir/final.mat ark:- ark:- |" ;;
  *) echo "$0: invalid feature type $feat_type" && exit 1;
esac
if [ ! -z "$transform_dir" ]; then
  echo "$0: using transforms from $transform_dir"
  [ ! -s $transform_dir/num_jobs ] && \
    echo "$0: expected $transform_dir/num_jobs to contain the number of jobs." && exit 1;
  nj_orig=$(cat $transform_dir/num_jobs)

  if [ $feat_type == "raw" ]; then trans=raw_trans;
  else trans=trans; fi

  if [ $feat_type == "lda" ] && \
    ! cmp $transform_dir/../final.mat $srcdir/final.mat && \
    ! cmp $transform_dir/final.mat $srcdir/final.mat; then
    echo "$0: LDA transforms differ between $srcdir and $transform_dir"
    exit 1;
  fi
  if [ ! -f $transform_dir/$trans.1 ]; then
    echo "$0: expected $transform_dir/$trans.1 to exist (--transform-dir option)"
    exit 1;
  fi
  if [ $nj -ne $nj_orig ]; then
    # Copy the transforms into an archive with an index.
    for n in $(seq $nj_orig); do cat $transform_dir/$trans.$n; done | \
       copy-feats ark:- ark,scp:$dir/$trans.ark,$dir/$trans.scp || exit 1;
    feats="$feats transform-feats --utt2spk=ark:$sdata/JOB/utt2spk scp:$dir/$trans.scp ark:- ark:- |"
  else
    # number of jobs matches with alignment dir.
    feats="$feats transform-feats --utt2spk=ark:$sdata/JOB/utt2spk ark:$transform_dir/$trans.JOB ark:- ark:- |"
  fi
elif grep 'transform-feats --utt2spk' $srcdir/log/train.1.log >&/dev/null; then
  echo "$0: **WARNING**: you seem to be using a neural net system trained with transforms,"
  echo "  but you are not providing the --transform-dir option in test time."
fi
##

aligncmd="lattice-align-words $graphdir/phones/word_boundary.int"
[ ! -f $graphdir/phones/word_boundary.int ] && align_lex=true
[ $align_lex == "true" ] && aligncmd="lattice-align-words-lexicon $graphdir/phones/align_lexicon.int"

[ "$no_softmax" == true ] && extraopts="--no-softmax=true" || extraopts="--apply-log=true"

# Run the decoding in the queue
if [ $stage -le 0 ]; then
  $cmd $parallel_opts JOB=1:$nj $dir/log/decode.JOB.log \
    nnet-forward --feature-transform=$feature_transform "$extraopts" \
    ${utt2spk:+ --utt2spk-rspecifier=ark:$utt2spk} \
    ${ivector_scp:+ --ivector-rspecifier=scp:$ivector_scp} \
    --frames-per-batch=2048 \
    --class-frame-counts=$class_frame_counts --use-gpu=$use_gpu $nnet "$feats" ark:- \| \
    latgen-faster-mapped$thread_string --max-active=$max_active --max-mem=$max_mem --beam=$beam \
    --lattice-beam=$latbeam --acoustic-scale=$acwt --allow-partial=true --word-symbol-table=$graphdir/words.txt \
    $model $graphdir/HCLG.fst ark:- ark:- \| \
    $aligncmd "$model" ark:- \
    "ark:|gzip -c > $dir/lat.JOB.gz" || exit 1;
  touch $dir/.done.align
fi

# Run the scoring
if ! $skip_scoring ; then
  if [ -x mylocal/score.sh ]; then
    mylocal/score.sh $scoring_opts --cmd "$cmd" $data $graphdir $dir
  elif [ -x local/score.sh ]; then
    local/score.sh $scoring_opts --cmd "$cmd" $data $graphdir $dir
  else
    echo "Not scoring because neither mylocal/score.sh nor local/score.sh is found"
    exit 1
  fi
fi

}
