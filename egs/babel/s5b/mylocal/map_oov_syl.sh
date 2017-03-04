#!/bin/bash
# Copyright 2014  International Computer Science Institute (Author: Hang Su)
#

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
{
set -e
set -o pipefail

echo "$0 $@"

# Begin configuration
nj=30
cmd=myutils/slurm.pl
# End configuration

. utils/parse_options.sh 

if [ $# -ne 3 ]; then
  echo "Usage: $0 <oov-lexicon> <syl2phn-lexicon> <exp-dir>"
  exit 1
fi

oov_lexicon=$1
syl2phn_lexicon=$2
dir=$3

[ -d $dir ] || mkdir -p $dir

cut -f1 $syl2phn_lexicon | sort -u > $dir/seen.syl
sed -e 's#\t #\t#g' -e 's#\t$##g' -e 's# #=#g' $oov_lexicon | \
  awk 'NR==FNR {a[$i]; next;} 
    {
      for(i=2; i<=NF; i++) {
        if (!($i in a)) {
          print $i;
        }
      }
    }' $dir/seen.syl /dev/stdin | sort -u > $dir/unseen.syl

split_unseens=""
for ((n=1; n<=nj; n++)); do
  split_unseens="$split_unseens $dir/split$nj/unseen.${n}.list"
done

utils/split_scp.pl $dir/unseen.syl $split_unseens

$cmd JOB=1:$nj $dir/log/map_unseen.JOB.log \
  g2p/closesyls.pl $dir/seen.syl $dir/split$nj/unseen.JOB.list \> $dir/split$nj/unseen.JOB.syl.map

for i in `seq $nj`; do
  cat $dir/split$nj/unseen.*.syl.map
done > $dir/unseen2seen.mapped.txt

perl -e '
  $map = $ARGV[0];
  $lex = $ARGV[1];
  %unseen = ();
  open(MAP, "$map") || die "unable to open $map\n";
  while(<MAP>) {
    ($unseen, $seen) = split(/\s/, $_);
    $unseen2seen{$unseen} = $seen;
  }
  open(LEX, "$lex") || die "unable to open $lex\n";
  while(<LEX>) {
    ($word, @syls) = split(/\t/, $_);
    $pron = "$word\t";
    foreach $syl (@syls) {
      $syl =~ s/^\s+//;
      $syl =~ s/\s+$//;
      $syl =~ s/ /=/g;
      if (exists($unseen2seen{$syl})) {
        $pron = "$pron$unseen2seen{$syl}\t ";
      } else {
        $pron = "$pron$syl\t ";
      }
    }
    print "$pron\n";
  }
' $dir/unseen2seen.mapped.txt $oov_lexicon | \
  sed -e 's#\t $##' -e 's#=# #g' > $dir/lexicon.mapped.txt

echo "$0 done";
exit 0;
}
