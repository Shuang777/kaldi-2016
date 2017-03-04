// nnetbin/nnet-forward.cc

// Copyright 2011-2013  Brno University of Technology (Author: Karel Vesely)

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

#include <limits>

#include "nnet5/nnet-nnet.h"
#include "nnet5/nnet-loss.h"
#include "nnet5/nnet-pdf-prior.h"
#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "base/timer.h"


int main(int argc, char *argv[]) {
  using namespace kaldi;
  using namespace kaldi::nnet5;
  try {
    const char *usage =
      "Perform forward pass through Neural Network.\n"
      "Usage: nnet-forward [options] <nnet5-in> <feature-rspecifier> <feature-wspecifier>\n"
      "e.g.: nnet-forward final.nnet ark:input.ark ark:output.ark\n";

    ParseOptions po(usage);

    PdfPriorOptions prior_opts;
    prior_opts.Register(&po);

    std::string feature_transform;
    po.Register("feature-transform", &feature_transform,
        "Feature transform in front of main network (in nnet format)");

    bool no_softmax = false;
    po.Register("no-softmax", &no_softmax,
        "Removes the last component with Softmax, if found. The pre-softmax "
        "activations are the output of the network. Decoding them leads to "
        "the same lattices as if we had used 'log-posteriors'.");

    bool apply_log = false;
    po.Register("apply-log", &apply_log, "Transform NN output by log()");

    std::string use_gpu="no";
    po.Register("use-gpu", &use_gpu,
        "yes|no|optional, only has effect if compiled with CUDA");
    
    std::string ivector_rspecifier = "";
    po.Register("ivector-rspecifier", &ivector_rspecifier,
        "ivector rspecifier for training with ivector");

    std::string utt2spk_rspecifier = "";
    po.Register("utt2spk-rspecifier", &utt2spk_rspecifier,
        "utt2spk rspecifier for training with ivector");

    int32 frames_per_batch = INT_MAX;
    po.Register("frames-per-batch", &frames_per_batch, "number of frames to process in each batch (default = utterance length)");

    using namespace kaldi;
    using namespace kaldi::nnet5;
    typedef kaldi::int32 int32;

    po.Read(argc, argv);

    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string model_filename = po.GetArg(1),
        feature_rspecifier = po.GetArg(2),
        feature_wspecifier = po.GetArg(3);

    // Select the GPU
#if HAVE_CUDA == 1
    CuDevice::Instantiate().SelectGpuId(use_gpu);
#endif

    Nnet nnet_transf;
    if (feature_transform != "") {
      nnet_transf.Read(feature_transform);
    }
    RandomAccessBaseFloatVectorReaderMapped ivector_reader;
    if (ivector_rspecifier != "" and utt2spk_rspecifier != "") {
      ivector_reader.Open(ivector_rspecifier, utt2spk_rspecifier);
    }

    Nnet nnet;
    nnet.Read(model_filename);
    // optionally remove softmax,
    Component::ComponentType last_comp_type = nnet.GetLastComponent().GetType();
    if (no_softmax) {
      if (last_comp_type == Component::kSoftmax ||
          last_comp_type == Component::kBlockSoftmax) {
        KALDI_LOG << "Removing " << Component::TypeToMarker(last_comp_type)
                  << " from the nnet " << model_filename;
        nnet.RemoveLastComponent();
      } else {
        KALDI_WARN << "Last component 'NOT-REMOVED' by --no-softmax=true, "
          << "the component was " << Component::TypeToMarker(last_comp_type);
      }
    }

    // avoid some bad option combinations,
    if (apply_log && no_softmax) {
      KALDI_ERR << "Cannot use both --apply-log=true --no-softmax=true, "
                << "use only one of the two!";
    }

    // we will subtract log-priors later,
    PdfPrior pdf_prior(prior_opts);

    // disable dropout,
    nnet_transf.SetDropoutRetention(1.0);
    nnet.SetDropoutRetention(1.0);

    kaldi::int64 tot_t = 0;

    SequentialBaseFloatMatrixReader feature_reader(feature_rspecifier);
    BaseFloatMatrixWriter feature_writer(feature_wspecifier);

    CuMatrix<BaseFloat> feats, feats_transf, nnet_out, feats_with_ivec;
    Matrix<BaseFloat> nnet_out_host;
    
    const int32 frames_dependent = (feature_transform != "") ? nnet_transf.FramesDependent() : nnet.FramesDependent();

    Timer time;
    double time_now = 0;
    int32 num_done = 0;

    // main loop,
    for (; !feature_reader.Done(); feature_reader.Next()) {
      // read
      Matrix<BaseFloat> mat = feature_reader.Value();
      std::string utt = feature_reader.Key();

      if (ivector_rspecifier != "" && !ivector_reader.HasKey(utt)) {
        KALDI_ERR << utt << ", missing per-speaker ivector"; 
      }

      KALDI_VLOG(2) << "Processing utterance " << num_done+1
                    << ", " << utt
                    << ", " << mat.NumRows() << "frm";


      if (!KALDI_ISFINITE(mat.Sum())) {  // check there's no nan/inf,
        KALDI_ERR << "NaN or inf found in features for " << utt;
      }

      nnet_out_host.Resize(mat.NumRows(), nnet.OutputDim());
      
      int32 utt_frames_per_batch = frames_per_batch > mat.NumRows() ? mat.NumRows() : frames_per_batch;

      for (int32 i = 0; i < mat.NumRows(); i+= utt_frames_per_batch) {
        int32 frame_start = std::max(i - frames_dependent, 0);
        int32 frame_end = std::min(i + utt_frames_per_batch + frames_dependent, mat.NumRows());
        int32 frames_this_batch_central = (i + utt_frames_per_batch > mat.NumRows()) ? mat.NumRows() - i : utt_frames_per_batch;

        SubMatrix<BaseFloat> sub_mat(mat, frame_start, frame_end - frame_start, 0, mat.NumCols());
      
        // push it to gpu,
        feats = sub_mat;

        // fwd-pass, feature transform,
        nnet_transf.Feedforward(feats, &feats_transf);
        if (!KALDI_ISFINITE(feats_transf.Sum())) {  // check there's no nan/inf,
          KALDI_ERR << "NaN or inf found in transformed-features for " << utt;
        }
          
        if (ivector_rspecifier == "") {
          nnet.Feedforward(feats_transf, &nnet_out);
        } else {
          const CuVector<BaseFloat> ivec(ivector_reader.Value(utt));
          feats_with_ivec.Resize(feats_transf.NumRows(), feats_transf.NumCols() + ivec.Dim());
          CuSubMatrix<BaseFloat> feats_acoustic(feats_with_ivec, 0, feats_with_ivec.NumRows(), 0, feats_transf.NumCols());
          feats_acoustic.CopyFromMat(feats_transf);
          CuSubMatrix<BaseFloat> feats_ivec(feats_with_ivec, 0, feats_with_ivec.NumRows(), feats_transf.NumCols(), ivec.Dim());
          feats_ivec.CopyRowsFromVec(ivec);

          nnet.Feedforward(feats_with_ivec, &nnet_out);
        }
                  
        // fwd-pass, nnet,
        if (!KALDI_ISFINITE(nnet_out.Sum())) {  // check there's no nan/inf,
          KALDI_ERR << "NaN or inf found in nn-output for " << utt;
        }

        // convert posteriors to log-posteriors,
        if (apply_log) {
          if (!(nnet_out.Min() >= 0.0 && nnet_out.Max() <= 1.0)) {
            KALDI_WARN << "Applying 'log()' to data which don't seem to be "
                       << "probabilities," << utt;
          }
          nnet_out.Add(1e-20);  // avoid log(0),
          nnet_out.ApplyLog();
        }

        // subtract log-priors from log-posteriors or pre-softmax,
        if (prior_opts.class_frame_counts != "") {
          pdf_prior.SubtractOnLogpost(&nnet_out);
        }
        
        CuSubMatrix<BaseFloat> nnet_out_central(nnet_out, i - frame_start, frames_this_batch_central, 0, nnet_out.NumCols());
        
        SubMatrix<BaseFloat> sub_nnet_out_host(nnet_out_host, i, frames_this_batch_central, 0, nnet_out_host.NumCols());

        //download from GPU,
        //nnet_out_host = Matrix<BaseFloat>(nnet_out);
        sub_nnet_out_host.CopyFromMat(nnet_out_central);
      }

      // write,
      if (!KALDI_ISFINITE(nnet_out_host.Sum())) {  // check there's no nan/inf,
        KALDI_ERR << "NaN or inf found in final output nn-output for " << utt;
      }
      feature_writer.Write(feature_reader.Key(), nnet_out_host);

      // progress log,
      if (num_done % 100 == 0) {
        time_now = time.Elapsed();
        KALDI_VLOG(1) << "After " << num_done << " utterances: time elapsed = "
                      << time_now/60 << " min; processed " << tot_t/time_now
                      << " frames per second.";
      }
      num_done++;
      tot_t += mat.NumRows();
    }

    // final message,
    KALDI_LOG << "Done " << num_done << " files"
              << " in " << time.Elapsed()/60 << "min,"
              << " (fps " << tot_t/time.Elapsed() << ")";

#if HAVE_CUDA == 1
    if (GetVerboseLevel() >= 1) {
      CuDevice::Instantiate().PrintProfile();
    }
#endif

    if (num_done == 0) return -1;
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
