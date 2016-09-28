// ivector2bin/ivector2-extract.cc

// Copyright 2013  Daniel Povey
//           2016  Hang Su

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
#include "gmm/am-diag-gmm.h"
#include "ivector3/ivector-extractor.h"
#include <algorithm>
#include <map>

void gen_bootstrap_frames(std::map<int32, int32> &selected_frames, int32 num_frames) {
  selected_frames.clear();
  for (int32 i = 0; i < num_frames; i++) {
    int32 frame = rand() % num_frames;
    if (selected_frames.find(frame) == selected_frames.end()) {
      selected_frames[frame] = 1;
    } else {
      selected_frames[frame]++;
    }
  }
}

int main(int argc, char *argv[]) {
  using namespace kaldi;
  using namespace kaldi::ivector3;
  typedef kaldi::int32 int32;
  typedef kaldi::int64 int64;
  try {
    const char *usage =
        "Extract iVectors for utterances, using a trained iVector extractor,\n"
        "and supvectors and Gaussian-level posteriors\n"
        "Usage:  ivector-extract [options] <model-in> <feat-rspecifier>"
        "<posteriors-rspecifier> <ivector-wspecifier>\n"
        "e.g.: \n"
        "  ivector-extract final.ie 'ark:1.feat' 'ark:1.post' ark,t:ivectors.1.ark\n";

    ParseOptions po(usage);
    bool compute_objf = false;
    po.Register("compute-objf", &compute_objf, "If true, compute the objective function");
    int32 seg_parts = 1;
    po.Register("seg-parts", &seg_parts, "Split each utterance into seg_parts parts, for ivector generation");
    int32 select_parts = 1;
    po.Register("select-parts", &select_parts, "Select these parts from segmentated audio");
    int32 bootstrap = 0;
    po.Register("bootstrap", &bootstrap, "Number of times you do bootstrapping");
    int32 srand_seed = 777;
    po.Register("srand-seed", &srand_seed, "Seed of randomization");

    po.Read(argc, argv);
    
    if (po.NumArgs() != 4) {
      po.PrintUsage();
      exit(1);
    }

    std::string ivector_extractor_rxfilename = po.GetArg(1),
        feature_rspecifier = po.GetArg(2),
        posterior_rspecifier = po.GetArg(3),
        ivectors_wspecifier = po.GetArg(4);

    IvectorExtractor extractor;
    {
      bool binary_in;
      Input ki(ivector_extractor_rxfilename, &binary_in);
      extractor.Read(ki.Stream(), binary_in);
    }

    double tot_auxf = 0.0;
    
    SequentialBaseFloatMatrixReader feature_reader(feature_rspecifier);
    RandomAccessPosteriorReader posteriors_reader(posterior_rspecifier);
    DoubleVectorWriter ivector_writer(ivectors_wspecifier);

    Vector<double> ivector(extractor.IvectorDim());

    IvectorExtractorUtteranceStats stats;

    int32 num_done = 0, num_err = 0;
    double this_auxf = 0;
    int32 feat_dim = extractor.FeatDim();
    int32 num_gauss = extractor.NumGauss();
    bool need_2nd_order_stats = false;
    if (compute_objf) 
      need_2nd_order_stats = true;

    if (seg_parts != 1 && bootstrap != 0) {
      KALDI_ERR << "seg_parts != 1 && bootstrap != 0, but we only support one of them at a time";
    }

    for (; !feature_reader.Done(); feature_reader.Next()) {
      std::string key = feature_reader.Key();
      if (!posteriors_reader.HasKey(key)) {
        KALDI_WARN << "No posteriors for utterance " << key;
        num_err++;
        continue;
      }
      const Matrix<BaseFloat> &mat = feature_reader.Value();
      const Posterior &posterior = posteriors_reader.Value(key);

      if (static_cast<int32>(posterior.size()) != mat.NumRows()) {
        KALDI_WARN << "Size mismatch between posterior " << (posterior.size())
                   << " and features " << (mat.NumRows()) << " for utterance "
                   << key;
        num_err++;
        continue;
      }

      double *auxf_ptr = (compute_objf ? &this_auxf : NULL);
      
      if (bootstrap == 0) { // no bootstrap 
        std::vector<bool> selected(seg_parts);
        std::fill(selected.begin() + seg_parts - select_parts, selected.end(), true);

        int32 count = 0;
        do {
          std::string utt = (seg_parts <= 1) ? key: key + "_C" + ConvertIntToString(seg_parts) + ConvertIntToString(select_parts) + "_" + ConvertIntToString(count);

          stats.Reset(num_gauss, feat_dim, need_2nd_order_stats);
          stats.AccStats(mat, posterior, selected);
         
          bool for_scoring = true;
          extractor.GetIvectorDistribution(stats, &ivector, NULL, NULL, auxf_ptr, for_scoring);
          
          tot_auxf += this_auxf;

          ivector_writer.Write(utt, ivector);

          count++;
        } while (std::next_permutation(selected.begin(), selected.end()));

      } else {      // bootstrap
        
        std::map<int32, int32> selected_frames;
        srand(srand_seed);

        for (int32 i = 0; i < bootstrap; i++) {
          std::string utt = key + "_B" + ConvertIntToString(i);
        
          gen_bootstrap_frames(selected_frames, mat.NumRows());

          stats.Reset(num_gauss, feat_dim, need_2nd_order_stats);
          stats.AccStats(mat, posterior, selected_frames);

          bool for_scoring = true;
          extractor.GetIvectorDistribution(stats, &ivector, NULL, NULL, auxf_ptr, for_scoring);

          tot_auxf += this_auxf;

          ivector_writer.Write(utt, ivector);

        }
      }

      num_done++;
    }

    KALDI_LOG << "Done " << num_done << " files.";

    if (compute_objf)
      KALDI_LOG << "Overall average objective-function estimating "
                << "ivector was " << (tot_auxf / num_done) << " per vector "
                << " over " << num_done << " vectors.";

    return (num_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
