#!/bin/bash
# Copyright 2013 Karel Vesely

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

# To be run from ..
#
# Deep Belief Network pre-training by Contrastive Divergence (CD-1) algorithm.
# The script can pre-train on plain features (ie. saved fMLLR features), 
# or modified features (CMN, delta).
# The script creates feature-transform in nnet format, which contains splice 
# and shift+scale (zero mean and unit variance on DBN input).
#
# For special cases it is possible to use external feature-transform.
# 
{
set -e

# Begin configuration.
#
# nnet config
nn_depth=6     #number of hidden layers
hid_dim=2048   #number of units per layer
param_stddev_first=0.1 #init parameters in 1st RBM
param_stddev=0.1 #init parameters in other RBMs
input_vis_type=gauss # type of visible nodes on DBN input
# number of iterations
rbm_iter=1            #number of pre-training epochs (Gaussian-Bernoulli RBM has 2x more)
# pre-training opts
rbm_lrate=0.4         #RBM learning rate
rbm_lrate_low=0.01    #lower RBM learning rate (for Gaussian units)
rbm_l2penalty=0.0002  #L2 penalty (increases RBM-mixing rate)
rbm_extra_opts=
# data processing config
# feature config
feat_type=
feature_transform= # Optionally reuse feature processing front-end (override splice,etc.)
feature_transform_proto= # Optionally pass prototype of feature transform
splice=5           # Temporal splicing
splice_step=1      # Stepsize of the splicing (1 is consecutive splice, 
                   # value 2 would do [ -10 -8 -6 -4 -2 0 2 4 6 8 10 ] splicing)
traps_dct_basis=11 # nr. od DCT basis (applies to `traps` feat_type, splice10 )
transdir=
semidata=
semitransdir=
# misc.
verbose=1 # enable per-cache reports

# mpi training
mpi_jobs=0
frames_per_reduce=
reduce_type=

# ivector adaptation
utt2spk=
ivector_scp=

# End configuration.

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh;
. parse_options.sh || exit 1;


if [ $# != 2 ]; then
   echo "Usage: $0 <data> <exp-dir>"
   echo " e.g.: $0 data/train exp/rbm_pretrain"
   echo "main options (for others, see top of script file)"
   echo "  --config <config-file>           # config containing options"
   echo ""
   echo "  --nn-depth <N>                   # number of RBM layers"
   echo "  --hid-dim <N>                    # number of hidden units per layer"
   echo "  --rbm-iter <N>                   # number of CD-1 iterations per layer"
   echo "  --dbm-drop-data <float>          # probability of frame-dropping,"
   echo "                                   # can be used to subsample large datasets"
   echo "  --rbm-lrate <float>              # learning-rate for Bernoulli-Bernoulli RBMs"
   echo "  --rbm-lrate-low <float>          # learning-rate for Gaussian-Bernoulli RBM"
   echo ""
   echo "  --copy-feats <bool>              # copy features to /tmp, to accelerate training"
   echo "  --apply-cmvn <bool>              # normalize input features (opt.)"
   echo "  --norm-vars <bool>               # use variance normalization (opt.)"
   echo "  --splice <N>                     # splice +/-N frames of input features"
   echo "  --ivector-scp                    # ivector scp file for ivector adaptation"
   echo "  --utt2spk                        # utt2spk file for ivector"
   exit 1;
fi

data=$1
dir=$2


for f in $data/feats.scp; do
  [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done

echo "# INFO"
echo "$0 : Pre-training Deep Belief Network as a stack of RBMs"
printf "\t dir       : $dir \n"
printf "\t Train-set : $data \n"

[ -e $dir/${nn_depth}.dbn ] && echo "$0 Skipping, already have $dir/${nn_depth}.dbn" && exit 0

mkdir -p $dir/log

###### PREPARE FEATURES ######
echo
echo "# PREPARING FEATURES"
#read the features
if [ -z "$feat_type" ]; then
  feat_type=delta;
  if [ ! -z "$transdir" ] && [ -f $transdir/final.mat ]; then 
    feat_type=lda;
    if [ -f $transdir/trans.1 ];then
      feat_type=fmllr;
    fi
  fi
fi
echo "$0: feature type is $feat_type"

if [ $feat_type == lda ]; then
  splice_opts=`cat $transdir/splice_opts 2>/dev/null`
  cp $transdir/splice_opts $dir 2>/dev/null
  cp $transdir/final.mat $dir 2>/dev/null # any LDA matrix...
  cp $transdir/tree $dir
fi


# shuffle the list
if [ -z $semidata ]; then
  cat $data/feats.scp | utils/shuffle_list.pl --srand ${seed:-777} > $dir/shuffle.scp
else
  echo "preparing semi-supervised training list"
  cat $data/feats.scp $semidata/feats.scp | utils/shuffle_list.pl --srand ${seed:-777} > $dir/shuffle.scp
  cat $semidata/utt2spk $data/utt2spk | sort > $dir/semitrain.utt2spk
  cat $semidata/cmvn.scp $data/cmvn.scp | sort > $dir/semitrain.cmvn.scp
  (set -e; cd $dir; ln -s semitrain.cmvn.scp cmvn.scp; ln -s semitrain.utt2spk utt2spk)
  data=$dir
fi

case $feat_type in
  raw) feats="scp:$dir/shuffle.scp"
   ;;
  cmvn|traps) feats="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.scp ark:- |"
   ;;
  delta) feats="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.scp ark:- | add-deltas ark:- ark:- |"
   ;;
  lda|fmllr) feats="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $dir/final.mat ark:- ark:- |"
    cp $transdir/final.mat $dir    
   ;;
  *) echo "$0: invalid feature type $feat_type" && exit 1;
esac

if [ -f $transdir/trans.1 ] && [ $feat_type == "fmllr" ]; then
  if [ -z $semitransdir ]; then
    echo "$0: using transforms from $transdir"
    feats="$feats transform-feats --utt2spk=ark:$data/utt2spk 'ark:cat $transdir/trans.*|' ark:- ark:- |"
  else
    echo "$0: using transforms from $transdir and $semitransdir"
    feats="$feats transform-feats --utt2spk=ark:$data/utt2spk 'ark:cat $transdir/trans.* $semitransdir/trans.* |' ark:- ark:- |"
  fi
fi

#re-save the shuffled features, so they are stored sequentially on the disk in /tmp/
echo "Resaving the features for rbm training"
tmpdir=$dir/feature_shuffled; mkdir -p $tmpdir; 
copy-feats "$feats" ark,scp:$tmpdir/feats.ark,$dir/train.scp
#remove data on exit...
trap "echo \"Removing features tmpdir $tmpdir @ $(hostname)\"; rm -r $tmpdir" EXIT

###### PREPARE FEATURE PIPELINE ######
feats="ark:copy-feats scp:$dir/train.scp ark:- |"
feats_tr="$feats"           # overwritten if in MPI mode
echo "Substitute feats with $feats"

# MPI feature preparation
rbm_train_tool=rbm-train-cd1-frmshuff
if [ "$mpi_jobs" != 0 ]; then
  echo "MPI jobs = $mpi_jobs"
  # filter the features
  min_frames_tr=$(feat-to-len scp:$dir/train.scp ark,t:- | sort -k2 -n -r | myutils/distribute_scp.pl $mpi_jobs $dir/train_list)

  for n in $(seq $mpi_jobs); do
    cat $dir/train.scp | utils/filter_scp.pl $dir/train_list.$n.scp > $dir/train.$n.scp
  done

  reduce_per_iter_tr=$(echo "$min_frames_tr/$frames_per_reduce" | bc)

  echo "reduce_per_iter_tr=$reduce_per_iter_tr"

  feats_tr="ark:copy-feats scp:$dir/train.MPI_RANK.scp ark:- |"

  if [[ `hostname` =~ stampede ]]; then 
    rbm_train_tool="ibrun rbm-train-cd1-frmshuff-mpi"
  else
    rbm_train_tool="mpirun -n $mpi_jobs rbm-train-cd1-frmshuff-mpi"
  fi
fi


#create a 10k utt subset for global cmvn estimates
head -n 10000 $dir/train.scp > $dir/train.scp.10k

# print the list size
wc -l $dir/train.scp

#get feature dim
echo -n "Getting feature dim : "
feat_dim=$(feat-to-dim "$feats" -)
echo $feat_dim


# Now we will start building feature_transform which will 
# be applied in CUDA to gain more speed.
#
# We will use 1GPU for both feature_transform and MLP training in one binary tool. 
# This is against the kaldi spirit, but it is necessary, because on some sites a GPU 
# cannot be shared accross by two or more processes (compute exclusive mode),
# and we would like to use single GPU per training instance,
# so that the grid resources can be used efficiently...


if [ ! -z "$feature_transform" ]; then
  echo Using already prepared feature_transform: $feature_transform
  cp $feature_transform $dir/final.feature_transform
else
  if [ ! -z "$feature_transform_proto" ]; then
    feature_transform=$dir/tr_$(basename $feature_transform_proto)
    log=$dir/log/feature-transform-initialize.log
    nnet-initialize --binary=false $feature_transform_proto $feature_transform 2>$log || { cat $log; exit 1; }
  else
    # Generate the splice transform
    echo "Using splice +/- $splice , step $splice_step"
    feature_transform=$dir/tr_splice$splice-$splice_step.nnet
    utils/nnet/gen_splice.py --fea-dim=$feat_dim --splice=$splice --splice-step=$splice_step > $feature_transform
    if [ $feat_type == traps ]; then
      #generate hamming+dct transform
      feature_transform_old=$feature_transform
      feature_transform=$dir/hamm_dct${traps_dct_basis}.nnet
      echo "Preparing Hamming DCT transform into : $feature_transform"
      #prepare matrices with time-transposed hamming and dct
      utils/nnet/gen_hamm_mat.py --fea-dim=$feat_dim --splice=$splice > $dir/hamm.mat
      utils/nnet/gen_dct_mat.py --fea-dim=$feat_dim --splice=$splice --dct-basis=$traps_dct_basis > $dir/dct.mat
      #put everything together
      compose-transforms --binary=false $dir/dct.mat $dir/hamm.mat - | \
        transf-to-nnet - - | \
        nnet-concat --binary=false $feature_transform_old - $feature_transform || exit 1;
    fi
  fi

  # Renormalize the MLP input to zero mean and unit variance
  feature_transform_old=$feature_transform
  feature_transform=${feature_transform%.nnet}_cmvn-g.nnet
  echo "Renormalizing MLP input features into $feature_transform"
  nnet-forward --use-gpu=yes \
    $feature_transform_old "$(echo $feats | sed 's|train.scp|train.scp.10k|')" \
    ark:- 2>$dir/log/cmvn_glob_fwd.log |\
  compute-cmvn-stats ark:- - | cmvn-to-nnet - - |\
  nnet-concat --binary=false $feature_transform_old - $feature_transform

  # MAKE LINK TO THE FINAL feature_transform, so the other scripts will find it ######
  [ -f $dir/final.feature_transform ] && unlink $dir/final.feature_transform
  (cd $dir; ln -s $(basename $feature_transform) final.feature_transform )
fi



###### GET THE DIMENSIONS ######
num_fea=$(feat-to-dim --print-args=false "$feats nnet-forward --use-gpu=no $feature_transform ark:- ark:- |" - 2>/dev/null)
if [ ! -z $uttspk ] && [ ! -z $ivector_scp ]; then
  num_fea_ivec=$(copy-vector "scp:head -1 $ivector_scp|" ark,t:- | awk '{print NF-3}')
  num_fea=$(($num_fea + $num_fea_ivec))
fi
num_hid=$hid_dim


###### PERFORM THE PRE-TRAINING ######
for depth in $(seq 1 $nn_depth); do
  echo
  echo "# PRE-TRAINING RBM LAYER $depth"
  RBM=$dir/$depth.rbm
  [ -f $RBM ] && echo "RBM '$RBM' already trained, skipping." && continue

  # The first RBM needs special treatment, because of Gussian input nodes
  if [ "$depth" == "1" ]; then
    # This is usually Gaussian-Bernoulli RBM (not if CNN layers are part of input transform)
    # initialize
    [ ! -z $cnn ] && vis_type=bern || vis_type=gauss
    echo "Initializing '$RBM.init'"
    echo "<NnetProto>
    <Rbm> <InputDim> $num_fea <OutputDim> $num_hid <VisibleType> $input_vis_type <HiddenType> bern <ParamStddev> $param_stddev_first
    </NnetProto>
    " > $RBM.proto
    nnet-initialize $RBM.proto $RBM.init 2>$dir/log/nnet-initialize.$depth.log || exit 1
    # pre-train
    num_iter=$rbm_iter; [ $input_vis_type == "gauss" ] && num_iter=$((2*rbm_iter)) #2x more epochs for Gaussian input
    [ $input_vis_type == "bern" ] && rbm_lrate_low=$rbm_lrate # original lrate for Bernoulli input
    echo "Pretraining '$RBM' (input $input_vis_type, lrate $rbm_lrate_low, iters $num_iter)"
    $rbm_train_tool --learn-rate=$rbm_lrate_low --l2-penalty=$rbm_l2penalty \
      --num-iters=$num_iter --verbose=$verbose \
      --feature-transform=$feature_transform \
      --max-frames=10000 \
      ${utt2spk:+ --utt2spk-rspecifier=ark:$utt2spk} \
      ${ivector_scp:+ --ivector-rspecifier=scp:$ivector_scp} \
      ${reduce_per_iter_tr:+ --max-reduce-count=$reduce_per_iter_tr} \
      ${reduce_type:+ --reduce-type=$reduce_type} \
      ${frames_per_reduce:+ --frames-per-reduce=$frames_per_reduce} \
      $rbm_extra_opts \
      $RBM.init "$feats_tr" $RBM 2>$dir/log/rbm.$depth.log || exit 1
  else
    #This is Bernoulli-Bernoulli RBM
    #cmvn stats for init
    echo "Computing cmvn stats '$dir/$depth.cmvn' for RBM initialization"
    if [ ! -f $dir/$depth.cmvn ]; then 
      nnet-forward --use-gpu=yes \
        ${utt2spk:+ --utt2spk-rspecifier=ark:$utt2spk} \
        ${ivector_scp:+ --ivector-rspecifier=scp:$ivector_scp} \
        --feature-transform=$feature_transform $dir/$((depth-1)).dbn \
        "$(echo $feats | sed 's|train.scp|train.scp.10k|')" \
        ark:- 2>$dir/log/cmvn_fwd.$depth.log | \
      compute-cmvn-stats ark:- - 2>$dir/log/cmvn.$depth.log | \
      cmvn-to-nnet - $dir/$depth.cmvn
    else
      echo compute-cmvn-stats already done, skipping.
    fi
    #initialize
    echo "Initializing '$RBM.init'"
    echo "<NnetProto>
    <Rbm> <InputDim> $num_hid <OutputDim> $num_hid <VisibleType> bern <HiddenType> bern <ParamStddev> $param_stddev <VisibleBiasCmvnFilename> $dir/$depth.cmvn
    </NnetProto>
    " > $RBM.proto
    nnet-initialize $RBM.proto $RBM.init 2>$dir/log/nnet-initialize.$depth.log || exit 1
    #pre-train
    echo "Pretraining '$RBM' (lrate $rbm_lrate, iters $rbm_iter)"
    $rbm_train_tool --learn-rate=$rbm_lrate --l2-penalty=$rbm_l2penalty \
      --num-iters=$rbm_iter --verbose=$verbose \
      --feature-transform=$feature_transform \
      --max-frames=10000 \
      ${utt2spk:+ --utt2spk-rspecifier=ark:$utt2spk} \
      ${ivector_scp:+ --ivector-rspecifier=scp:$ivector_scp} \
      ${reduce_per_iter_tr:+ --max-reduce-count=$reduce_per_iter_tr} \
      ${reduce_type:+ --reduce-type=$reduce_type} \
      ${frames_per_reduce:+ --frames-per-reduce=$frames_per_reduce} \
      $rbm_extra_opts \
      "nnet-concat $dir/$((depth-1)).dbn $RBM.init - |" "$feats_tr" $RBM 2>$dir/log/rbm.$depth.log || exit 1
  fi

  #Create DBN stack
  if [ "$depth" == "1" ]; then
    rbm-convert-to-nnet --binary=true $RBM $dir/$depth.dbn
  else 
    rbm-convert-to-nnet --binary=true $RBM - | \
    nnet-concat $dir/$((depth-1)).dbn - $dir/$depth.dbn
  fi

done

echo
echo "# REPORT"
echo "# RBM pre-training progress (line per-layer)"
grep progress $dir/log/rbm.*.log
echo 

echo "Pre-training finished."

sleep 3
exit 0
}
