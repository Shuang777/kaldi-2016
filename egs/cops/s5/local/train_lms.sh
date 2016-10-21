#!/bin/bash

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
weblm=
# end configuration sections

help_message="Usage: $0 [options] <train-txt> <cv-txt> <dict> <out-dir> 
Train language models for cops data, and optionally for Fisher and \n
web-data from University of Washington.\n
options: 
  --help          # print this message and exit
  --weblm DIR     # directory for web-data from University of Washington
";

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
    

set -o errexit
mkdir -p $dir
export LC_ALL=C 

cut -d' ' -f2- $text_tr | gzip -c > $dir/train.gz
cut -d' ' -f2- $text_cv | gzip -c > $dir/cv.gz

cut -d' ' -f1 $lexicon > $dir/wordlist

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

