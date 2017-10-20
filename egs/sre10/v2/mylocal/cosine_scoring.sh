#!/bin/bash
# Copyright 2015   David Snyder
# Apache 2.0.
#
# This script trains an LDA transform and does cosine scoring.

normalize=true

. utils/parse_options.sh

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 6 ]; then
  echo "Usage: $0 <enroll-data> <test-data> <enroll-ivec-dir> <test-ivec-dir> <trials-file> <scores-dir>"
  exit 1
fi

enroll_data=$1
test_data=$2
enroll_ivec_dir=$3
test_ivec_dir=$4
trials=$5
scores_dir=$6

[ -d $scores_dir ] || mkdir -p $scores_dir

if $normalize; then
cat $trials | awk '{print $1, $2}' | \
 ivector-compute-dot-products - \
  scp:${enroll_ivec_dir}/spk_ivector.scp \
  "ark:ivector-normalize-length scp:${test_ivec_dir}/ivector.scp ark:- |" \
   $scores_dir/cosine_scores
else
cat $trials | awk '{print $1, $2}' | \
 ivector-compute-dot-products - \
  "ark:ivector-mean ark:$enroll_data/spk2utt scp:${enroll_ivec_dir}/ivector.scp ark:- |" \
  "ark:ivector-normalize-length scp:${test_ivec_dir}/ivector.scp ark:- |" \
   $scores_dir/cosine_scores
fi
