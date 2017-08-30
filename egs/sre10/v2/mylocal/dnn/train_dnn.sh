#!/bin/bash
{
set -e 
set -o pipefail

# This script is based on egs/fisher_english/s5/run.sh. It trains a
# multisplice time-delay neural network used in the DNN-based speaker
# recognition recipes.

# It's best to run the commands in this one by one.

. cmd.sh
. path.sh
mfccdir=`pwd`/mfcc

# The dev and test sets are each about 3.3 hours long.  These are not carefully
# done; there may be some speaker overlap with each other and with the training
# set.  Note: in our LM-training setup we excluded the first 10k utterances (they
# were used for tuning but not for training), so the LM was not (directly) trained
# on either the dev or test sets.

# Now-- there are 1.6 million utterances, and we want to start the monophone training
# on relatively short utterances (easier to align), but not only the very shortest
# ones (mostly uh-huh).  So take the 100k shortest ones, and then take 10k random
# utterances from those.

steps/train_mono.sh --nj 10 --cmd "$train_cmd" \
  data/trainori_10k_nodup data/lang exp/mono0a

steps/align_si.sh --nj 30 --cmd "$train_cmd" \
   data/trainori_30k data/lang exp/mono0a exp/mono0a_ali

steps/train_deltas.sh --cmd "$train_cmd" \
    2500 20000 data/trainori_30k data/lang exp/mono0a_ali exp/tri1

steps/align_si.sh --nj 30 --cmd "$train_cmd" \
   data/trainori_30k data/lang exp/tri1 exp/tri1_ali

steps/train_deltas.sh --cmd "$train_cmd" \
    2500 20000 data/trainori_30k data/lang exp/tri1_ali exp/tri2

steps/align_si.sh --nj 30 --cmd "$train_cmd" \
  data/trainori_100k data/lang exp/tri2 exp/tri2_ali

# Train tri3a, which is LDA+MLLT, on 100k data.
steps/train_lda_mllt.sh --cmd "$train_cmd" \
   --splice-opts "--left-context=3 --right-context=3" \
   5000 40000 data/trainori_100k data/lang exp/tri2_ali exp/tri3a

# Next we'll use fMLLR and train with SAT (i.e. on
# fMLLR features)

steps/align_fmllr.sh --nj 30 --cmd "$train_cmd" \
  data/trainori_100k data/lang exp/tri3a exp/tri3a_ali

steps/train_sat.sh  --cmd "$train_cmd" \
  5000 100000 data/trainori_100k data/lang exp/tri3a_ali  exp/tri4a

steps/align_fmllr.sh --nj 30 --cmd "$train_cmd" \
  data/trainori_nodup data/lang exp/tri4a exp/tri4a_ali

steps/train_sat.sh  --cmd "$train_cmd" \
  7000 300000 data/trainori_nodup data/lang exp/tri4a_ali  exp/tri5a

## The following is based on the best current neural net recipe.
mylocal/dnn/run_nnet2_multisplice.sh
}
