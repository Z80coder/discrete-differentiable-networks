(* ::Package:: *)

(* 
  TODO:
  - Generalise COUNT to BooleanCountingFunction and specialise to XOR etc. Also consider
    explicit XOR neuron (and possibility of extending idea to create a more efficient Majority neuron)
  - Initialisation policies
  - Work out the policy for the sizes that ensure all possible DNF expressions
    can be learned. Then change parameter to [0, 1] from 0 capacity to full capacity to represent
    all possible DNF expressions. Ignoring NOTs then andSize does not need to be larger than 2^(inputSize - 1)
*)

(* ------------------------------------------------------------------ *)
BeginPackage["neurallogic`"]
(* ------------------------------------------------------------------ *)

Harden::usage = "Hards soft bits.";
Soften::usage = "Soften hard bits.";
HardNeuralNOT::usage = "Neural NOT.";
HardNeuralAND::usage = "Hard neural AND.";
HardNeuralNAND::usage = "Hard neural NAND.";
HardNeuralOR::usage = "Hard neural OR.";
HardNeuralNOR::usage = "Hard neural NOR.";
HardNeuralReshapeLayer::usage = "Port layer.";
NeuralOR::usage = "Neural OR.";
NeuralAND::usage = "Neural AND.";
DifferentiableHardAND::usage = "Differentiable hard AND.";
DifferentiableHardOR::usage = "Differentiable hard OR.";
DifferentiableHardNOT::usage = "Differentiable hard NOT.";
HardClip::usage = "Hard clip.";
LogisticClip::usage = "Logistic clip.";
HardNeuralMajority::usage = "Hard neural majority.";
HardNeuralChain::usage = "Hard neural chain.";
HardNOT::usage = "Hard NOT.";
HardNAND::usage = "Hard NAND.";
HardNOR::usage = "Hard NOR.";
HardAND::usage = "Hard AND.";
HardOR::usage = "Hard OR.";
HardMajority::usage = "Hard majority.";
GetWeights::usage = "Get weights.";
GetNetArrays::usage = "Get net arrays.";
ExtractWeights::usage = "Extract weights.";
HardNetFunction::usage = "Hard net function.";
HardNetTransformWeights::usage = "Hard net transform weights.";
HardNetBooleanExpression::usage = "Hard net boolean expression.";
HardNetBooleanFunction::usage = "Hard net boolean function.";
HardClassificationLoss::usage = "Hard classification loss.";
InitializeNearToZero::usage = "Initialize bias to zero.";
InitializeNearToOne::usage = "Initialize bias to one.";
InitializeBalanced::usage = "Initialize balanced.";
InitializeToConstant::usage = "Initialize to constant.";
HardeningLayer::usage = "Hardening layer.";
HardNeuralCount::usage = "Hard neural count.";
HardNeuralExactlyK::usage = "Hard neural exactly k.";
HardNeuralLTEK::usage = "Hard neural less than or equal to k.";
Require::usage = "Require.";
HardDropoutLayer::usage = "Hard dropout layer.";
RandomUniformSoftBits::usage = "Random soft bit layer.";
RandomNormalSoftBits::usage = "Random soft bit layer.";
RandomBalancedNormalSoftBits::usage = "Random balanced normal soft bit layer.";
SoftBits::usage = "Create some soft bits.";
HardNetClassBits::usage = "Hard net class bits.";
HardNetClassScores::usage = "Hard net class scores.";
HardNetClassProbabilities::usage = "Hard net class probabilities.";
HardNetClassPrediction::usage = "Hard net class prediction.";
HardNetClassify::usage = "Hard net classify.";
HardNetClassifyEvaluation::usage = "Hard net classify evaluation.";

(* ------------------------------------------------------------------ *)

Begin["`Private`"]

(* ------------------------------------------------------------------ *)
(* Boolean utilities *)
(* ------------------------------------------------------------------ *)

Harden[softBit_] := If[softBit > 0.5, True, False]
Harden[softBits_List] := Harden /@ softBits

Soften[hardBit_] := If[hardBit == 1, 1.0, 0.0]
Soften[hardBits_List] := Map[Soften, hardBits]

HardClip[x_] := Clip[x, {0.00000001, 0.9999999}]
HardClip[x_] := Clip[x, {0.0, 1.0}]

LogisticClip[x_] := LogisticSigmoid[4(2 x - 1)]
LogisticClip[x_] := HardClip[x]

(* ------------------------------------------------------------------ *)
(* Initalization policies *)
(* ------------------------------------------------------------------ *)

InitializeToConstant[net_, k_] := NetInitialize[net, All,
  Method -> {
    "Random", 
    "Weights" -> UniformDistribution[{k, k}],
    "Biases" -> UniformDistribution[{k, k}]
  }
]

InitializeBalanced[net_] := NetInitialize[net, All,
  Method -> {
    "Random", 
    "Weights" -> UniformDistribution[{0.4, 0.6}],
    "Biases" -> UniformDistribution[{0.4, 0.6}]
  }
]

InitializeNearToZero[net_] := NetInitialize[net, All,
  Method -> {
    "Random", 
    "Weights" -> CensoredDistribution[{0.001, 0.999}, NormalDistribution[-1, 1]],
    "Biases" -> CensoredDistribution[{0.001, 0.999}, NormalDistribution[-1, 1]]
  }
]

InitializeNearToOne[net_] := NetInitialize[net, All,
  Method -> 
  {
    "Random", 
    "Weights" -> CensoredDistribution[{0.001, 0.999}, NormalDistribution[1, 1]],
    "Biases" -> CensoredDistribution[{0.001, 0.999}, NormalDistribution[1, 1]]
  }
]

(* ------------------------------------------------------------------ *)
(* Learnable soft-bit deterministic variables *)
(* ------------------------------------------------------------------ *)

SoftBits[size_] := NetGraph[
  <|
    "Weights" -> NetArrayLayer["Output" -> size],
    (*"WeightsClip" -> ElementwiseLayer[HardClip]*)
    "WeightsClip" -> HardeningLayer[]
  |>,
  {
    "Weights" -> "WeightsClip"
  }
]

BalancedSoftBits[size_] := InitializeBalanced[SoftBits[size]]
NearZeroSoftBits[size_] := InitializeNearToZero[SoftBits[size]]

(* ------------------------------------------------------------------ *)
(* Learnable soft-bit random variables *)
(* ------------------------------------------------------------------ *)

RandomUniformSoftBits[aWeights_List, bWeights_List] := NetGraph[
  <|
    "A" -> NetArrayLayer["Array" -> aWeights, "Output" -> Length[aWeights]],
    "B" -> NetArrayLayer["Array" -> aWeights, "Output" -> Length[aWeights]],
    "ClipA" -> ElementwiseLayer[Clip[#, {0, 1}] &],
    "ClipB" -> ElementwiseLayer[Clip[#, {0, 1}] &],
    "Distribution" -> RandomArrayLayer[UniformDistribution[{0, 1}], "Output" -> Length[aWeights]],
    "Variates" -> FunctionLayer[#A + (#B - #A) #Random &]
  |>,
  {
    "Distribution" -> NetPort["Variates", "Random"],
    "A" -> "ClipA",
    "B" -> "ClipB",
    "ClipA" -> NetPort["Variates", "A"],
    "ClipB" -> NetPort["Variates", "B"]
  }
]

RandomUniformSoftBits[size_] := RandomUniformSoftBits[Table[RandomReal[{0.0, 1.0}], size], Table[RandomReal[{0.0, 1.0}, size]]]

RandomNormalSoftBits[muWeights_List, sigmaWeights_List] := NetGraph[
  <|
    "Mu" -> NetArrayLayer["Array" -> muWeights, "Output" -> Length[muWeights]],
    "Sigma" -> NetArrayLayer["Array" -> sigmaWeights, "Output" -> Length[muWeights]],
    "Distribution" -> RandomArrayLayer[NormalDistribution[0, 1], "Output" -> Length[muWeights]],
    "Variates" -> FunctionLayer[#Mu + #Sigma * #Random &],
    "ClipVariates" -> ElementwiseLayer[Clip[#, {0, 1}] &]
  |>,
  {
    "Distribution" -> NetPort["Variates", "Random"],
    "Mu" -> NetPort["Variates", "Mu"],
    "Sigma" -> NetPort["Variates", "Sigma"],
    "Variates" -> "ClipVariates"
  }
]

RandomNormalSoftBits[size_] := RandomNormalSoftBits[Table[RandomReal[{0, 0.5}], size], Table[RandomReal[{0, 0.1}], size]]
RandomBalancedNormalSoftBits[size_] := RandomNormalSoftBits[Table[RandomReal[{0, 1}], size], Table[RandomReal[{0, 0.1}], size]]

(* ------------------------------------------------------------------ *)
(* EXPERIMENTAL *)
(* HardMinAll, HardMaxAll *)
(* ------------------------------------------------------------------ *)

HardMinAll[] := NetGraph[
  <|
    "Min" -> AggregationLayer[Min],
    "Mean" -> AggregationLayer[Mean],
    "Filter" -> FunctionLayer[
      If[#Min > 1/2,
        #Min + (((#Min - 1/2) #Mean) (1 - #Min))^2,
        #Min + ((1/2 - #Min) #Mean)^2
      ] &
    ]
  |>,
  {
    "Min" -> NetPort["Filter", "Min"],
    "Mean" -> NetPort["Filter", "Mean"]
  }
]

(* ------------------------------------------------------------------ *)
(* Hard NOT *)
(* ------------------------------------------------------------------ *)

(*
  w = 0 => NOT is fully active
  w = 1 => NOT is fully inactive
  Hence, corresponding hard logic is: (b && w) || (! b && ! w)
    or equivalently ! (b \[Xor] w)
*)
DifferentiableHardNOT[input_, weights_] := 1 - weights + input (2 weights - 1)

HardNOT[{input_List, weights_List}] := 
  {
    (* Output *)
    Not /@ Thread[Xor[input, First[weights]]],
    (* Consume weights *)
    Drop[weights, 1]
  }

HardNeuralNOT[inputSize_, weights_Function:BalancedSoftBits] := {
  NetGraph[
    <|
      "Weights" -> weights[inputSize],
      "Not" -> ThreadingLayer[DifferentiableHardNOT[#Input, #Weights] &, 1](*,
      "OutputClip" -> ElementwiseLayer[LogisticClip]*)
    |>,
    {
      "Weights" -> NetPort["Not", "Weights"](*,
      "Not" -> "OutputClip"*)
    } 
  ],
  HardNOT
}

(* ------------------------------------------------------------------ *)
(* Hard AND *)
(* ------------------------------------------------------------------ *)

(*
  w = 0 => AND is fully inactive
  w = 1 => AND is fully active
  Hence, corresponding hard logic is: b || !w
*)
DifferentiableHardAND[b_, w_] := 
  If[w > 1/2,
    If[b > 1/2,
      b,
      (2 w - 1) b + 1 - w
    ], (*else w<=1/2*)
    If[b > 1/2,
      - 2 w (1 - b) + 1,
      1 - w
    ]
  ]

DifferentiableHardAND[b_, w_] := Max[b, 1 - w]

HardAND[layerSize_] := Function[{inputs},
  Block[{input, weights, layerWeights, reshapedWeights, notWeights},
    {input, weights} = inputs;
    {
      (* Output *)
      layerWeights = First[weights];
      reshapedWeights = Partition[layerWeights, Length[layerWeights] / layerSize];
      notWeights = (Not /@ #) & /@ reshapedWeights;
      MapApply[And, Map[Thread[Or[input, #]] &, notWeights]],
      (* Consume weights *)
      Drop[weights, 1]
    }
  ]
]

HardNeuralAND[inputSize_, layerSize_, weights_Function:NearZeroSoftBits] := {
  NetGraph[
    <|
      "Weights" -> weights[layerSize * inputSize],
      "Reshape" -> ReshapeLayer[{layerSize, inputSize}],
      "HardInclude" -> ThreadingLayer[DifferentiableHardAND[#Input, #Weights] &, 1, "Output" -> {layerSize, inputSize}],
      "And" -> AggregationLayer[Min](*,
      "OutputClip" -> ElementwiseLayer[LogisticClip]*)
    |>,
    {
      "Weights" -> "Reshape",
      "Reshape" -> NetPort["HardInclude", "Weights"],
      "HardInclude" -> "And"(*,
      "And" -> "OutputClip"*)
    }
  ],
  HardAND[layerSize]
}

(* ------------------------------------------------------------------ *)
(* Hard NAND *)
(* ------------------------------------------------------------------ *)

HardNAND[layerSize_] := Function[{inputs},
  HardNOT[HardAND[layerSize][inputs]]
]

HardNeuralNAND[inputSize_, layerSize_, andWeights_Function:NearZeroSoftBits, notWeights_Function:BalancedSoftBits] := {
  NetChain[
    {
      First[HardNeuralAND[inputSize, layerSize, andWeights[#]&]],
      First[HardNeuralNOT[layerSize, notWeights[#]&]]
    }
  ],
  HardNAND[layerSize]
}

(* ------------------------------------------------------------------ *)
(* Hard OR *)
(* ------------------------------------------------------------------ *)

(*
  w = 0 => OR is fully inactive
  w = 1 => OR is fully active
  Hence, corresponding hard logic is: b && w
*)
DifferentiableHardOR[b_, w_] := 1 - DifferentiableHardAND[1-b, w]

HardOR[layerSize_] := Function[{inputs},
  Block[{input, weights, layerWeights, reshapedWeights},
    {input, weights} = inputs;
    {
      (* Output *)
      layerWeights = First[weights];
      reshapedWeights = Partition[layerWeights, Length[layerWeights] / layerSize];
      MapApply[Or, Map[Thread[And[input, #]] &, reshapedWeights]],
      (* Consume weights *)
      Drop[weights, 1]
    }
  ]
]

HardNeuralOR[inputSize_, layerSize_, weights_Function:BalancedSoftBits] := {
  NetGraph[
    <|
      "Weights" -> weights[layerSize * inputSize],
      "Reshape" -> ReshapeLayer[{layerSize, inputSize}],
      "HardInclude" -> ThreadingLayer[DifferentiableHardOR[#Input, #Weights] &, 1, "Output" -> {layerSize, inputSize}],
      "Or" -> AggregationLayer[Max](*,
      "OutputClip" -> ElementwiseLayer[LogisticClip]*)
    |>,
    {
      "Weights" -> "Reshape",
      "Reshape" -> NetPort["HardInclude", "Weights"],
      "HardInclude" -> "Or"(*,
      "Or" -> "OutputClip"*)
    }
  ],
  HardOR[layerSize]
}

(* ------------------------------------------------------------------ *)
(* Hard NOR *)
(* ------------------------------------------------------------------ *)

HardNOR[layerSize_] := Function[{inputs},
  HardNOT[HardOR[layerSize][inputs]]
]

HardNeuralNOR[inputSize_, layerSize_, orWeights_Function:NearZeroSoftBits, notWeights_Function:BalancedSoftBits] := {
  NetChain[
    {
      First[HardNeuralOR[inputSize, layerSize, orWeights[#]&]],
      First[HardNeuralNOT[layerSize, notWeights[#]&]]
    }
  ],
  HardNOR[layerSize]
}

(* ------------------------------------------------------------------ *)
(* Hard MAJORITY *)
(* ------------------------------------------------------------------ *)

HardMajority[layerSize_] := Function[{inputs},
  Block[{input, weights, layerWeights, reshapedWeights},
    {input, weights} = inputs;
    {
      (* Output *)
      layerWeights = First[weights];
      reshapedWeights = Partition[layerWeights, Length[layerWeights] / layerSize];
      Map[Majority @@ First[HardNOT[{input, #}]] &, reshapedWeights],
      (* Consume weights *)
      Drop[weights, 1]
    }
  ]
]

(* 
  Currently using sort (probably compiles to QuickSort)
    - average O(n log n)
    - worst-case O(n^2)
  Replace with Floyd-Rivest algorithm:
    - average n + \min(k, n - k) + O(\sqrt{n \log n}) comparisons with probability at least 1 - 2n^{-1/2}
    - worst-case O(n^2)
    - See https://danlark.org/2020/11/11/miniselect-practical-and-generic-selection-algorithms/
*)
(* TODO: remove NOT from basic Majority *)
HardNeuralMajority[inputSize_, layerSize_, weights_Function:BalancedSoftBits] := {
  With[{medianIndex = Ceiling[(inputSize + 1)/2]},
    NetGraph[
      <|
        "Weights" -> weights[layerSize * inputSize],
        "Reshape" -> ReshapeLayer[{layerSize, inputSize}],
        "HardInclude" -> ThreadingLayer[DifferentiableHardNOT[#Input, #Weights] &, 1, "Output" -> {layerSize, inputSize}],
        "Sort" -> FunctionLayer[Sort /@ # &],
        "Medians" -> PartLayer[{All, medianIndex}](*,
        "OutputClip" -> ElementwiseLayer[LogisticClip]*)
      |>,
      {
        "Weights" -> "Reshape",
        "Reshape" -> NetPort["HardInclude", "Weights"],
        "HardInclude" -> "Sort",
        "Sort" -> "Medians"(*,
        "Medians" -> "OutputClip"*)
      }
    ]
  ],
  HardMajority[layerSize]
}

(* ------------------------------------------------------------------ *)
(* Hard COUNT *)
(* Experimental *)
(* ------------------------------------------------------------------ *)

(* TODO: Simplify with Ordering layer *)
HardNeuralCount[numArrays_, arraySize_] := {
  NetGraph[
    <|
      "Sort" -> FunctionLayer[
        Sort /@ # &
      ],
      "DropLast" -> FunctionLayer[
        Part[#, 1 ;; arraySize - 1] & /@ # &
      ],
      "PadFalse" -> FunctionLayer[
        ArrayPad[#, {{1, 0}}] & /@ # &,
        "Output" -> {numArrays, arraySize}
      ],
      "CountBooleans" -> FunctionLayer[
        (* !a && b *)
        MapThread[Min[DifferentiableHardNOT[#1, 0], #2] &, {#Input2, #Input1}, 2] &
      ](*,
      "OutputClip" -> ElementwiseLayer[LogisticClip]*)
    |>,
    {
      "Sort" -> NetPort["CountBooleans", "Input1"],
      "Sort" -> "DropLast",
      "DropLast" -> "PadFalse",
      "PadFalse" -> NetPort["CountBooleans", "Input2"](*,
      "CountBooleans" -> "OutputClip"*)
    }
  ],
  (* TODO: implement this *)
  HardCount
}

HardNeuralExactlyK[numArrays_, arraySize_, k_] := {
  NetGraph[
    <|
      "Count" -> HardNeuralCount[numArrays, arraySize][[1]],
      "SelectK" -> FunctionLayer[
        Part[#, arraySize - k + 1] & /@ # &
      ]
    |>,
    {
      "Count" -> "SelectK"
    }
  ],
  (* TODO: implement this *)
  HardExactlyK
}

HardNeuralLTEK[numArrays_, arraySize_, k_] := {
  NetGraph[
    <|
      "Count" -> HardNeuralCount[numArrays, arraySize][[1]],
      "CountsLTEK" -> FunctionLayer[
        Part[#, arraySize - k + 1 ;; arraySize] & /@ # &
      ],
      "LTEK" -> AggregationLayer[Max]
    |>,
    {
      "Count" -> "CountsLTEK",
      "CountsLTEK" -> "LTEK"
    }
  ],
  (* TODO: implement this *)
  LTEK
}

Require[requirement_] := {
  NetGraph[
    <|
      "Requirement" -> requirement,
      "Require" -> ThreadingLayer[
        Min[#K, #Input] &,
        2
      ]
    |>,
    {
      "Requirement" -> NetPort["Require", "K"]
    }
  ],
  (* TODO: implement this *)
  Require
}

(* ------------------------------------------------------------------ *)
(* Hard Dropout layer *)
(* ------------------------------------------------------------------ *)

HardDropout[{input_List, weights_List}] := {input, weights}

HardDropoutLayer[p_] := {
  NetGraph[
    <|
      "Dropout" -> DropoutLayer[p, "OutputPorts" -> "BinaryMask"],
      "Mask" -> FunctionLayer[#BinaryMask #Input &]
    |>,
    {
      NetPort["Input"] -> NetPort["Dropout", "Input"],
      NetPort["Input"] -> NetPort["Mask", "Input"],
      NetPort["Dropout", "BinaryMask"] -> NetPort["Mask", "BinaryMask"]
    }
  ],
  HardDropout
}

(* ------------------------------------------------------------------ *)
(* Hard reshape layer *)
(* ------------------------------------------------------------------ *)

HardReshapeLayer[numPorts_] := Function[{inputs},
  Block[{input, weights},
    {input, weights} = inputs;
    {
      Partition[input, Length[input] / numPorts], 
      weights
    }
  ]
]

HardNeuralReshapeLayer[inputSize_, numPorts_] := {
  ReshapeLayer[{numPorts, inputSize / numPorts}],
  HardReshapeLayer[numPorts]
}

(* ------------------------------------------------------------------ *)
(* Hard neural chain *)
(* ------------------------------------------------------------------ *)

HardNeuralChain[layers_List] := Module[{chain = Transpose[layers]},
  With[
    {
      softChain = First[chain],
      hardChain = Last[chain]
    },
    {
      NetChain[softChain],
      RightComposition @@ hardChain
    }
  ]
]

(* ------------------------------------------------------------------ *)
(* Hardening layer *)
(* ------------------------------------------------------------------ *)

HardeningForward[] := Function[
  {Typed[input, TypeSpecifier["PackedArray"]["MachineReal", 2]]},
(* 
  If[# > 0.5, 1.0, 0.0] is less numerically stable and allows
  soft weights to cluster around the 0.5 hard decision
  boundary. If[# > 0.5, 0.51, 0.49] is more numerically
  stable and forces soft weights away from the hard decision
  boundary, but prevents the net from getting correct feedback
  (all examples appear to have a permanent ineradicable
  loss).
*)
  If[# > 0.5, 0.99, 0.01] & /@ # & /@ input
]

HardeningForward[] := Function[
  {Typed[input, TypeSpecifier["PackedArray"]["MachineReal", 2]]},
  If[# < 0.4 || # > 0.6, If[# > 0.5, 0.99, 0.01], 0.5] & /@ # & /@ input
]

HardeningForward[] := Function[
  {Typed[input, TypeSpecifier["PackedArray"]["MachineReal", 2]]},
  If[# > 0.5, 1.0, 0.0] & /@ # & /@ input
]

HardeningBackward[] := Function[
  {
    Typed[input, TypeSpecifier["PackedArray"]["MachineReal", 2]],
    Typed[outgrad, TypeSpecifier["PackedArray"]["MachineReal", 2]]
  },
  (* Straight-through estimator *)
  outgrad
]

HardeningLayer[] := CompiledLayer[HardeningForward[], HardeningBackward[]]

(* ------------------------------------------------------------------ *)
(* Hard classification loss *)
(* ------------------------------------------------------------------ *)

(*
  TODO: CrossEntropy seems better but need to do a full
  experimental comparison.
*)
HardClassificationLoss[] := NetGraph[
  <|
    (*"Harden" -> HardeningLayer[],*)
    "Mean" -> AggregationLayer[Mean, 2],
    "Error" -> MeanSquaredLossLayer[]
  |>,
  {
    (*"Harden" -> "Mean",*)
    "Mean" -> NetPort["Error", "Input"]
  } 
]

HardClassificationLoss[] := NetGraph[
  <|
    (*"Harden" -> HardeningLayer[],*)
    "SoftProbs" -> AggregationLayer[Total, 2],
    "SoftmaxLayer" -> SoftmaxLayer[],
    "Error" -> CrossEntropyLossLayer["Probabilities"]
  |>,
  {
    (*"Harden" -> "SoftProbs",*)
    "SoftProbs" -> "SoftmaxLayer",
    "SoftmaxLayer" -> NetPort["Error", "Input"]
  } 
]

(* ------------------------------------------------------------------ *)
(* Network hardening *)
(* ------------------------------------------------------------------ *)

(* TODO: support non-deterministic weights *)
GetNetArrays[net_] := Select[Normal[NetFlatten[net]], MatchQ[#, _NetArrayLayer] &]

GetWeights[net_] := NetExtract[#, "Arrays"]["Array"] & /@ Values[GetNetArrays[net]]
 
ExtractWeights[net_] := Normal[GetWeights[net]]

HardNetFunction[hardNet_, trainedSoftNet_] := Module[{softWeights},
  softWeights = ExtractWeights[trainedSoftNet];
  With[{hardWeights = Harden[softWeights]},
    Function[{input},
      First[hardNet[{input, hardWeights}]]
    ]
  ]
]

(* TODO: remove need for client to understand weights are 2-layered *)
HardNetTransformWeights[net_, f_Function] := Module[
  {
    arrayNames = Keys[GetNetArrays[net]],
    transformedWeights = f /@ ExtractWeights[net], 
    transformedArrays
  },
  transformedArrays = MapIndexed[
    arrayNames[[#2[[1]]]] -> NetArrayLayer["Array" -> #1, "Output" -> Length[#1]] &,
    transformedWeights
  ];
  NetReplacePart[NetFlatten[net], transformedArrays]
]

HardNetBooleanExpression[hardNetFunction_Function, inputSize_] := Module[
  {
    inputs = Table[Symbol["b" <> ToString[i]], {i, inputSize}]
  },
  hardNetFunction[inputs]
]

HardNetBooleanFunction[hardNetBooleanExpression_, inputSize_] := Block[
  {
    signature = Typed[Symbol["input"], TypeSpecifier["NumericArray"]["MachineInteger", 1]],
    replacements = Quiet[Table[
      Symbol["b" <> ToString[i]] -> With[{b = Symbol["input"][[i]]}, 
          If[b == 1, True, False]
        ],
      {i, inputSize}]
    ],
    indexExpression
  },
  indexExpression = hardNetBooleanExpression //. replacements;
  Function[Evaluate[signature], Evaluate[indexExpression]]
]

(* ------------------------------------------------------------------ *)
(* Classifier querying and evaluation *)
(* ------------------------------------------------------------------ *)

HardNetClassBits[hardNet_Function, featureLayer_NetGraph, data_] := Normal[hardNet[Harden[Normal[featureLayer[#]]]] & /@ data]

HardNetClassScores[classBits_] := (Total /@ Boole[#]) & /@ classBits

HardNetClassProbabilities[classScores_] := N[Exp[#]/Total[Exp[#]]] & /@ classScores

HardNetClassPrediction[classProbabilities_, decoder_NetDecoder] := First[decoder @ classProbabilities]

HardNetClassify[hardNet_Function, featureLayer_NetGraph, decoder_NetDecoder, data_, targetName_String] := 
  ResourceFunction[ResourceObject[
      <|
        "Name" -> "DynamicMap",
        "ShortName" -> "DynamicMap", 
        "UUID" -> "962b5001-b624-4bc4-9b1e-401e550f4f2b", 
        "ResourceType" -> "Function",
        "Version" -> "4.0.0", 
        "Description" -> "Map functions over lists while showing dynamic progress", 
        "RepositoryLocation" -> URL["https://www.wolframcloud.com/objects/resourcesystem/api/1.0"], 
        "SymbolName" -> "FunctionRepository`$f51668a7ac6041a9b46390842a7243d8`DynamicMap", 
        "FunctionLocation" -> CloudObject["https://www.wolframcloud.com/obj/9d55b90e-e3c6-4d27-bdcf-8c3ebb4fe19a"]
      |>, 
      ResourceSystemBase -> Automatic
  ]][
    <|
      "Prediction" -> HardNetClassPrediction[
          HardNetClassProbabilities[
            HardNetClassScores[
              HardNetClassBits[hardNet, featureLayer, {KeyDrop[{targetName}] @ #}]
          ]
        ],
        decoder
      ],
      "Target" -> #[targetName]
    |> &,
    data
  ]

HardNetClassifyEvaluation[hardNetClassify_] := Module[
  {results = Counts[hardNetClassify], correctResults, totalCorrect, totalResults, accuracy},
  correctResults = KeySelect[results, Length[DeleteDuplicates[Values[#]]] == 1 &];
  totalCorrect = Total[correctResults];
  totalResults = Total[results];
  accuracy = N[totalCorrect / totalResults];
  <|"Accuracy" -> accuracy, "Results" -> Reverse[Sort[results]]|>
]

(* ------------------------------------------------------------------ *)
(* Approximate differentiable AND, OR *)
(* ------------------------------------------------------------------ *)

NeuralAND[inputSize_, layerSize_] := NetGraph[
  <|
    "Weights" -> NetArrayLayer["Output" -> {layerSize, inputSize}],
    "WeightsClip" -> ElementwiseLayer[HardClip],
    "SoftInclude" -> ThreadingLayer[1 - #Weights (1 - #Input) &, 1, "Output" -> {layerSize, inputSize}],
    (* LogSumExp trick *)
    "Log" -> ElementwiseLayer[Log],
    "Sum" -> AggregationLayer[Total],
    "Exp" -> ElementwiseLayer[Exp],
    "OutputClip" -> ElementwiseLayer[HardClip] 
  |>,
  {
    "Weights" -> "WeightsClip",
    "WeightsClip" -> NetPort["SoftInclude", "Weights"],
    "SoftInclude" -> "Log",
    "Log" -> "Sum",
    "Sum" -> "Exp",
    "Exp" -> "OutputClip"
  }
]

NeuralOR[inputSize_, layerSize_] := NetGraph[
  <|
    "Weights" -> NetArrayLayer["Output" -> {layerSize, inputSize}],
    "WeightsClip" -> ElementwiseLayer[HardClip],
    "SoftInclude" -> ThreadingLayer[1 - #Weights #Input &, 1, "Output" -> {layerSize, inputSize}],
    (* LogSumExp trick *) 
    "Or1" -> ElementwiseLayer[Log],
    "Or2" -> AggregationLayer[Total],
    "Or3" -> ElementwiseLayer[Exp],
    "Or4" -> ElementwiseLayer[1 - # &],
    "OutputClip" -> ElementwiseLayer[HardClip]
  |>,
  {
    "Weights" -> "WeightsClip",
    "WeightsClip" -> NetPort["SoftInclude", "Weights"],
    "SoftInclude" -> "Or1",
    "Or1" -> "Or2",
    "Or2" -> "Or3",
    "Or3" -> "Or4",
    "Or4" -> "OutputClip"
  }
]

End[]

EndPackage[]
