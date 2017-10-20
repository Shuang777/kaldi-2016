#!/usr/bin/python

# Copyright 2014  Brno University of Technology (author: Karel Vesely)

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

# Generated Nnet prototype, to be initialized by 'nnet-initialize'.

import math, random, sys
from optparse import OptionParser

###
### Parse options
###
usage="%prog [options] <feat-dim> >nnet-proto-file"
parser = OptionParser(usage)

parser.add_option('--no-proto-head', dest='with_proto_head', 
                   help='Do not put <NnetProto> head-tag in the prototype [default: %default]', 
                   default=True, action='store_false');
parser.add_option('--no-softmax', dest='with_softmax', 
                   help='Do not put <SoftMax> in the prototype [default: %default]', 
                   default=True, action='store_false');
parser.add_option('--top-linear', dest='top_linear', 
                   help='Use Linear instead of Affine for last hidden layer [default: %default]', 
                   default=False, action='store_true');
parser.add_option('--activation-type', dest='activation_type', 
                   help='Select type of activation function : (<Sigmoid>|<Tanh>) [default: %default]', 
                   default='<Sigmoid>', type='string');
parser.add_option('--hid-bias-mean', dest='hid_bias_mean', 
                   help='Set bias for hidden activations [default: %default]', 
                   default=-2.0, type='float');
parser.add_option('--hid-bias-range', dest='hid_bias_range', 
                   help='Set bias range for hidden activations (+/- 1/2 range around mean) [default: %default]', 
                   default=4.0, type='float');
parser.add_option('--param-stddev-factor', dest='param_stddev_factor', 
                   help='Factor to rescale Normal distriburtion for initalizing weight matrices [default: %default]', 
                   default=0.1, type='float');
parser.add_option('--bottleneck-dim', dest='bottleneck_dim', 
                   help='Make bottleneck network with desired bn-dim (0 = no bottleneck) [default: %default]',
                   default=0, type='int');
parser.add_option('--no-glorot-scaled-stddev', dest='with_glorot', help='Generate normalized weights according to X.Glorot paper, but mapping U->N with same variance (factor sqrt(x/(dim_in+dim_out)))', action='store_false', default=True)
parser.add_option('--no-smaller-input-weights', dest='smaller_input_weights', 
                   help='Disable 1/12 reduction of stddef in input layer [default: %default]',
                   action='store_false', default=True);
parser.add_option('--max-norm', dest='max_norm', 
                   help='Max radius of neuron-weights in L2 space (if longer weights get shrinked, not applied to last layer, 0.0 = disable) [default: %default]', 
                   default=0.0, type='float');
parser.add_option('--with-dropout', dest='with_dropout',
                   help='Add <Dropout> after the non-linearity of hidden layer.',
                   action='store_true', default=False);
parser.add_option('--dropout-opts', dest='dropout_opts',
                   help='Extra options for dropout [default: %default]',
                   default='', type='string');


(o,args) = parser.parse_args()
if len(args) != 4 : 
  parser.print_help()
  sys.exit(1)




o.dropout_opts = o.dropout_opts.replace("_"," ") 
(feat_dim, num_leaves, num_hid_layers, num_hid_neurons) = map(int,args);
### End parse options 


# Check
assert(feat_dim > 0)
assert(num_leaves > 0)
assert(num_hid_layers >= 0)
assert(num_hid_neurons > 0)

# Optionaly scale
def Glorot(dim1, dim2):
  if o.with_glorot:
    # 35.0 = magic number, gives ~1.0 in inner layers for hid-dim 1024dim,
    return 35.0 * math.sqrt(2.0/(dim1+dim2)); 
  else:
    return 1.0


###
### Print prototype of the network
###

# No hidden layer while adding bottleneck means:
# - add bottleneck layer + hidden layer + output layer
if num_hid_layers == 0 and o.bottleneck_dim != 0:
  assert(o.bottleneck_dim > 0)
  assert(num_hid_layers == 0)
  if o.with_proto_head : print "<NnetProto>"
  # 25% smaller stddev -> small bottleneck range, 10x smaller learning rate
  print "<LinearTransform> <InputDim> %d <OutputDim> %d <ParamStddev> %f <LearnRateCoef> %f" % \
   (feat_dim, o.bottleneck_dim, \
    (o.param_stddev_factor * Glorot(feat_dim, o.bottleneck_dim) * 0.75 ), 0.1)
  # 25% smaller stddev -> smaller gradient in prev. layer, 10x smaller learning rate for weigts & biases
  print "<AffineTransform> <InputDim> %d <OutputDim> %d <BiasMean> %f <BiasRange> %f <ParamStddev> %f <LearnRateCoef> %f <BiasLearnRateCoef> %f <MaxNorm> %f" % \
   (o.bottleneck_dim, num_hid_neurons, o.hid_bias_mean, o.hid_bias_range, \
    (o.param_stddev_factor * Glorot(o.bottleneck_dim, num_hid_neurons) * 0.75 ), 0.1, 0.1, o.max_norm) 
  print "%s <InputDim> %d <OutputDim> %d" % (o.activation_type, num_hid_neurons, num_hid_neurons) # Non-linearity
  # Last AffineTransform (10x smaller learning rate on bias)
  print "<AffineTransform> <InputDim> %d <OutputDim> %d <BiasMean> %f <BiasRange> %f <ParamStddev> %f <LearnRateCoef> %f <BiasLearnRateCoef> %f" % \
   (num_hid_neurons, num_leaves, 0.0, 0.0, \
    (o.param_stddev_factor * Glorot(num_hid_neurons, num_leaves)), 1.0, 0.1)
  # Optionaly append softmax
  if o.with_softmax:
    print "<Softmax> <InputDim> %d <OutputDim> %d" % (num_leaves, num_leaves)
  print "</NnetProto>"
  # We are done!
  sys.exit(0)

# Add only last layer (logistic regression)
if num_hid_layers == 0:
  if o.with_proto_head : print "<NnetProto>" 
  if o.top_linear:
    print "<LinearTransform> <InputDim> %d <OutputDim> %d <ParamStddev> %f <LearnRateCoef> %f" % \
        (num_hid_neurons, num_leaves, \
        (o.param_stddev_factor * Glorot(num_hid_neurons, num_leaves)), 0.1)
  else:
    print "<AffineTransform> <InputDim> %d <OutputDim> %d <BiasMean> %f <BiasRange> %f <ParamStddev> %f" % \
        (feat_dim, num_leaves, 0.0, 0.0, (o.param_stddev_factor * Glorot(feat_dim, num_leaves)))
  if o.with_softmax:
    print "<Softmax> <InputDim> %d <OutputDim> %d" % (num_leaves, num_leaves)
  print "</NnetProto>"
  # We are done!
  sys.exit(0)

# Assuming we have >0 hidden layers
assert(num_hid_layers > 0)

# Begin the prototype
if o.with_proto_head : print "<NnetProto>" 

# First AffineTranform
if o.smaller_input_weights:
  param_std_dev_scale = 1.0
else:
  param_std_dev_scale = math.sqrt(1.0/12.0)

print "<AffineTransform> <InputDim> %d <OutputDim> %d <BiasMean> %f <BiasRange> %f <ParamStddev> %f <MaxNorm> %f" % \
      (feat_dim, num_hid_neurons, o.hid_bias_mean, o.hid_bias_range, \
       (o.param_stddev_factor * Glorot(feat_dim, num_hid_neurons) * \
        param_std_dev_scale), o.max_norm) 
      # stddev(U[0,1]) = sqrt(1/12); reducing stddev of weights, 
      # the dynamic range of input data is larger than of a Sigmoid.
print "%s <InputDim> %d <OutputDim> %d" % (o.activation_type, num_hid_neurons, num_hid_neurons)
if o.with_dropout:
  print "<Dropout> <InputDim> %d <OutputDim> %d %s" % (num_hid_neurons, num_hid_neurons, o.dropout_opts)

# Internal AffineTransforms
for i in range(num_hid_layers-1):
  print "<AffineTransform> <InputDim> %d <OutputDim> %d <BiasMean> %f <BiasRange> %f <ParamStddev> %f <MaxNorm> %f" % \
        (num_hid_neurons, num_hid_neurons, o.hid_bias_mean, o.hid_bias_range, \
         (o.param_stddev_factor * Glorot(num_hid_neurons, num_hid_neurons)), o.max_norm)
  print "%s <InputDim> %d <OutputDim> %d" % (o.activation_type, num_hid_neurons, num_hid_neurons)
  if o.with_dropout:
    print "<Dropout> <InputDim> %d <OutputDim> %d %s" % (num_hid_neurons, num_hid_neurons, o.dropout_opts)

# Optionaly add bottleneck
if o.bottleneck_dim != 0:
  assert(o.bottleneck_dim > 0)
  # 25% smaller stddev -> small bottleneck range, 10x smaller learning rate
  print "<LinearTransform> <InputDim> %d <OutputDim> %d <ParamStddev> %f <LearnRateCoef> %f" % \
   (num_hid_neurons, o.bottleneck_dim, \
    (o.param_stddev_factor * Glorot(num_hid_neurons, o.bottleneck_dim) * 0.75 ), 0.1)
  # 25% smaller stddev -> smaller gradient in prev. layer, 10x smaller learning rate for weigts & biases
  print "<AffineTransform> <InputDim> %d <OutputDim> %d <BiasMean> %f <BiasRange> %f <ParamStddev> %f <LearnRateCoef> %f <BiasLearnRateCoef> %f <MaxNorm> %f" % \
   (o.bottleneck_dim, num_hid_neurons, o.hid_bias_mean, o.hid_bias_range, \
    (o.param_stddev_factor * Glorot(o.bottleneck_dim, num_hid_neurons) * 0.75 ), 0.1, 0.1, o.max_norm) 
  print "%s <InputDim> %d <OutputDim> %d" % (o.activation_type, num_hid_neurons, num_hid_neurons)
  if o.with_dropout:
    print "<Dropout> <InputDim> %d <OutputDim> %d %s" % (num_hid_neurons, num_hid_neurons, o.dropout_opts)

if o.top_linear:
  print "<LinearTransform> <InputDim> %d <OutputDim> %d <ParamStddev> %f <LearnRateCoef> %f" % \
        (num_hid_neurons, num_leaves, \
        (o.param_stddev_factor * Glorot(num_hid_neurons, num_leaves)), 0.1)
else:
  # Last AffineTransform (10x smaller learning rate on bias)
  print "<AffineTransform> <InputDim> %d <OutputDim> %d <BiasMean> %f <BiasRange> %f <ParamStddev> %f <LearnRateCoef> %f <BiasLearnRateCoef> %f" % \
        (num_hid_neurons, num_leaves, 0.0, 0.0, \
        (o.param_stddev_factor * Glorot(num_hid_neurons, num_leaves)), 1.0, 0.1)

# Optionaly append softmax
if o.with_softmax:
  print "<Softmax> <InputDim> %d <OutputDim> %d" % (num_leaves, num_leaves)

# End the prototype
print "</NnetProto>"

# We are done!
sys.exit(0)
