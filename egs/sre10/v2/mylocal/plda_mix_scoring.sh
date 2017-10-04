#!/bin/bash
# Copyright 2015   David Snyder
# Apache 2.0.
#
# This script trains PLDA models and does scoring.

stage=0
lda_dim=128
use_existing_models=false

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 8 ]; then
  echo "Usage: $0 <plda-data-dir> <plda-ivec-dir> <enroll-ivec-dir> <test-ivec-dir> <trials-file> <scores-dir>"
  exit 1
fi

plda_data_dir=$1
enroll_data_dir=$2
test_data_dir=$3
plda_ivec_dir=$4
enroll_ivec_dir=$5
test_ivec_dir=$6
trials=$7
scores_dir=$8

if [ $stage -le 0 ]; then
ivector-compute-lda --total-covariance-factor=0.0 --dim=$lda_dim \
  "ark:ivector-subtract-global-mean scp:$plda_ivec_dir/ivector.scp ark:- |" \
  ark:$plda_data_dir/utt2spk $plda_ivec_dir/lda_trans.mat
fi

if [ $stage -le 1 ]; then
ivector-compute-plda ark:$plda_data_dir/spk2utt \
  "ark:ivector-subtract-global-mean scp:$plda_ivec_dir/ivector.scp ark:- | transform-vec $plda_ivec_dir/lda_trans.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
  $plda_ivec_dir/plda
fi

if [ $stage -le 2 ]; then
ivector-plda-scoring --normalize-length=true \
  --num-utts=ark:$enroll_ivec_dir/num_utts.ark \
  "ivector-copy-plda --smoothing=0.0 $plda_ivec_dir/plda - |" \
  "ark:ivector-mean ark:$enroll_data_dir/spk2utt scp:$enroll_ivec_dir/ivector.scp ark:- | ivector-subtract-global-mean $plda_ivec_dir/mean.vec ark:- ark:- | transform-vec $plda_ivec_dir/lda_trans.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
  "ark:ivector-subtract-global-mean $plda_ivec_dir/mean.vec scp:$test_ivec_dir/ivector.scp ark:- | transform-vec $plda_ivec_dir/lda_trans.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
  "cat $trials | cut -d\  --fields=1,2 |" $scores_dir/lda_plda_scores
fi

