#!/usr/bin/python
import json
import sys
import os

def get_sec(time_str, plus = 0):
  ''' we are going to deal with two scenario
  1: time is given by hh:mm:ss
  2: time is given by hh:mm:ss.ss

  for 1st format, we add plus to miliseconds
  for 2nd format, we just use what was given
  '''
  h, m, s = time_str.split(':')
  if len(s.split('.')) > 1:
    return int(h) * 3600 + int(m) * 60 + float(s)
  else:
    return int(h) * 3600 + int(m) * 60 + int(s) + plus

chn_rob_vinod = sys.argv[1]
dir = sys.argv[2]
data = json.load(sys.stdin)

chn_no_concat = {}
with open(chn_rob_vinod) as f:
  for line in f:
    chn_no_concat[line.strip()] = None

fsegment = open(os.path.join(dir, "segments"), "w")
futtadd = open(os.path.join(dir, "uttid_add"), "w")   # record utts not from an officer
ftext = open(os.path.join(dir, "text"), "w")
futt2spk = open(os.path.join(dir, "utt2spk"), "w")
futt2chn = open(os.path.join(dir, "utt2chn"), "w")
fwrong = open(os.path.join(dir, "wrong.txt"), "w")
fusable = open(os.path.join(dir, "usable.txt"), "w")  # usable market in json (for NLP analysis)
fmeta = open(os.path.join(dir, "meta.txt"), "w")      # with meta information
futt2time = open(os.path.join(dir, "utt2time"), "w")
utt2uttid = open(os.path.join(dir, 'utt2uttid'), 'w') # mark utt to channel + index 

wrong_flist = set(['PICT0005_2014.04.02_21.15.46'])   # this is spanish, and no time info
short_flist = set(['PICT0008_2014.04.16_00.30.54', 'PICT0001_2014.04.17_04.15.42', 'PICT0010_2014.04.18_01.39.30'])  # they are not transcribed

spk2spk = {'OFFICER_2': 'OFFICER2',
           'OFFICER1': 'OFFICER',
           'OFFICER_1' : 'OFFICER',
           'FEM_OFFICER': 'OFFICER_FEM',
           'OFFICER_fem': 'OFFICER_FEM',
           'FEM_OFFICER_0': 'OFFICER_FEM',
           'FEM_OFFICER_1': 'OFFICER_FEM',
           'FEM_OFFICER_2': 'OFFICER_FEM2',
           'OFFICER_FEM_2': 'OFFICER_FEM2',
           'OFFICER_FEMALE': 'OFFICER_FEM',
           'OFFICER_FEMALE_2': 'OFFICER_FEM2',
           'FEMALE_OFFICER': 'OFFICER_FEM',
           'MAL_OFFICER': 'OFFICER',
           'MALE_OFFICER': 'OFFICER',
           'OFFICER_3': 'OFFICER3',
           'OFFICER_I': 'OFFICER2',
           'OFFICER_OFFICER': 'OFFICER',
           'OFFICER_OFFICER2': 'OFFICER_OFFICER',
           'OFFICER_X': 'OFFICER3'
          }

count_total_utt = 0
count_total_recording = 0
count_notrans = 0
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
  last_time = 0
  last_dur = 0
  last_utt = {}
  for item in info['transcript']:
    count_id = item['count_id']
    if 'utterance' not in item or 'usable' not in item or 'speaker' not in item:
      continue
    if 'OFFICER' not in item['speaker']:    # we only care about officer's voice; but we record the text.. and use for language modeling
      utt = "%s-%04d" % (key, count_id)
      futtadd.write("%s\n" % utt)
      ftext.write("%s %s\n" % (utt, item['utterance']))
      continue
    count_total_utt += 1
    chn_spk = item['speaker'].replace(" ","_")
    if chn_spk in spk2spk:
      chn_spk = spk2spk[chn_spk]
    spk = "%s_%s" % (key, chn_spk)
    utt = "%s-%04d" % (spk, count_id)
    utt2uttid.write("%s %s %d\n" % (utt, key, count_id))
    start_time = get_sec(item['start'])
    end_time = get_sec(item['end'], 0.99)
    fusable.write("%s %s\n" % (utt, item['usable']))
    futt2time.write("%s %s %s\n" % (utt, item['start'], item['end']))
    if 'meta' in item:
      fmeta.write("%s %s\n" % (utt, item['meta']))
    if start_time > end_time:
      count_wrong_time += 1
      fwrong.write("%s %s\n" %(utt, item))
      continue
    if last_time - start_time > 2:
      fwrong.write("%s %s\n" %(utt, item))

    if key in chn_no_concat:
      fsegment.write("%s %s %.2f %.2f\n" % (utt, key, start_time, end_time))
      ftext.write("%s %s\n" % (utt, item['utterance']))
      futt2spk.write("%s %s\n" % (utt, spk))
      futt2chn.write("%s %s\n" % (utt, key))
    else:       # concat by default
      if last_time > start_time and (end_time - start_time + last_dur) < 20 and spk == last_utt['spk']:  
        # if overlap and not too long yet, and from same speaker, we concatenate them
        last_utt['end'] = end_time
        last_utt['utterance'] = " ".join([last_utt['utterance'], item['utterance']])
      else:
        # print last utterance and record the new utterance
        if last_utt:
          fsegment.write("%s %s %.2f %.2f\n" % (last_utt['utt'], last_utt['key'], last_utt['start'], last_utt['end']))
          ftext.write("%s %s\n" % (last_utt['utt'], last_utt['utterance']))
          futt2spk.write("%s %s\n" % (last_utt['utt'], last_utt['spk']))
          futt2chn.write("%s %s\n" % (last_utt['utt'], last_utt['key']))
        last_utt = {'utt': utt,
                    'key': key,
                    'spk': spk,
                    'start': start_time,
                    'end': end_time,
                    'utterance': item['utterance']
                    }
    #end if key in chn_no_concat

    last_time = end_time
    last_dur = end_time - start_time

  if not key in chn_no_concat and last_utt:
    fsegment.write("%s %s %.2f %.2f\n" % (last_utt['utt'], last_utt['key'], last_utt['start'], last_utt['end']))
    ftext.write("%s %s\n" % (last_utt['utt'], last_utt['utterance']))
    futt2spk.write("%s %s\n" % (last_utt['utt'], last_utt['spk']))
    futt2chn.write("%s %s\n" % (last_utt['utt'], last_utt['key']))

utt2uttid.close()

fsegment.close()
ftext.close()
futtadd.close()
futt2spk.close()
futt2chn.close()
fwrong.close()
fmeta.close()
futt2time.close()

print "%d recordings processed, %d no transcripts" % (count_total_recording, count_notrans)
print "%d utterances prepared in total. %d utterance with wrong time" % (count_total_utt, count_wrong_time)
