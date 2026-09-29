import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_litert/flutter_litert.dart';
import 'package:mic_visualization/core/constants/audio_tagging_config.dart';

class AudioTaggingService {
  AudioTaggingService._(
      this._yamnetInterpreter,
      this._yamnetIsolate,
      this._labels,
      this._scoresIndex,
      this._embeddingsIndex,
      this._embeddingDim,
      this._outputShapes,
      this._customInterpreter,
      this._customIsolate,
      this._customLabels,
      );

  final Interpreter _yamnetInterpreter;
  final IsolateInterpreter _yamnetIsolate;
  final List<String> _labels;
  final int _scoresIndex;
  final int _embeddingsIndex;
  final int _embeddingDim;
  final List<List<int>> _outputShapes; // shape of every output tensor, in order

  final Interpreter? _customInterpreter;
  final IsolateInterpreter? _customIsolate;
  final List<String> _customLabels;

  static final Set<String> _excludedTags = {
    "Hubbub, speech noise, speech babble",
    "Wind noise (microphone)",
    "Traffic noise, roadway noise",
    "Noise",
    "Environmental noise",
    "White noise",
    "Pink noise",
    "Silence",
  };

  static Future<AudioTaggingService> create() async {
    final yamnetInterpreter = await Interpreter.fromAsset(AudioTaggingConfig.modelAsset);

    yamnetInterpreter.resizeInputTensor(0, [AudioTaggingConfig.windowSamples]);
    yamnetInterpreter.allocateTensors();

    // Output shapes for this model depend on the number of internal frames,
    // which TFLite only finalizes after a real invoke — so run once with
    // dummy input to learn the true shapes before doing any real inference.
    final dummyInput = List.filled(AudioTaggingConfig.windowSamples, 0.0);
    final inputTensor = yamnetInterpreter.getInputTensors()[0];
    inputTensor.setTo(dummyInput);
    yamnetInterpreter.invoke();

    final outputTensors = yamnetInterpreter.getOutputTensors();
    final outputShapes = outputTensors.map((t) => t.shape).toList();

    int scoresIndex = -1;
    int embeddingsIndex = -1;
    int embeddingDim = 1024;

    for (var i = 0; i < outputShapes.length; i++) {
      final lastDim = outputShapes[i].isNotEmpty ? outputShapes[i].last : 0;
      if (lastDim == 521) {
        scoresIndex = i;
      } else if (lastDim == 1024) {
        embeddingsIndex = i;
        embeddingDim = lastDim;
      }
    }

    if (scoresIndex == -1) {
      throw StateError('Could not find a [*, 521] scores output in yamnet_official.tflite.');
    }
    if (embeddingsIndex == -1) {
      throw StateError('Could not find a [*, 1024] embeddings output in yamnet_official.tflite.');
    }

    final yamnetIsolate = await IsolateInterpreter.create(address: yamnetInterpreter.address);
    final labels = await _loadLabels(AudioTaggingConfig.labelsAsset);

    Interpreter? customInterpreter;
    IsolateInterpreter? customIsolate;
    List<String> customLabels = [];
    try {
      customInterpreter = await Interpreter.fromAsset(AudioTaggingConfig.animalModelAsset);
      customIsolate = await IsolateInterpreter.create(address: customInterpreter.address);
      customLabels = await _loadLabels(AudioTaggingConfig.animalLabelsAsset);
    } catch (_) {
      // custom model not present — falls back to YAMNet-only behavior
    }

    return AudioTaggingService._(
      yamnetInterpreter,
      yamnetIsolate,
      labels,
      scoresIndex,
      embeddingsIndex,
      embeddingDim,
      outputShapes,
      customInterpreter,
      customIsolate,
      customLabels,
    );
  }

  static Future<List<String>> _loadLabels(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  }

  /// Builds a nested zero-filled buffer matching [shape] exactly, e.g.
  /// [1, 521] -> [[0.0, 0.0, ...]], [N, 1024] -> [[0.0...], [0.0...], ...].
  dynamic _zeroBuffer(List<int> shape) {
    if (shape.length == 1) {
      return List.filled(shape[0], 0.0);
    }
    return List.generate(shape[0], (_) => _zeroBuffer(shape.sublist(1)));
  }

  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final exps = logits.map((x) => exp(x - maxLogit)).toList(); // subtract max for numerical stability
    final sumExps = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sumExps).toList();
  }

  Future<AudioTag?> classify(List<double> samples, {required double minConfidence}) async {
    assert(samples.length == AudioTaggingConfig.windowSamples);

    // Must provide a correctly-shaped buffer for EVERY output tensor —
    // runForMultipleInputs internally iterates all outputs, not just the
    // ones we care about, and throws if any index is missing from the map.
    final outputs = <int, Object>{
      for (var i = 0; i < _outputShapes.length; i++) i: _zeroBuffer(_outputShapes[i]),
    };

    await _yamnetIsolate.runForMultipleInputs([samples], outputs);

    final scoresBuffer = (outputs[_scoresIndex] as List)[0] as List<double>;
    final embeddingsBuffer = outputs[_embeddingsIndex] as List;

    // Average embeddings across the frame dimension into a single (1024,) vector.
    final avgEmbedding = List.filled(_embeddingDim, 0.0);
    var frameCount = 0;
    for (final frameObj in embeddingsBuffer) {
      final frame = frameObj as List<double>;
      final isZeroFrame = frame.every((v) => v == 0.0);
      if (isZeroFrame && frameCount > 0) break;
      for (var d = 0; d < _embeddingDim; d++) {
        avgEmbedding[d] += frame[d];
      }
      frameCount++;
    }
    if (frameCount > 0) {
      for (var d = 0; d < _embeddingDim; d++) {
        avgEmbedding[d] /= frameCount;
      }
    }

    // Try the custom classifier on the averaged embedding first.
    if (_customIsolate != null && frameCount > 0) {
      final customInput = [avgEmbedding];
      final customOutput = [List.filled(_customLabels.length, 0.0)];
      await _customIsolate.run(customInput, customOutput);

      final scores = _softmax(customOutput[0]);
      var bestIndex = 0;
      for (var i = 1; i < scores.length; i++) {
        if (scores[i] > scores[bestIndex]) bestIndex = i;
      }

      final bestLabel = _customLabels[bestIndex];
      if (bestLabel != 'unknown' && scores[bestIndex] > minConfidence) {
        debugPrint("$bestLabel-custom");
        return AudioTag(bestLabel, scores[bestIndex]);
      }
    }

    // Fall back to YAMNet's own 521-class scores.
    var bestIndex = -1;
    for (var i = 0; i < scoresBuffer.length; i++) {
      if (_excludedTags.contains(_labels[i])) continue;
      if (bestIndex == -1 || scoresBuffer[i] > scoresBuffer[bestIndex]) bestIndex = i;
    }
    if (bestIndex == -1) return null;

    final confidence = scoresBuffer[bestIndex];
    if (confidence <= minConfidence) return null;
    return AudioTag(_labels[bestIndex], confidence);
  }

  void dispose() {
    _yamnetIsolate.close();
    _yamnetInterpreter.close();
    _customIsolate?.close();
    _customInterpreter?.close();
  }
}

class AudioTag {
  const AudioTag(this.label, this.confidence);

  final String label;
  final double confidence;
}