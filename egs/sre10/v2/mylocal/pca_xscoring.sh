#!/bin/bash
{
set -e
set -o pipefail

# Copyright 2015   David Snyder
# Apache 2.0.
#
# This script trains an LDA transform, applies it to the enroll and
# test i-vectors and does cosine scoring.
. ./path.sh

use_existing_models=false
pca_dim=150
norm_mean=true

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 8 ]; then
  echo "Usage: $0 <pca-data-dir> <enroll-data-dir> <test-data-dir> <pca-ivec-dir> <enroll-ivec-dir> <test-ivec-dir> <trials-file> <scores-dir>"
fi

pca_data_dir=$1
enroll_data_dir=$2
test_data_dir=$3
pca_ivec_dir=$4
enroll_ivec_dir=$5
test_ivec_dir=$6
trials=$7
scores_dir=$8

[ -d $scores_dir ] || mkdir -p $scores_dir

if [ "$use_existing_models" == "true" ]; then
  for f in ${pca_ivec_dir}/mean.vec ${pca_ivec_dir}/pca.mat ; do
    [ ! -f $f ] && echo "No such file $f" && exit 1;
  done
else

  if $norm_mean; then
    ivector-mean scp:${pca_ivec_dir}/xvector.scp ${pca_ivec_dir}/mean.vec
    pca_scp="ark:ivector-subtract-global-mean ${pca_ivec_dir}/mean.vec scp:${pca_ivec_dir}/xvector.scp ark:- |"
  else
    pca_scp="scp:${pca_ivec_dir}/xvector.scp"
  fi

  est-pca --dim=$pca_dim --read-vectors=true \
    --normalize-variance=true --normalize-mean=true \
    "$pca_scp" ${pca_ivec_dir}/pca.mat
fi

if $norm_mean; then
  enroll_scp="ark:ivector-subtract-global-mean ${pca_ivec_dir}/mean.vec scp:${enroll_ivec_dir}/spk_xvector.scp ark:- | ivector-transform ${pca_ivec_dir}/pca.mat ark:- ark:- |"
  test_scp="ark:ivector-subtract-global-mean ${pca_ivec_dir}/mean.vec scp:${test_ivec_dir}/xvector.scp ark:- | ivector-transform ${pca_ivec_dir}/pca.mat ark:- ark:- |"
else
  enroll_scp="ark:ivector-transform ${pca_ivec_dir}/pca.mat scp:${enroll_ivec_dir}/spk_xvector.scp ark:- |"
  test_scp="ark:ivector-transform ${pca_ivec_dir}/pca.mat scp:${test_ivec_dir}/xvector.scp ark:- |"
fi

ivector-compute-dot-products "cat '$trials' | cut -d\  --fields=1,2 |"  \
  "$enroll_scp" "$test_scp" $scores_dir/pca_scores
}
