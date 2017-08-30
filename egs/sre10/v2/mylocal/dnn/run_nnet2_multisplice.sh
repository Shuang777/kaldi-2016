#!/bin/bash
{
set -e
set -o pipefail

# This script is based on run_nnet2_multisplice.sh in
# egs/fisher_english/s5/local/online. It has been modified
# for speaker recognition.

. ./cmd.sh
. ./path.sh

nj_tr=10
stage=0
train_stage=-10
use_gpu=true
set -e
. cmd.sh
. ./path.sh
. ./utils/parse_options.sh



# assume use_gpu=true since it would be way too slow otherwise.

parallel_opts="-l gpu=1" 
num_threads=1
minibatch_size=512
dir=exp/nnet2_online/nnet_ms_a
mkdir -p exp/nnet2_online

mfccdir=mfcc

if [ $stage -le 0 ]; then
  utils/copy_data_dir.sh data/trainori_nodup data/trainori_nodup_hires
  steps/make_mfcc.sh --mfcc-config conf/mfcc_hires.conf --compress true --nj 30 \
    --cmd "$train_cmd" data/trainori_nodup_hires exp/make_mfcc/trainori_nodup $mfccdir
  steps/compute_cmvn_stats.sh data/trainori_nodup_hires exp/make_mfcc/trainori_nodup $mfccdir 
  $single && exit
fi

if [ $stage -le 1 ]; then
  # Because we have a lot of data here and we don't want the training to take
  # too long, we reduce the number of epochs from the defaults (15 + 5) to (3 +
  # 1).  The option "--io-opts '-tc 12'" is to have more than the default number
  # (5) of jobs dumping the egs to disk; this is OK since we're splitting our
  # data across four filesystems for speed.

  mylocal/dnn/train_multisplice_accel2.sh --stage $train_stage \
    --feat-type raw \
    --splice-indexes "layer0/-2:-1:0:1:2 layer1/-1:2 layer3/-3:3 layer4/-7:2" \
    --num-epochs 6 \
    --num-hidden-layers 6 \
    --num-jobs-initial 3 --num-jobs-final 18 \
    --num-threads "$num_threads" \
    --minibatch-size "$minibatch_size" \
    --parallel-opts "$parallel_opts" \
    --mix-up 10500 \
    --initial-effective-lrate 0.0015 --final-effective-lrate 0.00015 \
    --cmd "$decode_cmd" \
    --egs-dir "$common_egs_dir" \
    --pnorm-input-dim 3500 \
    --pnorm-output-dim 350 \
    data/trainori_nodup_hires data/lang exp/tri5a $dir  || exit 1;

  $single && exit
fi

if [ $stage -le 3 ]; then
for name in train sre10_train sre10_test; do
  utils/copy_data_dir.sh data/$name data/${name}_hires
  steps/make_mfcc.sh --mfcc-config conf/mfcc_hires.conf --nj $nj_tr --cmd "$train_cmd" \
    data/${name}_hires exp/make_mfcc $mfccdir
  steps/compute_cmvn_stats.sh data/${name}_hires exp/make_mfcc $mfccdir
done
$single && exit
fi

if [ $stage -le 4 ]; then
  utils/copy_data_dir.sh data/train_hires data/train_hires_5752
  utils/filter_scp.pl data/train_5752/feats.scp data/train_hires/feats.scp > data/train_hires_5752/feats.scp
  utils/fix_data_dir.sh data/train_hires_5752
  $single && exit
fi

exit 0;
}
