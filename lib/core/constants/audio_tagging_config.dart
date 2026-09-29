class AudioTaggingConfig {
  AudioTaggingConfig._();

  static const String modelAsset = 'assets/models/yamnet.tflite';
  static const String labelsAsset = 'assets/models/yamnet_label_list.txt';
  static const String animalModelAsset = 'assets/models/animal_classifier.tflite';
  static const String animalLabelsAsset = 'assets/models/animal_labels.txt';

  // TODO: confirm against your actual model
  static const int sampleRate = 16000;
  static const int windowSamples = 15600; // 1 second window
}