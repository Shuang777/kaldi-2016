#!/bin/bash

./run-prep-list.sh

./run-prep-lang.sh

./run-prep-data.sh --type train
./run-prep-data.sh --type dev10h

./run-prep-lm.sh

./run-prep-feat.sh --type train

./run-1-flatstart.sh
./run-2-triphone.sh

./run-prep-feat.sh --type trainall
./run-prep-feat.sh --type dev10h --segmode unseg

./run-3-segment.sh
./run-prep-feat.sh --type dev10h --segmode pem --segfile exp/trainall_plp_pitch_tri4/decode_dev10h_unseg_plp_pitch/segments

./run-3a-nnet-pnorm.sh


