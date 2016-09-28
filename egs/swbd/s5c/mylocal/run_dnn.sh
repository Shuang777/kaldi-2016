#!/bin/bash
{

set -e
set -o pipefail

# Copyright 2012-2014  Brno University of Technology (Author: Karel Vesely)
# Apache 2.0

# This example script trains a DNN on top of fMLLR features. 
# The training is done in 3 stages,
#
# 1) RBM pre-training:
#    in this unsupervised stage we train stack of RBMs, 
#    a good starting point for frame cross-entropy trainig.
# 2) frame cross-entropy training:
#    the objective is to classify frames to correct pdfs.
# 3) sequence-training optimizing sMBR: 
#    the objective is to emphasize state-sequences with better 
#    frame accuracy w.r.t. reference alignment.

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.

. ./path.sh ## Source the tools/utils (import the queue.pl)

# Config:
lm=fsh_tgpr
traindata=data/train_10ks
decodename=eval2000
stage=1 # resume training with --stage=N
feat_type=fmllr
nj=30
trainfext=train10k_
# End of config.
. parse_options.sh
#
#if [ $stage -le 0 ]; then
#  utils/subset_data_dir_tr_cv.sh ${traindata}_nodup ${traindata}_nodup_tr90 ${traindata}_nodup_cv10
#fi

gmmdir=exp/tri4b
ali=exp/${trainfext}tri4b_ali_nodup

dir=exp/${trainfext}dnn5b_${feat_type}_dbn

if [ $stage -le 0 ]; then
  # Pre-train DBN, i.e. a stack of RBMs
  case $feat_type in
    fmllr|lda) $cuda_cmd $dir/log/pretrain_dbn.log \
        mysteps/pretrain_dbn.sh --rbm-iter 1 --feat-type $feat_type --transdir $alidir ${traindata}_nodup $dir
    ;;
    traps|raw|delta) $cuda_cmd $dir/log/pretrain_dbn.log \
        mysteps/pretrain_dbn.sh --rbm-iter 1 --feat-type $feat_type ${traindata}_nodup $dir
    ;;
  *) echo "$0: feat_type $feat_type not supported yet" && exit 1;
  esac
fi

dbndir=$dir
dir=${dbndir}_dnn_end0.001
dbndir=exp/dnn5b_${feat_type}_dbn
feature_transform=$dbndir/final.feature_transform
dbn=$dbndir/6.dbn
if [ $stage -le 1 ]; then
  # Train the DNN optimizing per-frame cross-entropy
  case $feat_type in
    fmllr|lda)
      $cuda_cmd $dir/log/train_nnet.log \
        mysteps/train_nnet.sh --feature-transform $feature_transform --dbn $dbn --hid-layers 0 --learn-rate 0.008 \
        --resume-anneal false --feat-type $feat_type \
        ${traindata}_nodup $ali $dir
    ;;
    traps|raw|delta)
      $cuda_cmd $dir/log/train_nnet.log \
        mysteps/train_nnet.sh --feature-transform $feature_transform --dbn $dbn --hid-layers 0 --learn-rate 0.008 \
        --resume-anneal false --feat-type $feat_type \
        ${traindata}_nodup $ali $dir
    ;;
  esac
fi

if [ $stage -le 2 ]; then
  case $feat_type in
    fmllr|lda)
      mysteps/decode_nnet.sh --nj $nj --cmd "$decode_cmd" --config conf/decode_dnn.config --acwt 0.08333 \
        --transform-dir ${gmmdir}/decode_${decodename}_sw1_${lm} --feat-type $feat_type \
        $gmmdir/graph_sw1_${lm} data/${decodename} $dir/decode_${decodename}_sw1_${lm}
    # Rescore using unpruned trigram sw1_fsh
    #  steps/lmrescore.sh --mode 3 --cmd "$mkgraph_cmd" data/lang_sw1_fsh_tg data/lang_sw1_fsh_tg data/eval2000 \
    #    $dir/decode_eval2000_sw1_fsh_tg $dir/decode_eval2000_sw1_fsh_tg.3 || exit 1 
    ;;
  traps|raw|delta)
      # Decode (reuse HCLG graph)
      mysteps/decode_nnet.sh --nj $nj --cmd "$decode_cmd" --config conf/decode_dnn.config --feat-type $feat_type \
        --acwt 0.08333 $gmmdir/graph_sw1_${lm} data/${decodename} $dir/decode_${decodename}_sw1_${lm}
    ;;
  esac
fi

exit

## bottleneck approach
if [ $stage -le 3 ]; then
  # 1st network, overall context +/-5 frames
  # - the topology is 90_1500_1500_80_1500_NSTATES, linear bottleneck
  dir=exp/nnet5b_uc-part1
  ali=${gmmdir}_ali_nodup
  $cuda_cmd $dir/log/train_nnet.log \
    mysteps/train_nnet.sh --hid-layers 2 --hid-dim 1500 --bn-dim 80 \
      --feat-type traps --splice 5 --traps-dct-basis 6 --learn-rate 0.008 \
    ${traindata}_nodup $ali $dir
fi

if [ $stage -le 4 ]; then
  # Compose feature_transform for the next stage, 
  # - remaining part of the first network is fixed
  dir=exp/nnet5b_uc-part1
  feature_transform=$dir/final.feature_transform.part1
  nnet-concat $dir/final.feature_transform \
    "nnet-copy --remove-last-layers=4 --binary=false $dir/final.nnet - |" \
    "utils/nnet/gen_splice.py --fea-dim=80 --splice=2 --splice-step=5 |" \
    $feature_transform 
  
  # 2nd network, overall context +/-15 frames
  # - the topology will be 400_1500_1500_30_1500_NSTATES, again, the bottleneck is linear
  dir=exp/nnet5b_uc-part2
  ali=${gmmdir}_ali_nodup
  $cuda_cmd $dir/log/train_nnet.log \
    mysteps/train_nnet.sh --hid-layers 2 --hid-dim 1500 --bn-dim 30 \
      --feat-type traps --feature-transform $feature_transform --learn-rate 0.008 \
      ${traindata}_nodup $ali $dir
fi


# Sequence training using sMBR criterion, we do Stochastic-GD 
# with per-utterance updates. We use usually good acwt 0.1
# Lattices are re-generated after 1st epoch, to get faster convergence.
srcdir=$dir
dir=${srcdir}_smbr
acwt=0.0909

if [ $stage -le 5 ]; then
  # First we generate lattices and alignments:
  mysteps/align_nnet.sh --nj 100 --cmd "$train_cmd -tc 50" \
    --transform-dir ${gmmdir}_ali_nodup \
    --feat-type $feat_type \
    ${traindata}_nodup data/lang $srcdir ${srcdir}_ali || exit 1;
  mysteps/make_denlats_nnet.sh --nj 100 --cmd "$decode_cmd -tc 50" \
    --transform-dir ${gmmdir}_ali_nodup \
    --feat-type $feat_type \
    --config conf/decode_dnn.config \
    --acwt $acwt ${traindata}_nodup data/lang $srcdir ${srcdir}_denlats
fi

if [ $stage -le 6 ]; then
  # Re-train the DNN by 1 iteration of sMBR 
#  mysteps/train_nnet_mpe.sh --cmd "$cuda_cmd" --num-iters 1 --acwt $acwt --do-smbr true \
#    --transdir ${gmmdir}_ali_nodup  --feat-type $feat_type \
#    ${traindata}_nodup data/lang $srcdir ${srcdir}_ali ${srcdir}_denlats $dir || exit 1
  # Decode (reuse HCLG graph)
  for ITER in 1; do
    mysteps/decode_nnet.sh --nj $nj --cmd "$decode_cmd" --config conf/decode_dnn.config \
      --nnet $dir/${ITER}.nnet --acwt $acwt \
      --transform-dir ${gmmdir}/decode_${decodename}_sw1_${lm} --feat-type $feat_type \
      $gmmdir/graph_sw1_${lm} data/${decodename} $dir/decode_${decodename}_sw1_${lm}
    # Rescore using unpruned trigram sw1_fsh
#    steps/lmrescore.sh --mode 3 --cmd "$mkgraph_cmd" data/lang_sw1_${lm} data/lang_sw1_fsh_tg data/eval2000 \
#      $dir/decode_eval2000_sw1_${lm} $dir/decode_eval2000_sw1_fsh_tg.3 || exit 1 
  done 
fi

# Re-generate lattices, run 4 more sMBR iterations
srcdir=$dir
dir=${srcdir}_i1lats
acwt=0.0909

<<align
if [ $stage -le 7 ]; then
  # First we generate lattices and alignments:
  mysteps/align_nnet.sh --nj 100 --cmd "$train_cmd -tc 50" \
    --transform-dir ${gmmdir}_ali_nodup \
    --feat-type $feat_type \
    ${traindata}_nodup data/lang $srcdir ${srcdir}_ali || exit 1;
  mysteps/make_denlats_nnet.sh --nj 100 --cmd "$decode_cmd -tc 50" \
    --transform-dir ${gmmdir}_ali_nodup \
    --feat-type $feat_type \
    --config conf/decode_dnn.config \
    --acwt $acwt ${traindata}_nodup data/lang $srcdir ${srcdir}_denlats
fi
align

if [ $stage -le 8 ]; then
  # Re-train the DNN by 1 iteration of sMBR 
#  mysteps/train_nnet_mpe.sh --cmd "$cuda_cmd" --num-iters 2 --acwt $acwt --do-smbr true \
#    --transdir ${gmmdir}_ali_nodup  --feat-type $feat_type \
#    ${traindata}_nodup data/lang $srcdir ${srcdir}_ali ${srcdir}_denlats $dir || exit 1
  # Decode (reuse HCLG graph)
  for ITER in 1 2; do
    mysteps/decode_nnet.sh --nj $nj --cmd "$decode_cmd" --config conf/decode_dnn.config \
      --nnet $dir/${ITER}.nnet --acwt $acwt \
      --transform-dir ${gmmdir}/decode_${decodename}_sw1_${lm} --feat-type $feat_type \
      $gmmdir/graph_sw1_${lm} data/${decodename} $dir/decode_${decodename}_sw1_${lm}
    # Rescore using unpruned trigram sw1_fsh
#    steps/lmrescore.sh --mode 3 --cmd "$mkgraph_cmd" data/lang_sw1_${lm} data/lang_sw1_fsh_tg data/eval2000 \
#      $dir/decode_eval2000_sw1_${lm} $dir/decode_eval2000_sw1_fsh_tg.3 || exit 1 
  done 
fi

# Getting results [see RESULTS file]
# for x in exp/*/decode*; do [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh; done

}
