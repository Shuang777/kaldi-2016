#!/bin/bash
{
#echo "$0 $@"

prep_DET=true
plot_DET=false

. parse_options.sh

if [ $# -ne 2 ]; then
  echo "$0 <trials> <scores>"
  exit 1
fi

. ./path.sh

trials=$1
scores=$2

compute-eer <(python myutils/prepare_for_eer.py $trials $scores) | tee $scores.eer
echo ""
if [ $prep_DET == true ]; then
  dir=`dirname $scores`
  myutils/prepDET.pl $trials $scores $dir
  if [ $plot_DET == true ]; then
    matlab  -nodesktop -r "plotDET('`pwd`/true.scores', '`pwd`/imposter.scores');exit;"
  fi
fi

}
