// featbin/compute-snr.cc

// Copyright 2017 Hang Su

// See ../../COPYING for clarification regarding multiple authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
// WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
// MERCHANTABLITY OR NON-INFRINGEMENT.
// See the Apache 2 License for the specific language governing permissions and
// limitations under the License.


#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "matrix/kaldi-matrix.h"

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace std;

    const char *usage =
        "Compute SNR based on frame-energy and POV\n"
        "Usage: compute-snr <feats-rspecifier> <pov-rspecifier> <snr-wspecifier>\n"
        " e.g. copmute-snr scp:feats.scp scp:pitch.scp scp:snr.scp\n";

    ParseOptions po(usage);
    kaldi::int32 energy_index = 0;
    po.Register("energy-index", &energy_index, "Index of energy in feats file.");
    kaldi::int32 pov_index= 0;
    po.Register("pov-index", &pov_index, "Index of POV in pitch feats file.");
    BaseFloat threshold = 0.5;
    po.Register("threshold", &threshold, "Threshold for determining voice using POV.");
    BaseFloat snr_min = -10.0;
    po.Register("snr-min", &snr_min, "Value to use if all frames are classified as background");
    BaseFloat snr_max = 20.0;
    po.Register("snr-max", &snr_max, "Value to use if all frames are classified as voice");

    po.Read(argc, argv);

    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    kaldi::int32 num_done = 0, num_err = 0;

    std::string feat_rspecifier = po.GetArg(1);
    std::string pitch_rspecifier = po.GetArg(2);
    std::string snr_wspecifier = po.GetArg(3);

    SequentialBaseFloatMatrixReader feat_reader(feat_rspecifier);
    RandomAccessBaseFloatMatrixReader pov_reader(pitch_rspecifier);
    BaseFloatWriter snr_writer(snr_wspecifier);


    for (; !feat_reader.Done(); feat_reader.Next()) {
      std::string utt = feat_reader.Key();
      if (!pov_reader.HasKey(utt)) {
        KALDI_WARN << "No POV for key " << utt << ", producing no output fo this utterance";
        num_err++;
        continue;
      }
      const Matrix<BaseFloat> &feat_mat = feat_reader.Value();
      const Matrix<BaseFloat> &pov_mat =  pov_reader.Value(utt);
      kaldi::int32 num_voice = 0, num_background = 0;
      BaseFloat acc_log_energy_voice = 0, acc_log_energy_background = 0;
      for (int i = 0; i < feat_mat.NumRows(); i++) {
        if (pov_mat(i, pov_index) > threshold) {
          // this is voice
          acc_log_energy_voice += feat_mat(i, energy_index);
          num_voice += 1;
        } else {
          // this is background
          acc_log_energy_background += feat_mat(i, energy_index);
          num_background += 1;
        }
      }
      if (num_voice == 0 || num_background == 0){
        KALDI_WARN << "Problematic utterances: num_voice = " << num_voice
          << ", num_background = " << num_background;
        if (num_voice == 0) {
          snr_writer.Write(utt, snr_min);
        } else {
          snr_writer.Write(utt, snr_max);
        }
        num_err++;
        continue;
      }
      BaseFloat avg_log_energy_voice = acc_log_energy_voice / num_voice;
      BaseFloat avg_log_energy_background = acc_log_energy_background / num_background;
      //BaseFloat avg_log_energy_voice = LogSub(avg_log_energy_voice, avg_log_energy_background);
      BaseFloat SNR_dB = 10.0 * (avg_log_energy_voice - avg_log_energy_background) / Log(10.0);
      snr_writer.Write(utt, SNR_dB);

      num_done++;
    }
    KALDI_LOG << "Done computing SNR for " << num_done << " utterances, errors on " << num_err;
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}

