#!/usr/bin/python

import sys

# read unsort tra and llk file and sort the utterance according to llk (from high to low)

tra_unsort = sys.argv[1]
llk_unsort = sys.argv[2]

f_llk_unsort = open(llk_unsort)
utt_hyp2llk = {}
for line in f_llk_unsort:
  utt_hyp, llk = line.strip().split()
  utt_hyp2llk[utt_hyp] = float(llk)

f_tra_unsort = open(tra_unsort)
utt2hyps = {}
utt_list = []     # we need to maintain the order of utterances
for line in f_tra_unsort:
  fields = line.strip().split(' ')
  utt_hyp = fields[0]
  if len(fields) > 1:
    tra = ' '.join(fields[1:])
  else:
    tra = ""

  utt, hyp_id = utt_hyp.rsplit('-', 1)
  if utt in utt2hyps:
    utt2hyps[utt].append((utt_hyp2llk[utt_hyp], tra))
  else:
    utt2hyps[utt] = [(utt_hyp2llk[utt_hyp], tra)]
    utt_list.append(utt)


for utt in utt_list:
  hyps = utt2hyps[utt]
  hyps_sorted = sorted(hyps, reverse=True)
  count = 1
  for (llk, hyp) in hyps_sorted:
    print("%s-%d %s %s" % (utt, count, llk, hyp))
    count += 1
