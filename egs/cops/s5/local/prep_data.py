#!/usr/bin/python
import json
import sys
import os

def get_sec(time_str):
  h, m, s = time_str.split(':')
  return int(h) * 3600 + int(m) * 60 + int(s)

dir=sys.argv[1]
data=json.load(sys.stdin)

fsegment = open(os.path.join(dir, "segments"), "w")
ftext = open(os.path.join(dir, "text"), "w")
fsplit = open(os.path.join(dir, "split"), "w")
futt2spk = open(os.path.join(dir, "utt2spk"), "w")
fchn2spk = open(os.path.join(dir, "chn2spk"), "w")
fwrong = open(os.path.join(dir, "wrong.txt"), "w")
fusable = open(os.path.join(dir, "usable.txt"), "w")

wrong_flist = set(['PICT0003_2014.04.10_01.48.48', 'PICT0004_2014.04.09_23.54.16', 'PICT0005_2014.04.02_21.15.46', 'PICT0002_2014.04.24_02.14.00', 'PICT0004_2014.04.18_04.06.18', 'PICT0002_2014.04.24_09.31.56'])

count_total_utt = 0
count_total_recording = 0
count_notrans = 0
count_nosplit = 0
count_wrong_time = 0
channels = {}
for key, info in data.iteritems():
  count_total_recording += 1
  if key in channels:
    print "%s already processed, skipping" % key
    continue
  channels[key] = True
  if key in wrong_flist:
    # these files are totally off
    continue
  if 'transcript' not in info:
    count_notrans += 1
    continue
  if 'data_split' not in info:
    count_nosplit += 1
    continue
  data_split = info['data_split']
  count_item = 0
  last_time = 0
  last_dur = 0
  last_utt = {}
  spk = info['EmpID1']
  fchn2spk.write("%s %s\n" % (key, spk))
  channel_key = spk + "_" + key
  fsplit.write("%s %s\n" % (channel_key, data_split))
  for item in info['transcript']:
    if 'utterance' not in item or 'usable' not in item or 'speaker' not in item:
      continue
    count_item += 1
    if item['speaker'] != 'OFFICER' and item['speaker'] != 'OFFICER FEM':
      continue
    count_total_utt += 1
    utt = "%s_%04d" % (channel_key, count_item)
    start_time = get_sec(item['start'])
    end_time = get_sec(item['end']) + 0.99    # we assume the end time include this second till 0.99s
    fusable.write("%s %s\n" % (utt, item['usable']))
    if start_time > end_time:
      count_wrong_time += 1
      fwrong.write("%s %s\n" %(channel_key, item))
      continue
    if last_time - start_time > 2:
      fwrong.write("%s %s\n" %(channel_key, item))
    if last_time > start_time and (end_time - start_time + last_dur) < 20:  
      # if overlap and not too long yet, we concatenate them
      last_utt['end'] = end_time
      last_utt['utterance'] = " ".join([last_utt['utterance'], item['utterance']])
    else:
      # print last utterance and record the new utterance
      if last_utt:
        fsegment.write("%s %s %.2f %.2f\n" % (last_utt['utt'], last_utt['key'], last_utt['start'], last_utt['end']))
        ftext.write("%s %s\n" % (last_utt['utt'], last_utt['utterance']))
        futt2spk.write("%s %s\n" % (last_utt['utt'], spk))
      last_utt = {"utt": utt,
                  "key": channel_key,
                  "start": start_time,
                  "end": end_time,
                  "utterance": item['utterance']
                  }
    last_time = end_time
    last_dur = end_time - start_time
  if last_utt:
    fsegment.write("%s %s %.2f %.2f\n" % (last_utt['utt'], last_utt['key'], last_utt['start'], last_utt['end']))
    ftext.write("%s %s\n" % (last_utt['utt'], last_utt['utterance']))
    futt2spk.write("%s %s\n" % (last_utt['utt'], spk))

fsegment.close()
ftext.close()
fsplit.close()
futt2spk.close()
fwrong.close()

print "%d recordings processed, %d no transcripts, %d no data_split info" % \
    (count_total_recording, count_notrans, count_nosplit)
print "%d utterances prepared in total. %d utterance with wrong time" % (count_total_utt, count_wrong_time)
