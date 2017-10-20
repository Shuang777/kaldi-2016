#!/bin/bash
# Copyright 2012-2013  Johns Hopkins University (Author: Daniel Povey);
#                      Arnab Ghoshal
#           2014       Hang Su

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

# This script prepares a directory such as data/lang/, in the standard format,
# given a source directory containing a dictionary lexicon.txt in a form like:
# word phone1 phone2 ... phoneN
# per line (alternate prons would be separate lines), or a dictionary with probabilities
# called lexiconp.txt in a form:
# word pron-prob phone1 phone2 ... phoneN
# (with 0.0 < pron-prob <= 1.0); note: if lexiconp.txt exists, we use it even if
# lexicon.txt exists.
# and also files silence_phones.txt, nonsilence_phones.txt, optional_silence.txt
# and extra_questions.txt
# Here, silence_phones.txt and nonsilence_phones.txt are lists of silence and
# non-silence phones respectively (where silence includes various kinds of 
# noise, laugh, cough, filled pauses etc., and nonsilence phones includes the 
# "real" phones.)
# In each line of those files is a list of phones, and the phones on each line 
# are assumed to correspond to the same "base phone", i.e. they will be 
# different stress or tone variations of the same basic phone.
# The file "optional_silence.txt" contains just a single phone (typically SIL) 
# which is used for optional silence in the lexicon.
# extra_questions.txt might be empty; typically will consist of lists of phones,
# all members of each list with the same stress or tone; and also possibly a 
# list for the silence phones.  This will augment the automtically generated 
# questions (note: the automatically generated ones will treat all the 
# stress/tone versions of a phone the same, so will not "get to ask" about 
# stress or tone).

# This script adds word-position-dependent phones and constructs a host of other
# derived files, that go in data/lang/.

{

set -e
set -o pipefail

echo "$0 $@"

# Begin configuration section.
num_sil_states=5
num_nonsil_states=3
position_dependent_phones=true
# have been generated by another source
reverse=false
sil_prob=0.5
make_individual_sil_models=false # enforce individual models for all silence phones
# end configuration sections

. utils/parse_options.sh 

if [ $# -ne 3 ]; then 
  echo "usage: $0 <dict> <tmp-dir> <lang-dir>"
  echo " e.g.: $0 data/local/dict data/local/tmp.lang data/lang"
  echo "options: "
  echo "     --sil-prob <probability of silence>             # default: 0.5 [must have 0 <= silprob < 1]"
  exit 1;
fi

wrd2syllex=$1
tmpdir=$2
dir=$3

# add disambig symbols to the lexicon in $tmpdir/lexiconp.syl2phn.txt and $tmpdir/lexiconp.sylwrd2phn.txt
# and produce $tmpdir/lexicon_disambig.syl2phn.txt and $tmpdir/lexicon_disambig.sylwrd2phn.txt

ndisambig=`utils/add_lex_disambig.pl --pron-probs $wrd2syllex $tmpdir/lexiconp_disambig.wrd2syl.txt`
ndisambig=$[$ndisambig+1]; # add one disambig symbol for silence in lexicon FST.
echo $ndisambig > $tmpdir/ndisambig.wrd2syl

# Format of lexiconp_disambig.txt:
# !SIL	1.0   SIL_S
# <SPOKEN_NOISE>	1.0   SPN_S #1
# <UNK>	1.0  SPN_S #2
# <NOISE>	1.0  NSN_S
# !EXCLAMATION-POINT	1.0  EH2_B K_I S_I K_I L_I AH0_I M_I EY1_I SH_I AH0_I N_I P_I OY2_I N_I T_E

( for n in `seq 0 $ndisambig`; do echo '#'$n; done ) >$dir/phones/disambig.wrd2syl.txt

cat $wrd2syllex $(dirname $wrd2syllex)/kw.oov.list | awk '{print $1}' | sort | uniq  | \
 awk 'BEGIN{print "<eps> 0"; } {printf("%s %d\n", $1, NR);} END{printf("#0 %d\n", NR+1);} ' \
   > $dir/words.merge.txt

( for n in `seq 1 $ndisambig`; do echo '#'$n; done) | cat $dir/syls.txt - | awk '{if (NF==1) print $1, (NR-1); else print;}' > $dir/syls.merge.txt

utils/sym2int.pl $dir/syls.merge.txt $dir/phones/disambig.wrd2syl.txt > $dir/phones/disambig.wrd2syl.int

syl_disambig_symbol=`grep \#0 $dir/syls.merge.txt | awk '{print $2}'`
word_disambig_symbol=`grep \#0 $dir/words.merge.txt | awk '{print $2}'`

cat $wrd2syllex | mylocal/prepare_wrd2phn_align.pl $tmpdir/lexiconp.syl2phn.txt > $tmpdir/align_lexicon.wrd2syl.txt

# Note: here, $silphone will have no suffix e.g. _S because it occurs as optional-silence,
# and is not part of a word.
silphone=`cat $(dirname $wrd2syllex)/optional_silence.txt`
[ ! -z "$silphone" ] && echo "<eps> $silphone" >> $tmpdir/align_lexicon.wrd2syl.txt

cat $tmpdir/align_lexicon.wrd2syl.txt | \
  perl -ane '@A = split; print $A[0], " ", join(" ", @A), "\n";' | sort | uniq > $dir/phones/align_lexicon.wrd2syl.txt

# create phones/align_lexicon.int
cat $dir/phones/align_lexicon.wrd2syl.txt | utils/sym2int.pl -f 3- $dir/phones.syl2phn.txt | \
  utils/sym2int.pl -f 1-2 $dir/words.merge.txt > $dir/phones/align_lexicon.wrd2syl.int

# prepare align_lexicon.syl.int
perl -ape 's/(\S+\s+)\S+\s+(.+)/$1$2/;' < $wrd2syllex > $tmpdir/align_lexicon.syl.txt

# Note: here, $silphone will have no suffix e.g. _S because it occurs as optional-silence,
# and is not part of a word.
silphone=`cat $(dirname $wrd2syllex)/optional_silence.txt`
[ ! -z "$silphone" ] && echo "<eps> $silphone" >> $tmpdir/align_lexicon.syl.txt

cat $tmpdir/align_lexicon.syl.txt | \
  perl -ane '@A = split; print $A[0], " ", join(" ", @A), "\n";' | sort | uniq > $dir/phones/align_lexicon.syl.txt

# create phones/align_lexicon.int
cat $dir/phones/align_lexicon.syl.txt | utils/sym2int.pl -f 3- $dir/syls.merge.txt | \
  utils/sym2int.pl -f 1-2 $dir/words.merge.txt > $dir/phones/align_lexicon.syl.int

# Create the basic L.fst without disambiguation symbols, for use
# in training. 
utils/make_lexicon_fst.pl --pron-probs $tmpdir/lexiconp_disambig.wrd2syl.txt $sil_prob $silphone '#'$ndisambig | \
  fstcompile --isymbols=$dir/syls.merge.txt --osymbols=$dir/words.merge.txt \
  --keep_isymbols=false --keep_osymbols=false | \
  fstdeterminizestar | fstrmsymbols $dir/phones/disambig.wrd2syl.int | \
  fstarcsort --sort_type=olabel > $dir/Ldet.wrd2syl.fst || exit 1;

silword=`grep $silphone $tmpdir/lexiconp_disambig.wrd2syl.txt | awk '{print $1}'`
myutils/make_lexicon_fst_end.pl --pron-probs $tmpdir/lexiconp_disambig.wrd2syl.txt $sil_prob $silphone $silword '#'$ndisambig | \
  fstcompile --isymbols=$dir/syls.merge.txt --osymbols=$dir/words.merge.txt \
  --keep_isymbols=false --keep_osymbols=false | \
  fstdeterminizestar | fstrmsymbols $dir/phones/disambig.wrd2syl.int | \
  fstarcsort --sort_type=olabel > $dir/Ldet.wrd2sylT.fst || exit 1;

utils/make_lexicon_fst.pl --pron-probs $tmpdir/lexiconp_disambig.wrd2syl.txt $sil_prob $silphone '#'$ndisambig | \
  fstcompile --isymbols=$dir/syls.merge.txt --osymbols=$dir/words.merge.txt \
  --keep_isymbols=false --keep_osymbols=false | \
  fstaddselfloops "echo $syl_disambig_symbol |" "echo $word_disambig_symbol |" | \
  fstarcsort --sort_type=olabel > $dir/L_disambig.wrd2syl.fst || exit 1;

# give same result
# phi=`grep -w '#0' $dir/words.merge.txt | awk '{print $2}'`
# fstprint $dir/L_disambig.wrd2syl.fst | awk '{if($4 != '$phi'){print;}}' | fstcompile | \
#  fstdeterminizestar | fstrmsymbols $dir/phones/disambig.wrd2syl.int > $dir/Ldet.wrd2syl2.fst

# temp codes
localdir=$(dirname $wrd2syllex)
awk 'NR==FNR {if ($3 ~ /^</) {map[$1]=$3;} next} { printf "%s\t1.0",$1; for (i=3; i<=NF; i++) { if ($i~ /^</) {printf "\t%s",map[$i]} else {printf "\t%s",$i}} printf "\n"}' $localdir/lexiconp.syl2phn.txt $wrd2syllex | tr '=' ' ' > $localdir/lexiconp.merge.txt

if $position_dependent_phones; then
  perl -ane '@A=split(" ",$_); $w = shift @A; $p = shift @A; @A>0||die;
           if(@A==1) { print "$w $p $A[0]_S\n"; } else { print "$w $p $A[0]_B ";
           for($n=1;$n<@A-1;$n++) { print "$A[$n]_I "; } print "$A[$n]_E\n"; } ' < $localdir/lexiconp.merge.txt > $tmpdir/lexiconp.merge.txt
else
  cp $localdir/lexiconp.merge.txt $tmpdir/lexiconp.merge.txt 
fi

ndisambig=`utils/add_lex_disambig.pl --pron-probs $tmpdir/lexiconp.merge.txt $tmpdir/lexiconp_disambig.merge.txt`
ndisambig=$[$ndisambig+1]; # add one disambig symbol for silence in lexicon FST.
echo $ndisambig > $tmpdir/lex_ndisambig.merge

( for n in `seq 0 $ndisambig`; do echo '#'$n; done ) >$dir/phones/disambig.merge.txt

echo "<eps>" | cat - $dir/phones/{silence,nonsilence,disambig.merge}.txt | \
  awk '{n=NR-1; print $1, n;}' > $dir/phones.merge.txt

phone_disambig_symbol=`grep \#0 $dir/phones.merge.txt | awk '{print $2}'`

utils/make_lexicon_fst.pl --pron-probs $tmpdir/lexiconp.merge.txt $sil_prob $silphone | \
  fstcompile --isymbols=$dir/phones.merge.txt --osymbols=$dir/words.merge.txt \
  --keep_isymbols=false --keep_osymbols=false | \
  fstarcsort --sort_type=olabel > $dir/L.merge.fst || exit 1;

for f in disambig; do
  utils/sym2int.pl $dir/phones.merge.txt <$dir/phones/$f.merge.txt >$dir/phones/$f.merge.int
  utils/sym2int.pl $dir/phones.merge.txt <$dir/phones/$f.merge.txt | \
    awk '{printf(":%d", $1);} END{printf "\n"}' | sed s/:// > $dir/phones/$f.merge.csl || exit 1;
done 

utils/make_lexicon_fst.pl --pron-probs $tmpdir/lexiconp_disambig.merge.txt $sil_prob $silphone '#'$ndisambig | \
  fstcompile --isymbols=$dir/phones.merge.txt --osymbols=$dir/words.merge.txt \
  --keep_isymbols=false --keep_osymbols=false |   \
  fstaddselfloops  "echo $phone_disambig_symbol |" "echo $word_disambig_symbol |" | \
  fstarcsort --sort_type=olabel > $dir/L_disambig.merge.fst || exit 1;

exit 0;

}