#!/bin/bash
{
set -e
set -o pipefail

# Copyright 2015   David Snyder
# Apache 2.0.
#
# This script trains an LDA transform and does cosine scoring.

norm_mean=true
. utils/parse_options.sh
echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 8 ]; then
  echo "Usage: $0 <enroll-data> <test-data> <enroll-ivec-dir> <test-ivec-dir> <trials-file> <scores-dir>"
  exit 1
fi

sre_data=$1
enroll_data=$2
test_data=$3
sre_ivec_dir=$4
enroll_ivec_dir=$5
test_ivec_dir=$6
trials=$7
scores_dir=$8

[ -d $scores_dir ] || mkdir -p $scores_dir

ivector-mean scp:${sre_ivec_dir}/xvector.scp ${sre_ivec_dir}/mean.vec

if $norm_mean; then
  enroll_scp="ark:ivector-subtract-global-mean ${sre_ivec_dir}/mean.vec scp:${enroll_ivec_dir}/spk_xvector.scp ark:- |"
  test_scp="ark:ivector-subtract-global-mean ${sre_ivec_dir}/mean.vec scp:${test_ivec_dir}/xvector.scp ark:- |"
else
  enroll_scp="scp:${enroll_ivec_dir}/spk_xvector.scp"
  test_scp="scp:${test_ivec_dir}/xvector.scp"
fi

cat $trials | awk '{print $1, $2}' | \
 ivector-compute-dot-products - \
  "$enroll_scp" "$test_scp" $scores_dir/cosine_scores

}
