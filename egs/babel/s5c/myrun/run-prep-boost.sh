#!/bin/bash

kwfile="/u/drspeech/projects/swordfish/IndusDB/IndusDB.latest/IARPA-babel204b-v1.1b_conv-dev.kwlist5.xml"

# get the keywords
grep '<kwtext>' $kwfile | cut -f2 -d'>' | cut -f1 -d'<' | tr ' ' '\n' > tmp/all.keywords

cat data/train/text | cut -f2- -d' ' > tmp/train.txt
cat data/dev10h/text | cut -f2- -d' ' > tmp/dev10h.txt
cat data/lang/words.txt | awk '{print $1}' | grep -v '\#0' | grep -v '<eps>' > tmp/vocab

# the regular ngram
ngram-count -order 3 -text tmp/train.txt -vocab tmp/all.vocab -unk -kndiscount -lm tmp/llp.lm

# main text unigram
ngram-count -order 1 -text tmp/train.txt -vocab tmp/all.vocab -unk -lm tmp/llp.unigram.lm -kndiscount

cat data/lang_wrd2syl/words.txt | awk '{print $1}' | grep -v '\#0' | grep -v '<eps>' > tmp/all.vocab
# keywords unigram
ngram-count -order 1 -text tmp/all.keywords -unk -lm tmp/kws.unigram.lm  -vocab tmp/all.vocab -kndiscount

#interpolate the unigram models
ngram -vocab tmp/all.vocab -lm tmp/llp.unigram.lm -lambda 0.5 -mix-lm tmp/kws.unigram.lm -write-lm tmp/combined.unigram.lm -unk

ngram -lm tmp/combined.unigram.lm -renorm -write-lm tmp/combined.unigram.lm.norm

# adapt overall model
ngram -vocab tmp/all.vocab -lm tmp/llp.lm -adapt-marginals tmp/combined.unigram.lm.norm -rescore-ngram tmp/llp.lm -write-lm tmp/boosted.lm
