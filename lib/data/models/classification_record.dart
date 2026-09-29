class ClassificationRecord {
  const ClassificationRecord({
    this.id,
    required this.slot,
    required this.tag,
    required this.confidence,
    required this.timestamp,
  });

  final int? id;
  final String slot;
  final String tag;
  final double confidence;
  final DateTime timestamp;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'slot': slot,
      'tag': tag,
      'confidence': confidence,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory ClassificationRecord.fromMap(Map<String, dynamic> map) {
    return ClassificationRecord(
      id: map['id'] as int?,
      slot: map['slot'] as String,
      tag: map['tag'] as String,
      confidence: map['confidence'] as double,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    );
  }
}