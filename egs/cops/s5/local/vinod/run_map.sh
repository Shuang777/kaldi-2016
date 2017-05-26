#!/bin/bash
{
set -e

#begin configuration
nbest=1
#end configuration

. parse_options.sh

if [ $0 == "./run_map.sh" ]; then
  echo "Please call from folder above this level"
  exit 1
fi

expext=_middle   # _middle, _big
perturb=_full_perturbed      # empty, full_perturbed

gmmdir=exp/data_usabledev5_tri4${perturb}$expext
dnndir=exp/data_usabledev5_dnn5b_fmllr_dbn_dnn${perturb}$expext

dir=deliver_vinod/usabledev5_fix_re

langext=_fix
langext=_fix_swb_fsh

[ -d $dir ] || mkdir -p $dir

local/get_trans.sh --nbest $nbest --lm-score 16 \
  $gmmdir/decode_vinod$langext $gmmdir/graph$langext $dir/gmm${perturb}${expext}${langext}_${nbest}best.tra

python deliver_vinod/map2tsv.py --nbest $nbest --llk \
  local/utt2id.vinod $dir/gmm${perturb}${expext}${langext}_${nbest}best.tra \
  $dir/gmm${perturb}${expext}${langext}_${nbest}best.tsv

local/get_trans.sh --nbest $nbest --lm-score 16 \
  $dnndir/decode_vinod$langext $gmmdir/graph$langext $dir/dnn${perturb}${expext}${langext}_${nbest}best.tra

python deliver_vinod/map2tsv.py --nbest $nbest --llk \
  local/utt2id.vinod $dir/dnn${perturb}${expext}${langext}_${nbest}best.tra \
  $dir/dnn${perturb}${expext}${langext}_${nbest}best.tsv
}
