#!/bin/bash
#
{
set -e
set -o pipefail

# To be run from one directory above this script.

## The input is some directory containing the switchboard-1 release 2
## corpus (LDC97S62).  Note: we don't make many assumptions about how
## you unpacked this.  We are just doing a "find" command to locate
## the .sph files.

# for example /mnt/matylda2/data/SWITCHBOARD_1R2

. ./path.sh

# The parts of the output of this that will be needed are
# [in data/local/dict/ ]
# lexicon.txt
# extra_questions.txt
# nonsilence_phones.txt
# optional_silence.txt
# silence_phones.txt


#check existing directories
[ $# != 1 ] && echo "Usage: $0 data" && exit 1;
data=$1

dir=$data/local/dict
mkdir -p $dir
echo "Getting CMU dictionary"
[ -f $dir/cmudict/cmudict.0.7a.symbols ] || svn co  https://svn.code.sf.net/p/cmusphinx/code/trunk/cmudict  $dir/cmudict

# silence phones, one per line. 
for w in sil laughter noise oov; do echo $w; done > $dir/silence_phones.txt
echo sil > $dir/optional_silence.txt

# For this setup we're discarding stress.
cat $dir/cmudict/cmudict.0.7a.symbols | sed s/[0-9]//g | \
 tr '[A-Z]' '[a-z]' | perl -ane 's:\r::; print;' | sort | uniq > $dir/nonsilence_phones.txt

# An extra question will be added by including the silence phones in one class.
cat $dir/silence_phones.txt| awk '{printf("%s ", $1);} END{printf "\n";}' > $dir/extra_questions.txt || exit 1;

grep -v ';;;' $dir/cmudict/cmudict.0.7a |  tr '[A-Z]' '[a-z]' | \
 perl -ane 'if(!m:^;;;:){ s:(\S+)\(\d+\) :$1 :; s:  : :; print; }' | \
 perl -ane '@A = split(" ", $_); for ($n = 1; $n<@A;$n++) { $A[$n] =~ s/[0-9]//g; } print join(" ", @A) . "\n";' | \
 sort | uniq > $dir/lexicon1_raw_nosil.txt || exit 1;

# Add prons for laughter, noise, oov
for w in `grep -v sil $dir/silence_phones.txt`; do
  echo "[$w] $w"
done | cat - $dir/lexicon1_raw_nosil.txt  > $dir/lexicon2_raw.txt

cat $dir/lexicon2_raw.txt local/lexicon_fix_cmudict_v2.txt \
   <( echo "mm m"
      echo "<unk> oov" ) > $dir/lexicon4_extra.txt


cp $dir/lexicon4_extra.txt $dir/lexicon.txt
[ -f $dir/lexiconp.txt ] && rm $dir/lexiconp.txt 2>/dev/null; # can confuse later script if this exists.

<< oov
awk '{print $1}' $dir/lexicon.txt | \
  perl -e '($word_counts)=@ARGV;
   open(W, "<$word_counts")||die "opening word-counts $word_counts";
   while(<STDIN>) { chop; $seen{$_}=1; }
   while(<W>) {
     ($c,$w) = split;
     if (!defined $seen{$w}) { print; }
   } ' $dir/word_counts > $dir/oov_counts.txt

echo "*Highest-count OOVs are:"
head -n 20 $dir/oov_counts.txt
oov

utils/validate_dict_dir.pl $dir
exit 0;
}
