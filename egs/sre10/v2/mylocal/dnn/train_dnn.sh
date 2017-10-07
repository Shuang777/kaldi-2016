#!/bin/bash
{
set -e 
set -o pipefail

stage=0
single=true
# This script is based on egs/fisher_english/s5/run.sh. It trains a
# multisplice time-delay neural network used in the DNN-based speaker
# recognition recipes.

# It's best to run the commands in this one by one.

. utils/parse_options.sh
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

if [ $stage -le 0 ]; then
  mylocal/dnn/fisher_data_prep.sh /u/drspeech/data/swordfish/users/suhang/data/LDC2004T19 \
    /u/drspeech/data/swordfish/users/suhang/data/LDC2005T19 \
    /u/drspeech/data/swordfish/users/suhang/data/LDC2004S13 

  local/dnn/fisher_prepare_dict.sh

  utils/prepare_lang.sh data/local/dict "<unk>" data/local/lang data/lang

  mylocal/dnn/fisher_train_lms.sh

  local/dnn/fisher_create_test_lang.sh
  $single && exit
fi

if [ $stage -le 1 ]; then
#utils/fix_data_dir.sh data/train_all_asr

steps/make_mfcc.sh --nj 40 --cmd "$train_cmd" --mfcc-config conf/mfcc_asr.conf \
   data/train_all_asr exp/make_mfcc/train_all_asr $mfccdir || exit 1;

utils/fix_data_dir.sh data/train_all_asr
utils/validate_data_dir.sh data/train_all_asr


# The dev and test sets are each about 3.3 hours long.  These are not carefully
# done; there may be some speaker overlap with each other and with the training
# set.  Note: in our LM-training setup we excluded the first 10k utterances (they
# were used for tuning but not for training), so the LM was not (directly) trained
# on either the dev or test sets.
utils/subset_data_dir.sh --first data/train_all_asr 10000 data/dev_and_test_asr
utils/subset_data_dir.sh --first data/dev_and_test_asr 5000 data/dev_asr
utils/subset_data_dir.sh --last data/dev_and_test_asr 5000 data/test_asr
rm -r data/dev_and_test_asr

steps/compute_cmvn_stats.sh data/dev_asr exp/make_mfcc/dev_asr $mfccdir
steps/compute_cmvn_stats.sh data/test_asr exp/make_mfcc/test_asr $mfccdir

n=$[`cat data/train_all_asr/segments | wc -l` - 10000]
utils/subset_data_dir.sh --last data/train_all_asr $n data/train_fisher_asr
steps/compute_cmvn_stats.sh data/train_fisher_asr exp/make_mfcc/train_fisher_asr $mfccdir

utils/subset_data_dir.sh --shortest data/train_fisher_asr 100000 data/train_fisher_asr_100kshort
utils/subset_data_dir.sh  data/train_fisher_asr_100kshort 10000 data/train_fisher_asr_10k
local/dnn/remove_dup_utts.sh 100 data/train_fisher_asr_10k data/train_fisher_asr_10k_nodup
utils/subset_data_dir.sh --speakers data/train_fisher_asr 30000 data/train_fisher_asr_30k
utils/subset_data_dir.sh --speakers data/train_fisher_asr 100000 data/train_fisher_asr_100k
$single && exit

fi


if [ $stage -le 2 ]; then
steps/train_mono.sh --nj 10 --cmd "$train_cmd" \
  data/train_fisher_asr_10k_nodup data/lang exp/mono0a

steps/align_si.sh --nj 30 --cmd "$train_cmd" \
   data/train_fisher_asr_30k data/lang exp/mono0a exp/mono0a_ali

steps/train_deltas.sh --cmd "$train_cmd" \
    2500 20000 data/train_fisher_asr_30k data/lang exp/mono0a_ali exp/tri1

steps/align_si.sh --nj 30 --cmd "$train_cmd" \
   data/train_fisher_asr_30k data/lang exp/tri1 exp/tri1_ali

steps/train_deltas.sh --cmd "$train_cmd" \
    2500 20000 data/train_fisher_asr_30k data/lang exp/tri1_ali exp/tri2

steps/align_si.sh --nj 30 --cmd "$train_cmd" \
  data/train_fisher_asr_100k data/lang exp/tri2 exp/tri2_ali

# Train tri3a, which is LDA+MLLT, on 100k data.
steps/train_lda_mllt.sh --cmd "$train_cmd" \
   --splice-opts "--left-context=3 --right-context=3" \
   5000 40000 data/train_fisher_asr_100k data/lang exp/tri2_ali exp/tri3a

$single && exit

fi

if [ $stage -le 3 ]; then
# Next we'll use fMLLR and train with SAT (i.e. on
# fMLLR features)

#steps/align_fmllr.sh --nj 30 --cmd "$train_cmd" \
#  data/train_fisher_asr_100k data/lang exp/tri3a exp/tri3a_ali

#steps/train_sat.sh  --cmd "$train_cmd" \
#  5000 100000 data/train_fisher_asr_100k data/lang exp/tri3a_ali  exp/tri4a

steps/align_fmllr.sh --nj 30 --cmd "$train_cmd" \
  data/train_fisher_asr data/lang exp/tri4a exp/tri4a_ali

steps/train_sat.sh  --cmd "$train_cmd" \
  7000 300000 data/train_fisher_asr data/lang exp/tri4a_ali  exp/tri5a


utils/mkgraph.sh data/lang_test exp/tri5a exp/tri5a/graph
steps/decode_fmllr.sh --nj 25 --cmd "$decode_cmd" --config conf/decode.config \
  exp/tri5a/graph data/dev_asr exp/tri5a/decode_dev

$single && exit

fi

if [ $stage -le 4 ]; then
## The following is based on the best current neural net recipe.
mylocal/dnn/run_nnet2_multisplice.sh

$single && exit
fi
}
