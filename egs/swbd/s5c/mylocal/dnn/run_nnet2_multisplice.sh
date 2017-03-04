#!/bin/bash

# This script is based on run_nnet2_multisplice.sh in
# egs/fisher_english/s5/local/online. It has been modified
# for speaker recognition.

. cmd.sh


stage=0
train_stage=-10
use_gpu=true
set -e
. cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if [ $# -ne 0 ]; then
  echo "Usage: $0"
  echo " e,g,: $0"
  exit 1
fi


dir=exp/nnet2_online/nnet_ms_a_cpu_4a

# assume use_gpu=true since it would be way too slow otherwise.

if $use_gpu; then
  parallel_opts="-l gpu=1" 
  num_threads=1
  minibatch_size=512
else
  num_threads=16
  minibatch_size=128
  parallel_opts="-pe smp $num_threads" 
fi

[ -d $dir ] || mkdir -p $dir

# Stages 1 through 5 are done in run_nnet2_common.sh,
# so it can be shared with other similar scripts.
mylocal/dnn/run_nnet2_common.sh --stage $stage

if [ $stage -le 6 ]; then
  
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
    data/train_hires_asr data/lang exp/tri4a $dir 

fi

if [ $stage -le 7 ]; then
mfccdir=mfcc
utils/copy_data_dir.sh data/eval2000 data/eval2000_hires_asr
steps/make_mfcc.sh --nj 30 --mfcc-config conf/mfcc_hires.conf \
  --cmd "$train_cmd" data/eval2000_hires_asr exp/make_hires/eval2000 $mfccdir
fi

if [ $stage -le 8 ]; then
for lm in tg fsh_tgpr; do
graph_dir=exp/tri4b/graph_sw1_$lm
mylocal/dnn/decode.sh --nj 30 --cmd "$decode_cmd" \
  --config conf/decode.config --feat-type raw \
  $graph_dir data/eval2000_hires_asr $dir/decode_eval2000_sw1_$lm
done
fi

exit 0;

