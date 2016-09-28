#!/bin/bash
{
set -e
set -o pipefail

cmd=cmd.sh

. parse_options.sh

#./run-prep-data.sh --type evalp1 2>&1 | tee log/run-prep-data.sh_evalp1.log
#./run-prep-feat.sh --cmd $cmd --type evalp1 --segmode unseg 2>&1 | tee log/run-prep-feat.sh_evalp1_unseg.log
#./run-3-segment.sh --cmd $cmd --type evalp1 2>&1 | tee log/run-3-segment_evalp1.sh.log
#./run-prep-feat.sh --cmd $cmd --type evalp1 --segmode pem --segfile exp/trainall_plp_pitch_tri4/decode_evalp1_unseg_plp_pitch/segments 2>&1 | tee log/run-prep-feat.sh_evalp1_pem.log
#./run-prep-feat.sh --cmd $cmd --type evalp1 --segmode pem --segfile exp/trainall_plp_pitch_tri4/decode_evalp1_unseg_plp_pitch/segments --feattype bnplp --bnnet train_plp_pitch_tri7_bn2 --srctype plp 2>&1 | tee log/run-prep-feat.sh_evalp1_bnplp.log


./run-decode.sh --cmd $cmd --type evalp1 --segmode pem 2>&1 > log/run-decode.sh_evalp1_pem.log
#./run-decode.sh --cmd $cmd --type evalp1 --segmode pem --feattype bnplp --nnetlatbeam 10 2>&1 | tee log/run-decode.sh_evalp1_bnplp_beam10.log
#./run-decode.sh --cmd $cmd --langext _nop 2>&1 | tee log/run-decode.sh_nop_re.log
#./run-transduce.sh --cmd $cmd --langext _nop 2>&1 | tee log/run-transduce.sh_nop_re.log
#./run-transduce.sh --cmd $cmd --langext _nop --LGmiddle .boost --nnetlatbeam 10 2>&1 | tee log/run-tranduce.sh_nop_sylG_beam10.log
#./run-transduce.sh --cmd $cmd --type evalp1 --segmode pem --langext _nop --LGmiddle .boost --nnetlatbeam 10 2>&1 | tee log/run-tranduce.sh_evalp1_pem_nop_sylG_beam10.log
}
