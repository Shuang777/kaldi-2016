#!/bin/bash 

# Copyright 2012  Karel Vesely, Daniel Povey
# Apache 2.0
# To be run from .. (one directory up from here)
# see ../run.sh for example

# Begin configuration section.
nj=4
cmd=run.pl
transform_dir=
feat_type=raw
remove_last_layers=4 # remove N last components from the nnet
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 5 ]; then
   echo "usage: $0 [options] <tgt-data-dir> <src-data-dir> <nnet-dir> <log-dir> <abs-path-to-bn-feat-dir>";
   echo "options: "
   echo "  --trim-transforms <N>                            # number of NNet Components to remove from the end"
   echo "  --nj <nj>                                        # number of parallel jobs"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   exit 1;
fi

if [ -f path.sh ]; then . path.sh; fi

data=$1
srcdata=$2
nndir=$3
logdir=$4
bnfeadir=$5

######## CONFIGURATION

# copy the dataset metadata from srcdata.
mkdir -p $data || exit 1;
cp $srcdata/* $data 2>/dev/null; 
[ -f $data/feats.scp ] && rm $data/feats.scp; 
[ -f $data/cmvn.scp ] && rm $data/cmvn.scp;

[ -f $bnfeadir/raw_bnfea_$name.1.scp ] && rm $bnfeadir/raw_bnfea_$name.*.scp

# make $bnfeadir an absolute pathname.
bnfeadir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $bnfeadir ${PWD}`

# use "name" as part of name of the archive.
name=`basename $data`

mkdir -p $bnfeadir || exit 1;
mkdir -p $data || exit 1;
mkdir -p $logdir || exit 1;


srcscp=$srcdata/feats.scp
scp=$data/feats.scp

required="$srcscp $nndir/final.nnet"

for f in $required; do
  if [ ! -f $f ]; then
    echo "$0: no such file $f"
    exit 1;
  fi
done

if [ ! -d $srcdata/split$nj -o $srcdata/split$nj -ot $srcdata/feats.scp ]; then
  utils/split_data.sh $srcdata $nj
fi


#cut the MLP
nnet=$bnfeadir/feature_extractor.nnet
nnet-copy --remove-last-layers=$remove_last_layers --binary=false $nndir/final.nnet $nnet 2>$logdir/feature_extractor.log

#get the feature transform
feature_transform=$nndir/final.feature_transform

echo "Creating bn-feats into $data"

if [ -z "$feat_type" ]; then
  feat_type=delta;
  if [ ! -z "$transform_dir" ] && [ -f $transform_dir/final.mat ]; then
    feat_type=lda;
    if [ -f $transform_dir/trans.1 ]; then
      feat_type=fmllr;
    fi
  fi
fi

###
### Prepare feature pipeline
## Set up features.
sdata=$srcdata/split$nj
if [ "$feat_type" == "lda" ]; then
  echo "$0: feature type is $feat_type"
  norm_vars=`cat $transform_dir/norm_vars 2>/dev/null` || norm_vars=false # cmn/cmvn option, default false.
  feats="ark,s,cs:apply-cmvn --norm-vars=$norm_vars --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $nndir/final.mat ark:- ark:- |"
  if [ ! -z "$transform_dir" ]; then
    echo "$0: using transforms from $transform_dir"
    if [ "$feat_type" == "lda" ]; then
      [ ! -f $transform_dir/trans.1 ] && echo "$0: no such file $transform_dir/trans.1" && exit 1;
      [ "$nj" -ne "`cat $transform_dir/num_jobs`" ] \
        && echo "$0: #jobs mismatch with transform-dir." && exit 1;
      feats="$feats transform-feats --utt2spk=ark:$sdata/JOB/utt2spk ark,s,cs:$transform_dir/trans.JOB ark:- ark:- |"
    else
      [ ! -f $transform_dir/raw_trans.1 ] && echo "$0: no such file $transform_dir/raw_trans.1" && exit 1;
      [ "$nj" -ne "`cat $transform_dir/num_jobs`" ] \
        && echo "$0: #jobs mismatch with transform-dir." && exit 1;
      feats="$feats transform-feats --utt2spk=ark:$sdata/JOB/utt2spk ark,s,cs:$transform_dir/raw_trans.JOB ark:- ark:- |"
    fi
  elif grep 'transform-feats --utt2spk' $srcdir/log/train.1.log >&/dev/null; then
    echo "$0: **WARNING**: you seem to be using a neural net system trained with transforms,"
    echo "  but you are not providing the --transform-dir option in test time."
  fi
elif [ $feat_type == "raw" ]; then
  feats="ark,s,cs:copy-feats scp:$sdata/JOB/feats.scp ark:- |"
  # Optionally add cmvn
  if [ -f $nndir/norm_vars ]; then
    norm_vars=$(cat $nndir/norm_vars 2>/dev/null)
    feats="$feats apply-cmvn --norm-vars=$norm_vars --utt2spk=ark:$srcdata/utt2spk scp:$srcdata/cmvn.scp ark:- ark:- |"
  fi
  # Optionally add deltas
  if [ -f $nndir/delta_order ]; then
    delta_order=$(cat $nndir/delta_order)
    feats="$feats add-deltas --delta-order=$delta_order ark:- ark:- |"
  fi
  ###
  ###
else
  echo "feat_type $feat_type not supported"
  exit 1
fi

#Run the forward pass
$cmd JOB=1:$nj $logdir/make_bnfeats_$name.JOB.log \
  nnet-forward --feature-transform=$feature_transform $nnet "$feats" \
  ark,scp:$bnfeadir/raw_bnfea_$name.JOB.ark,$bnfeadir/raw_bnfea_$name.JOB.scp \
  || exit 1;


N0=$(cat $srcdata/feats.scp | wc -l) 
N1=$(cat $bnfeadir/raw_bnfea_$name.*.scp | wc -l)
if [[ "$N0" != "$N1" ]]; then
  echo "Error producing bnfea features for $name:"
  echo "Original feats : $N0  Bottleneck feats : $N1"
  exit 1;
fi

# concatenate the .scp files together.
for ((n=1; n<=nj; n++)); do
  cat $bnfeadir/raw_bnfea_$name.$n.scp >> $data/feats.scp
done


echo "Succeeded creating MLP-BN features for $name ($data)"

