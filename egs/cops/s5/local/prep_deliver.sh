#!/bin/bash

system=tri4
#system=nnet2_pnorm    # tri4, ..
data=data_usabledev
dir=exp/${data}_$system
decode=decode_dev_t1
graph_dir=exp/${data}_tri4/graph_t1

local/score_basic.sh --cmd myutils/slurm.pl $data/dev $graph_dir $dir/$decode
local/text2json.py $data/dev/segments $dir/$decode/scoring/13.0.5.txt sample_asr.json
local/text2json.py $data/dev/segments $data/dev/text sample_trans.json

