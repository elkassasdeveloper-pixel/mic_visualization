class AudioTaggingConfig {
  AudioTaggingConfig._();

  static const String modelAsset = 'assets/models/yamnet.tflite';
  static const String labelsAsset = 'assets/models/yamnet_label_list.txt';

  // TODO: confirm against your actual model
  static const int sampleRate = 16000;
  static const int windowSamples = 15600; // 1 second window
}