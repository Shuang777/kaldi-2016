#!/bin/bash
# Copyright Johns Hopkins University (Author: Daniel Povey) 2012.  Apache 2.0.
{
set -e
set -o pipefail

# begin configuration section.
cmd=run.pl
stage=0
min_lmwt=5
max_lmwt=20
iter=final
#end configuration section.

echo "$0 $@"

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 3 ]; then
  echo "Usage: local/score_sclite.sh [--cmd (run.pl|queue.pl...)] <data-dir> <lang-dir|graph-dir> <decode-dir>"
  echo " Options:"
  echo "    --cmd (run.pl|queue.pl...)      # specify how to run the sub-processes."
  echo "    --stage (0|1|2)                 # start scoring script from part-way through."
  echo "    --min_lmwt <int>                # minumum LM-weight for lattice rescoring "
  echo "    --max_lmwt <int>                # maximum LM-weight for lattice rescoring "
  exit 1;
fi

data=$1
lang=$2 # Note: may be graph directory not lang directory, but has the necessary stuff copied.
dir=$3

model=$dir/../$iter.mdl # assume model one level up from decoding dir.

for f in $data/stm $lang/words.txt $lang/phones/word_boundary.int \
     $model $data/segments $data/reco2file_and_channel $dir/lat.1.gz; do
  [ ! -f $f ] && echo "$0: expecting file $f to exist" && exit 1;
done

name=`basename $data`; # e.g. eval2000

mkdir -p $dir/scoring/log

if [ $stage -le 0 ]; then
  $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/get_ctm.LMWT.log \
    mkdir -p $dir/score_LMWT/ '&&' \
    lattice-1best --lm-scale=LMWT "ark:gunzip -c $dir/lat.*.gz|" ark:- \| \
    lattice-align-words $lang/phones/word_boundary.int $model ark:- ark:- \| \
    nbest-to-ctm ark:- - \| \
    utils/int2sym.pl -f 5 $lang/words.txt  \| \
    utils/convert_ctm.pl $data/segments $data/reco2file_and_channel \
    '>' $dir/score_LMWT/$name.ctm || exit 1;
fi

if [ $stage -le 1 ]; then
  # Remove some stuff we don't want to score, from the ctm.
  for x in $dir/score_*/$name.ctm; do
    cp $x $x.bkup1;
    cat $x.bkup1 | grep -v -E '\[NOISE|LAUGHTER|VOCALIZED-NOISE\]' | \
      grep -v -E '<UNK>|%HESITATION|\(\(\)\)' | \
      grep -v -E '<eps>' | \
      grep -v -E '<noise>' | \
      grep -v -E '<silence>' | \
      grep -v -E '<hes>' | \
      grep -v -E '<unk>' | \
      grep -v -E '<v-noise>' | \
      perl -e '@list = (); %list = ();
      while(<>) {
        chomp;
        @col = split(" ", $_);
        push(@list, $_);
        $key = "$col[0]" . " $col[1]";
        $list{$key} = 1;
      }
      foreach(sort keys %list) {
        $key = $_;
        foreach(grep(/$key/, @list)) {
          print "$_\n";
        }
      }' > $x;
  done
fi


ScoringProgram=`which sclite` || ScoringProgram=$KALDI_ROOT/tools/sctk/bin/sclite
[ ! -x $ScoringProgram ] && echo "Cannot find scoring program at $ScoringProgram" && exit 1;
SortingProgram=`which hubscr.pl` || SortingProgram=$KALDI_ROOT/tools/sctk/bin/hubscr.pl
[ ! -x $ScoringProgram ] && echo "Cannot find scoring program at $ScoringProgram" && exit 1;

if [ $stage -le 2 ] ; then
  $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/score.LMWT.log \
    set -e';' set -o pipefail';' \
    cp -f $data/stm $dir/score_LMWT/stm.unsorted '&&' \
    cp -f $dir/score_LMWT/${name}.ctm $dir/score_LMWT/${name}.ctm.unsorted '&&'\
    $SortingProgram sortSTM \<$dir/score_LMWT/stm.unsorted          \>$dir/score_LMWT/stm.sorted '&&' \
    $SortingProgram sortCTM \<$dir/score_LMWT/${name}.ctm.unsorted  \>$dir/score_LMWT/${name}.ctm.sorted '&&' \
    paste -d ' ' \<\(cut -f 1-5 -d ' ' $dir/score_LMWT/stm.sorted \) \
                 \<\(cut -f 6- -d ' ' $dir/score_LMWT/stm.sorted \| uconv -f utf8 -t utf8 -x "$icu_transform" \) \
        \> $dir/score_LMWT/stm '&&' \
    paste -d ' ' \<\(cut -f 1-4 -d ' ' $dir/score_LMWT/${name}.ctm.sorted \) \
                 \<\(cut -f 5-  -d ' ' $dir/score_LMWT/${name}.ctm.sorted \| uconv -f utf8 -t utf8 -x "$icu_transform" \) \
        \> $dir/score_LMWT/${name}.ctm '&&' \
    $ScoringProgram -s -r $dir/score_LMWT/stm  stm -h $dir/score_LMWT/${name}.ctm ctm \
      -n "$name.ctm" -f 0 -D -F  -o  sum rsum prf dtl sgml -e utf-8 || exit 1
fi


exit 0
}
