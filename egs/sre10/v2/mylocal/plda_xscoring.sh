#!/bin/bash
# Copyright 2015   David Snyder
# Apache 2.0.
#
# This script trains PLDA models and does scoring.

norm_mean=true
norm_var=true
use_existing_models=false

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 8 ]; then
  echo "Usage: $0 <plda-data-dir> <enroll-data-dir> <test-data-dir> <plda-ivec-dir> <enroll-ivec-dir> <test-ivec-dir> <trials-file> <scores-dir>"
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

if [ "$use_existing_models" == "true" ]; then
  for f in ${plda_ivec_dir}/mean.vec ${plda_ivec_dir}/plda ; do
    [ ! -f $f ] && echo "No such file $f" && exit 1;
  done
else

  if $norm_mean; then
    if $norm_var; then
      compute-vec-mvn-stats scp:${plda_ivec_dir}/xvector.scp ${plda_ivec_dir}/mvn.mat
      plda_scp="ark:apply-vec-cmvn --norm-vars=true ${plda_ivec_dir}/mvn.mat scp:${plda_ivec_dir}/xvector.scp ark:- |"
    else
      ivector-mean scp:${plda_ivec_dir}/xvector.scp ${plda_ivec_dir}/mean.vec
      plda_scp="ark:ivector-subtract-global-mean ${plda_ivec_dir}/mean.vec scp:${plda_ivec_dir}/xvector.scp ark:- |"
    fi
  else
    plda_scp="scp:${plda_ivec_dir}/xvector.scp"
  fi

  [ -d $plda_ivec_dir/log ] || mkdir -p $plda_ivec_dir/log

  ivector-compute-plda ark:$plda_data_dir/spk2utt \
    "$plda_scp" $plda_ivec_dir/plda | tee $plda_ivec_dir/log/plda.log
fi

[ -d $scores_dir ] || mkdir -p $scores_dir

if $norm_mean; then
  if $norm_var; then
    enroll_scp="ark:apply-vec-cmvn --norm-vars=true ${plda_ivec_dir}/mvn.mat scp:${enroll_ivec_dir}/spk_xvector.scp ark:- |"
    test_scp="ark:apply-vec-cmvn --norm-vars=true ${plda_ivec_dir}/mvn.mat scp:${test_ivec_dir}/xvector.scp ark:- |"
  else
    enroll_scp="ark:ivector-subtract-global-mean ${plda_ivec_dir}/mean.vec scp:${enroll_ivec_dir}/spk_xvector.scp ark:- |"
    test_scp="ark:ivector-subtract-global-mean ${plda_ivec_dir}/mean.vec scp:${test_ivec_dir}/xvector.scp ark:- |"
  fi
else
  enroll_scp="scp:${enroll_ivec_dir}/spk_xvector.scp"
  test_scp="scp:${test_ivec_dir}/xvector.scp"
fi

ivector-plda-scoring --num-utts=ark:${enroll_ivec_dir}/num_utts.ark \
   "ivector-copy-plda --smoothing=0.0 ${plda_ivec_dir}/plda - |" \
   "$enroll_scp" "$test_scp" \
   "cat '$trials' | awk '{print \$1, \$2}' |" $scores_dir/plda_scores
