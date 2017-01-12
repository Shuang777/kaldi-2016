#!/usr/bin/env python

import sys
import json

def sec2str(seconds):
  sec_int = int(round(seconds))
  hh = sec_int / 3600
  mm = (sec_int - hh * 3600) / 60
  ss = sec_int - hh * 3600 - mm * 60
  return "%d:%02d:%02d" % (hh, mm, ss)


if len(sys.argv) != 4:
  print "Usage:", __file__, "<segment> <text> <json>"
  print " e.g.:", __file__, "data/dev/segmetns data/dev/text trans.json"
  sys.exit(1)


segment_filename = sys.argv[1]
text_filename = sys.argv[2]
output_filename = sys.argv[3]

start_time = {}
end_time = {}
utt2chn = {}
utt2id = {}

with open(segment_filename) as segmentfile:
  for line in segmentfile:
    fields = line.split()
    utt = fields[0]
    start_time[utt] = float(fields[2]);
    end_time[utt] = float(fields[3]);
    id, chn = fields[1].split("_", 1)
    utt2chn[utt] = chn
    utt2id[utt] = id


data = {}
with open(text_filename) as textfile:
  for line in textfile:
    utt, text = line.split(" ", 1)
    chn = utt2chn[utt]
    if chn not in data:
      data[chn] = { 
          'EmpID1': utt2id[utt],
          'transcript': []
          }
  
    start = sec2str(start_time[utt])
    end = sec2str(end_time[utt])
    utt_info = { 
        'start': start,
        'end': end,
        'usable': True,
        'speaker': 'OFFICER',
        'utterance': text.strip()
        }
    data[chn]['transcript'].append(utt_info)


with open(output_filename, 'w') as outfile:
  json.dump(data, outfile)
