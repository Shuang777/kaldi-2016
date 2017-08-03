#!/bin/bash

# Copyright 2012/2013  Brno University of Technology (Author: Karel Vesely)
# Apache 2.0
{
set -o pipefail

# Begin configuration.
config=            # config, which is also sent to all other scripts

# NETWORK INITIALIZATION
network_type=dnn   # (dnn,cnn1d,cnn2d,lstm)
#
hid_layers=4       # nr. of hidden layers (prior to sotfmax or bottleneck)
hid_dim=1024       # select hidden dimension
bn_dim=            # set a value to get a bottleneck network
dbn=               # select DBN to prepend to the MLP initialization
#
init_opts=         # options, passed to the initialization script

# FEATURE PROCESSING
splice_transform=true
splice=5         # temporal splicing
splice_step=1    # stepsize of the splicing (1 == no gap between frames)
feat_type=raw       # raw, cmvn or delta
tgt_feat_type=cmvn  # raw, cmvn or delta
feature_transform=
cmvn_opts=
tgt_cmvn_opts="--norm-vars=true"

# TRAINING SCHEDULER
learn_rate=0.008   # initial learning rate
train_opts=        # options, passed to the training script
train_tool=nnet-train-frmshuff-denoise    # optionally change the training tool

# OTHER
cv_base=spk
cv_subset_factor=0.1
resume_anneal=false

# semi-supervised training
min_iters=
max_iters=20

resave=true
seed=777
# End configuration.

echo "$0 $@"  # Print the command line for logging

. path.sh || exit 1;
. parse_options.sh || exit 1;

if [ $# != 3 ]; then
   echo "Usage: $0 <data-dir> <tgt-dir> <exp-dir>"
   echo " e.g.: $0 data/train_renoise data/train exp/mono_nnet"
   echo "  --config <config-file>  # config containing options"
   exit 1;
fi

data=$1
tgt=$2
dir=$3

for f in $data/feats.scp $tgt/feats.scp; do
  [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done

[ -d $dir/log ] || mkdir -p $dir/log

echo
echo "# INFO"
echo "$0 : Training Neural Network"
printf "\t dir       : $dir \n"
printf "\t Train-set : $data $tgt \n"

# shuffle the list
echo "Preparing train/cv lists :"
num_utts_all=$(wc $data/feats.scp | awk '{print $1}')
num_utts_subset=$(awk "BEGIN {print(int( $num_utts_all * $cv_subset_factor))}")
echo "Split out cv feats from training data using cv_base $cv_base"

if [ $cv_base == spk ]; then
  cat $data/spk2utt | utils/shuffle_list.pl --srand ${seed:-777} |\
    awk -v num_utts_subset=$num_utts_subset '
      BEGIN{count=0;} 
      {
        count += NF-1; 
        if (count > num_utts_subset) 
          exit; 
        for(i=2; i<=NF; i++)
          print $i;
      }' > $dir/cv.utt
  cat $data/feats.scp | utils/filter_scp.pl --exclude $dir/cv.utt | \
    utils/shuffle_list.pl --srand ${seed:-777} > $dir/shuffle.train.scp
  cat $data/feats.scp | utils/filter_scp.pl $dir/cv.utt | \
    utils/shuffle_list.pl --srand ${seed:-777} > $dir/shuffle.cv.scp
elif [ $cv_base == utt ]; then
  # chose last num_utts_subset utterance
  tail -$num_utts_subset $data/feats.scp > $dir/shuffle.cv.scp
  cat $data/feats.scp | utils/filter_scp.pl --exclude $dir/shuffle.cv.scp | \
    utils/shuffle_list.pl --srand ${seed:-777} > $dir/shuffle.train.scp
else
  cat $data/feats.scp | utils/shuffle_list.pl --srand ${seed:-777} > $dir/shuffle.scp
  head -$num_utts_subset $dir/shuffle.scp > $dir/shuffle.cv.scp
  cat $dir/shuffle.scp | utils/filter_scp.pl --exclude $dir/shuffle.cv.scp > $dir/shuffle.train.scp
fi

echo "$0: feature type is $feat_type"
case $feat_type in
  raw) feats_tr="scp:$dir/shuffle.train.scp"
       feats_cv="scp:$dir/shuffle.cv.scp"
   ;;
  cmvn) feats_tr="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.train.scp ark:- |"
       feats_cv="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.cv.scp ark:- |"
   ;;
  delta) feats_tr="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.train.scp ark:- | add-deltas $delta_opts ark:- ark:- |"
       feats_cv="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.cv.scp ark:- | add-deltas $delta_opts ark:- ark:- |"
  ;;
  *) echo "$0: invalid feature type $feat_type" && exit 1;
esac
 
case $tgt_feat_type in 
  raw) feats_tgt="ark:copy-feats scp:$tgt/feats.scp ark:- |"
    ;;
  cmvn) feats_tgt="ark:apply-cmvn $tgt_cmvn_opts --utt2spk=ark:$tgt/utt2spk scp:$tgt/cmvn.scp scp:$tgt/feats.scp ark:- |"
    ;;
  delta) feats_tgt="ark:apply-cmvn $tgt_cmvn_opts --utt2spk=ark:$tgt/utt2spk scp:$tgt/cmvn.scp scp:$tgt/feats.scp ark:- | add-deltas $delta_opts ark:- ark:- |"
    ;;
  *) echo "$0: invalid target feature type $tgt_feat_type" && exit 1;
esac

tgt1=$(echo $feats_tgt | sed "s#scp:$tgt\/feats.scp#'scp:head -1 $tgt\/feats.scp |'##")
tgt_tr="$feats_tgt"
tgt_cv="$feats_tgt"

echo "$tgt_feat_type" > $dir/tgt_feat_type

#get feature dim
# re-save the shuffled features, so they are stored sequentially on the disk in /tmp/
if [ $resave == true ]; then
  tmpdir=$dir/feature_shuffled; mkdir -p $tmpdir; 
  copy-feats "$feats_tr" ark,scp:$tmpdir/feats.tr.ark,$dir/train.scp
  copy-feats "$feats_cv" ark,scp:$tmpdir/feats.cv.ark,$dir/cv.scp
  # remove data on exit...
  [ "$clean_up" == true ] && trap "echo \"Removing features tmpdir $tmpdir @ $(hostname)\"; rm -r $tmpdir" EXIT
else
  [ -f $dir/train.scp ] && rm -f $dir/train.scp
  [ -f $dir/cv.scp ] && rm -f $dir/cv.scp
  (cd $dir; ln -s shuffle.train.scp train.scp; ln -s shuffle.cv.scp cv.scp)
fi

# print the list sizes
wc -l $dir/train.scp $dir/cv.scp
feats_tr="ark:copy-feats scp:$dir/train.scp ark:- |"
feats_cv="ark:copy-feats scp:$dir/cv.scp ark:- |"
echo substituting feats_tr with $feats_tr
echo substituting feats_cv with $feats_cv

#create a 10k utt subset for global cmvn estimates
head -n 10000 $dir/train.scp > $dir/train.scp.10k

# get feature dim
echo "Getting feature dim : "
feats_tr1=$(echo $feats_tr | sed -e "s#scp:$dir/train.scp#\"scp:head -1 $dir/train.scp |\"#g")
feat_dim=$(feat-to-dim --print-args=false "$feats_tr1" -)
echo "Feature dim is : $feat_dim"

# raw input
if [ ! -z "$feature_transform" ]; then
  echo "Using pre-computed feature-transform : '$feature_transform'"
  tmp=$dir/$(basename $feature_transform) 
  cp $feature_transform $tmp; feature_transform=$tmp
elif [ "$splice_transform" == true ]; then
  # Generate the splice transform
  echo "Using splice +/- $splice , step $splice_step"
  feature_transform=$dir/tr_splice$splice-$splice_step.nnet
  utils/nnet/gen_splice.py --fea-dim=$feat_dim --splice=$splice --splice-step=$splice_step > $feature_transform

  # Renormalize the MLP input to zero mean and unit variance
  feature_transform_old=$feature_transform
  feature_transform=${feature_transform%.nnet}_cmvn-g.nnet
  echo "Renormalizing MLP input features into $feature_transform"
  nnet-forward --use-gpu=yes \
    $feature_transform_old "$(echo $feats_tr | sed 's|train.scp|train.scp.10k|')" \
    ark:- 2>$dir/log/nnet-forward-cmvn.log |\
  compute-cmvn-stats ark:- - | cmvn-to-nnet - - |\
  nnet-concat --binary=false $feature_transform_old - $feature_transform
else
  feature_transform=$dir/cmvn-g.nnet
  compute-cmvn-stats "$(echo $feats_tr | sed 's|train.scp|train.scp.10k|')" - |\
  cmvn-to-nnet --binary=false - $feature_transform
fi

###### MAKE LINK TO THE FINAL feature_transform, so the other scripts will find it ######
(cd $dir; [ ! -f final.feature_transform ] && ln -s $(basename $feature_transform) final.feature_transform )


[ ! -z "$mlp_init" ] && echo "Using pre-initialized network '$mlp_init'";
if [ ! -z "$mlp_proto" ]; then 
  echo "Initializing using network prototype '$mlp_proto'";
  mlp_init=$dir/nnet.init; log=$dir/log/nnet_initialize.log
  nnet-initialize $mlp_proto $mlp_init 2>$log || { cat $log; exit 1; } 
fi

if [[ -z "$mlp_init" && -z "$mlp_proto" ]]; then
  #initializing the MLP, get the i/o dims...
  #input-dim
  num_fea=$(feat-to-dim "$feats_tr1 nnet-forward $feature_transform ark:- ark:- |" - )
  num_tgt=$(feat-to-dim "$tgt1" -)
  echo "Getting input/output dims : $num_fea/$num_tgt"

  # make network prototype
  mlp_proto=$dir/nnet.proto
  echo "Genrating network prototype $mlp_proto"
  case "$network_type" in
    dnn)
      myutils/nnet/make_nnet_proto.py $proto_opts \
        --no-softmax --top-linear \
        ${bn_dim:+ --bottleneck-dim=$bn_dim} \
        $num_fea $num_tgt $hid_layers $hid_dim >$mlp_proto
      ;;
    lstm)
      utils/nnet/make_lstm_proto.py $proto_opts \
        $num_fea $num_tgt >$mlp_proto || exit 1 
      ;;
    *) echo "Unknown : --network-type $network_type" && exit 1
  esac

  # initialize
  mlp_init=$dir/nnet.init; log=$dir/log/nnet_initialize.log
  echo "Initializing $mlp_proto -> $mlp_init"
  nnet-initialize $mlp_proto $mlp_init 2>$log || { cat $log; exit 1; }

  #optionally prepend dbn to the initialization
  if [ ! -z $dbn ]; then
    mlp_init_old=$mlp_init; mlp_init=$dir/nnet_$(basename $dbn)_dnn.init
    nnet-concat $dbn $mlp_init_old $mlp_init || exit 1 
  fi
fi

echo "# RUNNING THE NN-TRAINING SCHEDULER"
mysteps/train_nnet_scheduler.sh \
  --feature-transform $feature_transform \
  --learn-rate $learn_rate \
  --randomizer-seed $seed \
  --resume-anneal $resume_anneal \
  --max-iters $max_iters \
  --obj mse \
  ${min_iters:+ --min-iters $min_iters} \
  ${train_opts} \
  ${train_tool:+ --train-tool "$train_tool"} \
  ${config:+ --config $config} \
  $mlp_init "$feats_tr" "$feats_cv" "$tgt_tr" "$tgt_cv" $dir 


echo "$0 successfuly finished.. $dir"

exit 0
}
