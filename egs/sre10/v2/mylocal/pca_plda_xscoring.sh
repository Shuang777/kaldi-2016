#!/bin/bash
# Copyright 2015   David Snyder
# Apache 2.0.
#
# This script trains PLDA models and does scoring.

stage=0
pca_dim=128
use_existing_models=false
norm_vec=true

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
  est-pca --dim=$pca_dim --read-vectors=true \
    --normalize-variance=true --normalize-mean=true \
    scp:$plda_ivec_dir/xvector.scp ${plda_ivec_dir}/pca_trans.mat
fi

if [ $stage -le 1 ]; then
  if $norm_vec; then
    scp="ark:transform-vec $plda_ivec_dir/pca_trans.mat scp:$plda_ivec_dir/xvector.scp ark:- | ivector-normalize-length ark:- ark:- |"
  else
    scp="ark:transform-vec $plda_ivec_dir/pca_trans.mat scp:$plda_ivec_dir/xvector.scp ark:- |"
  fi
  ivector-compute-plda ark:$plda_data_dir/spk2utt \
    "$scp" $plda_ivec_dir/plda
fi

if [ $stage -le 2 ]; then
  if $norm_vec; then
    enroll_scp="ark:transform-vec $plda_ivec_dir/pca_trans.mat scp:$enroll_ivec_dir/spk_xvector.scp ark:- | ivector-normalize-length ark:- ark:- |"
    test_scp="ark:transform-vec $plda_ivec_dir/pca_trans.mat scp:$test_ivec_dir/xvector.scp ark:- | ivector-normalize-length ark:- ark:- |"
  else
    enroll_scp="ark:transform-vec $plda_ivec_dir/pca_trans.mat scp:$enroll_ivec_dir/spk_xvector.scp ark:- |"
    test_scp="ark:transform-vec $plda_ivec_dir/pca_trans.mat scp:$test_ivec_dir/xvector.scp ark:- |"
  fi

  ivector-plda-scoring --normalize-length=true \
    --num-utts=ark:$enroll_ivec_dir/num_utts.ark \
    "ivector-copy-plda --smoothing=0.0 $plda_ivec_dir/plda - |" \
    "$enroll_scp" "$test_scp" \
    "cat $trials | cut -d\  --fields=1,2 |" $scores_dir/pca_plda_scores
fi

