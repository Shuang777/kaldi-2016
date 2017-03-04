#!/bin/bash

{

# Begin configuration
stage=0
seq1_max=2
seq2_max=7
ngram_order_max=7
phnsyl=phn          # phn, syl, sylbound, csyl
# End configuration

echo "$0 $@"

. parse_options.sh
. ./path.sh
. ./g2p_path.sh

if [ $# != 2 ]; then
  echo "Usage: $0 <lexicon> <dir>"
  exit 1
fi

lexicon=$1
dir=$2

[ -d $dir ] || mkdir -p $dir

# Input lexicon is of the form
#
# word_1	phone1 phone2	 phone3 phone4	
#
# where syllables are separated by '\t '

if [ $phnsyl == syl ]; then
  # directly align grapheme with syllable
  sed -e 's# #=#g' -e 's#\t=# #g' -e 's#\t$##g' $lexicon > $dir/lexicon2align.tmp
elif [ $phnsyl == sylbound ]; then
  # similar to G2P but with syllable boundary included
  sed -e 's#\t # = #g' -e 's#\t$# =#g' $lexicon > $dir/lexicon2align.tmp
elif [ $phnsyl == phn ] || [ $phnsyl == csyl ] || [ $phnsyl == phn2syl ]; then
  # for phone g2p model, we need to change syllable sep '\t' to ' '
  sed -e 's#\t # #g' -e 's#\t$##g' $lexicon > $dir/lexicon2align.tmp
else
  echo "Unknown phnsyl type $phnsyl";
  exit 1
fi

# we need to substitute '|' and '}' because this is used as separater in alignment file in Phonetisaurus
# we assume only phones may contain those two
sed -e 's#|#vbar#g' -e 's#}#rbrk#g' $dir/lexicon2align.tmp > $dir/lexicon2align.tmp2

# we also remove '_' in graphemes
awk -F'\t' '{gsub(/_/,"", $1); printf("%s\t%s\n", $1, $2); }' $dir/lexicon2align.tmp2 > $dir/lexicon2align.txt

if [ $stage -le 0 ]; then
  cmd="phonetisaurus-align \
    --input=$dir/lexicon2align.txt \
    --ofile=$dir/lexicon_aligned.txt \
    --skip='.' \
    --seq1_del=false \
    --seq2_del=false \
    --seq1_max=$seq1_max \
    --seq2_max=$seq2_max"

  echo $cmd
  eval $cmd
fi

if [ $stage -le 1 ]; then
  for order in `seq $ngram_order_max -1 1`; do
    ngram-count \
      -order $order \
      -kn-modify-counts-at-end \
      -gt1min 0 -gt2min 0 -gt3min 0 -gt4min 0 \
      -gt5min 0 -gt6min 0 -gt7min 0 \
      -ukndiscount -ukndiscount1 -ukndiscount2 \
      -ukndiscount3 -ukndiscount4 -ukndiscount5 \
      -ukndiscount6 -ukndiscount7 \
      -text $dir/lexicon_aligned.txt \
      -lm $dir/align.lm

    if [ $? -eq 0 ]; then
      echo "LM of order $order built"
      break
    else
      echo "Problems building LM order $order... backing off"
    fi
  done
fi

if [ $stage -le 2 ]; then
  echo "convert language model to fst"
  phonetisaurus-arpa2wfst \
    --lm=$dir/align.lm \
    --ofile=$dir/lm.fst
fi

[ -f $dir/final.fst ] && rm $dir/final.fst

if [ $phnsyl == csyl ]; then
  echo "Building fsts with syllable constraints"
  fstsymbols --save_osymbols=$dir/phoneseq.syms $dir/lm.fst > /dev/null

  g2p/accumulate_syllable_stats.pl $lexicon $dir/phoneseq.syms $dir

  echo "Composing FSTs..."
  # build phoneseq2phoneonc
  fstcompile --isymbols=$dir/phoneseq.syms --osymbols=$dir/phoneonc.syms \
    --keep_isymbols=true --keep_osymbols=true $dir/phoneseq2phoneonc.txt | \
    fstarcsort --sort_type='olabel' > $dir/phoneseq2phoneonc.fst

  # build phoneonc2onc
  fstcompile --isymbols=$dir/phoneonc.syms --osymbols=$dir/onc.syms \
    --keep_isymbols=true --keep_osymbols=true $dir/phoneonc2onc.txt | \
    fstarcsort --sort_type='olabel' > $dir/phoneonc2onc.fst

  # build onc acceptor
  fstcompile --acceptor=true --isymbols=$dir/onc.syms \
    --keep_isymbols --keep_osymbols $dir/onc_constraint.fst.txt | \
    fstarcsort --sort_type='ilabel' > $dir/onc_constraint.fst

  # compose the three fst above and project to the input side
  # the joint fst is phoneseq2phoneonc
  fstcompose $dir/phoneonc2onc.fst $dir/onc_constraint.fst | \
    fstproject --project_output=false | \
    fstarcsort --sort_type='ilabel' | \
    fstcompose $dir/phoneseq2phoneonc.fst - > $dir/phonejoint.fst

  # compose with original fst
  fstarcsort --sort_type='olabel' $dir/lm.fst | \
    fstcompose - $dir/phonejoint.fst | \
    fstarcsort > $dir/g2s.fst

  # build onc wfst for boundary
  fstcompile --isymbols=$dir/onc.syms --osymbols=$dir/onc_boundary.syms \
    --keep_isymbols --keep_osymbols $dir/onc_boundary.fst.txt | \
    fstarcsort --sort_type='ilabel' > $dir/onc_boundary.fst

  (cd $dir; ln -s g2s.fst final.fst)
elif [ $phnsyl == phn2syl ]; then
  echo "Building fsts with phone2syllable approach"
  fstsymbols --save_osymbols=$dir/phoneseq.syms $dir/lm.fst > /dev/null

  g2p/accumulate_phone2syllable.pl $lexicon $dir/phoneseq.syms $dir

  echo "Composing FSTs..."
  fstcompile --isymbols=$dir/phoneseq.syms --osymbols=$dir/phone.syms \
    --keep_isymbols=true --keep_osymbols=true $dir/phoneseq2phone.txt | \
    fstarcsort --sort_type='olabel' > $dir/phoneseq2phone.fst

  fstcompile --isymbols=$dir/phone.syms --osymbols=$dir/syllable.syms \
    --keep_isymbols=true --keep_osymbols=true $dir/phone2syl.txt | \
    fstarcsort --sort_type='olabel' > $dir/phone2syl.fst

  # now compose fsts together
  fstcompose $dir/phoneseq2phone.fst $dir/phone2syl.fst > $dir/phoneseq2syl.fst

  fstarcsort --sort_type='olabel' $dir/lm.fst | \
    fstcompose - $dir/phoneseq2syl.fst | \
    fstarcsort > $dir/g2s.fst

  (cd $dir; ln -s g2s.fst final.fst)
else
  (cd $dir; ln -s lm.fst final.fst)
fi

echo "$0 done with final.fst built";
}
