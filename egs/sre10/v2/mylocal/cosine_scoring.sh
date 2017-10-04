#!/bin/bash
# Copyright 2015   David Snyder
# Apache 2.0.
#
# This script trains an LDA transform and does cosine scoring.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 4 ]; then
  echo "Usage: $0 <enroll-ivec-dir> <test-ivec-dir> <trials-file> <scores-dir>"
  exit 1
fi

enroll_ivec_dir=$1
test_ivec_dir=$2
trials=$3
scores_dir=$4

cat $trials | awk '{print $1, $2}' | \
 ivector-compute-dot-products - \
  scp:${enroll_ivec_dir}/spk_ivector.scp \
  'ark:ivector-normalize-length scp:${test_ivec_dir}/ivector.scp ark:- |' \
   $scores_dir/cosine_scores
