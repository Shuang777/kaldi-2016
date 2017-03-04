#!/bin/bash

# Make the features.

. cmd.sh

stage=1
set -e
. cmd.sh
. ./path.sh
. ./utils/parse_options.sh

mkdir -p exp/nnet2_online

if [ $stage -le 1 ]; then
  # this shows how you can split across multiple file-systems.  we'll split the
  # MFCC dir across multiple locations.  You might want to be careful here, if you
  # have multiple copies of Kaldi checked out and run the same recipe, not to let
  # them overwrite each other.
  mfccdir=mfcc

  utils/copy_data_dir.sh data/train_nodup data/train_hires_asr
  steps/make_mfcc.sh --nj 100 --mfcc-config conf/mfcc_hires.conf \
      --cmd "$train_cmd -tc 100" data/train_hires_asr exp/make_hires/train $mfccdir || exit 1;
fi
