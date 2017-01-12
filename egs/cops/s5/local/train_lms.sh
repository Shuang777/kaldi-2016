#!/bin/bash
{
set -e
set -o errexit

# Copyright 2016  Hang Su

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

# To be run from one directory above this script.


# Begin configuration section.
swbdata=
fshdata=
lambda_swb=
lambda_fsh=
# end configuration sections

help_message="Usage: $0 [options] <train-txt> <cv-txt> <dict> <out-dir> 
Train language models for cops data, and optionally for Fisher and \n
web-data from University of Washington.\n
options: 
  --help          # print this message and exit
";

. ./path.sh
. utils/parse_options.sh

if [ $# -ne 4 ]; then
  printf "$help_message\n";
  exit 1;
fi

text_tr=$1     # data/local/train/text
text_cv=$2
lexicon=$3  # data/local/dict/lexicon.txt
dir=$4      # data/local/lm

for f in "$text" "$lexicon"; do
  [ ! -f $x ] && echo "$0: No such file $f" && exit 1;
done

loc=`which ngram-count`;
if [ -z $loc ]; then
  if uname -a | grep 64 >/dev/null; then # some kind of 64 bit...
    sdir=`pwd`/../../../tools/srilm/bin/i686-m64 
  else
    sdir=`pwd`/../../../tools/srilm/bin/i686
  fi
  if [ -f $sdir/ngram-count ]; then
    echo Using SRILM tools from $sdir
    export PATH=$PATH:$sdir
  else
    echo You appear to not have SRILM tools installed, either on your path,
    echo or installed in $sdir.  See tools/install_srilm.sh for installation
    echo instructions.
    exit 1
  fi
fi
    
mkdir -p $dir
export LC_ALL=C 

cut -d' ' -f2- $text_tr | gzip -c > $dir/train.gz
cut -d' ' -f2- $text_cv | gzip -c > $dir/cv.gz

cut -d' ' -f1 $lexicon | sort -u > $dir/wordlist

# Bigram language model
ngram-count -text $dir/train.gz -order 2 -limit-vocab -vocab $dir/wordlist \
  -unk -map-unk "<unk>" -kndiscount -interpolate -lm $dir/o2g.kn.gz
echo "PPL for COPS 2gram LM:"
ngram -unk -lm $dir/o2g.kn.gz -ppl $dir/cv.gz
ngram -unk -lm $dir/o2g.kn.gz -ppl $dir/cv.gz -debug 2 >& $dir/2gram.ppl2

# Trigram language model
ngram-count -text $dir/train.gz -order 3 -limit-vocab -vocab $dir/wordlist \
  -unk -map-unk "<unk>" -kndiscount -interpolate -lm $dir/o3g.kn.gz
echo "PPL for COPS 3gram LM:"
ngram -unk -lm $dir/o3g.kn.gz -ppl $dir/cv.gz
ngram -unk -lm $dir/o3g.kn.gz -ppl $dir/cv.gz -debug 2 >& $dir/3gram.ppl2

# 4gram language model
ngram-count -text $dir/train.gz -order 4 -limit-vocab -vocab $dir/wordlist \
  -unk -map-unk "<unk>" -kndiscount -interpolate -lm $dir/o4g.kn.gz
echo "PPL for COPS 4gram LM:"
ngram -unk -lm $dir/o4g.kn.gz -ppl $dir/cv.gz
ngram -unk -lm $dir/o4g.kn.gz -ppl $dir/cv.gz -debug 2 >& $dir/4gram.ppl2

current_lm=o3g.kn.gz
current_ppl=3gram.ppl2

if [ ! -z $swbdata ]; then
  echo "swbdata given, interpolating with it"
  cut -d' ' -f2- $swbdata | local/get_word_count.pl > $dir/swb.vocab
  cut -d' ' -f2- $swbdata | gzip > $dir/swb.train.gz
  ngram-count -text $dir/swb.train.gz -order 3 -limit-vocab -vocab $dir/wordlist \
    -unk -map-unk "<unk>" -kndiscount -interpolate -lm $dir/swb.o3g.kn.gz
  echo "PPL for swb 3gram LM:"
  ngram -unk -lm $dir/swb.o3g.kn.gz -ppl $dir/cv.gz
  ngram -unk -lm $dir/swb.o3g.kn.gz -ppl $dir/cv.gz -debug 2 >& $dir/swb.3gram.ppl2

  compute-best-mix $dir/$current_ppl $dir/swb.3gram.ppl2 >& $dir/swb_mix.3gram.log
  grep 'best lambda' $dir/swb_mix.3gram.log | perl -e '
    $_=<>;
    s/.*\(//; s/\).*//;
    @A = split;
    die "Expecting 2 numbers; found: $_" if(@A!=2);
    print "$A[0]\n$A[1]\n";' > $dir/swb_mix.3gram.weights

  ori_weight=$(head -1 $dir/swb_mix.3gram.weights)
  swb_weight=$(tail -n -1 $dir/swb_mix.3gram.weights)

  if [ ! -z $lambda_swb ]; then
    new_weight=$(echo 1-$lambda_swb | bc)
    echo "Overwrite ori_weight from $ori_weight to $new_weight"
    ori_weight=$new_weight
    echo $ori_weight $lambda_swb > $dir/swb_mix.3gram.weights
  fi

  ngram -order 3 -lm $dir/$current_lm -lambda $ori_weight \
    -mix-lm $dir/swb.o3g.kn.gz \
    -unk -write-lm $dir/swb_mix.3gram.kn.gz
  echo "PPL for swb mix 3gram LM:"
  ngram -unk -lm $dir/swb_mix.3gram.kn.gz -ppl $dir/cv.gz
  ngram -unk -lm $dir/swb_mix.3gram.kn.gz -ppl $dir/cv.gz -debug 2 >& $dir/swb_mix.3gram.ppl2

  current_lm=swb_mix.3gram.kn.gz
  current_ppl=swb_mix.3gram.ppl2
fi

if [ ! -z $fshdata ]; then
  echo "fshdata given, interpolating with it"
  cut -d' ' -f2- $fshdata | local/fisher_map_words.pl | \
    gzip -c > $dir/fsh.train.gz
  gunzip -c $dir/fsh.train.gz | local/get_word_count.pl > $dir/fsh.vocab
  ngram-count -text $dir/fsh.train.gz -order 3 -limit-vocab -vocab $dir/wordlist \
    -unk -map-unk "<unk>" -kndiscount -interpolate -lm $dir/fsh.o3g.kn.gz
  echo "PPL for fsh 3gram LM:"
  ngram -unk -lm $dir/fsh.o3g.kn.gz -ppl $dir/cv.gz
  ngram -unk -lm $dir/fsh.o3g.kn.gz -ppl $dir/cv.gz -debug 2 >& $dir/fsh.3gram.ppl2

  compute-best-mix $dir/$current_ppl $dir/fsh.3gram.ppl2 >& $dir/fsh_mix.3gram.log
  grep 'best lambda' $dir/fsh_mix.3gram.log | perl -e '
    $_=<>;
    s/.*\(//; s/\).*//;
    @A = split;
    die "Expecting 2 numbers; found: $_" if(@A!=2);
    print "$A[0]\n$A[1]\n";' > $dir/fsh_mix.3gram.weights

  ori_weight=$(head -1 $dir/fsh_mix.3gram.weights)
  fsh_weight=$(tail -n -1 $dir/fsh_mix.3gram.weights)
  
  if [ ! -z $lambda_fsh ]; then
    new_weight=$(echo 1-$lambda_fsh | bc)
    echo "Overwrite ori_weight from $ori_weight to $new_weight"
    ori_weight=$new_weight
    echo $new_weight $lambda_fsh > $dir/fsh_mix.3gram.weights
  fi

  ngram -order 3 -lm $dir/$current_lm -lambda $ori_weight \
    -mix-lm $dir/fsh.o3g.kn.gz \
    -unk -write-lm $dir/fsh_mix.3gram.kn.gz
  echo "PPL for fsh mix 3gram LM:"
  ngram -unk -lm $dir/fsh_mix.3gram.kn.gz -ppl $dir/cv.gz

  current_lm=fsh_mix.3gram.kn.gz
fi

(cd $dir; ln -s $current_lm lm.gz)

echo "$0: done successfully!"
}
