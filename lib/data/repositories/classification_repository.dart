import 'package:flutter/foundation.dart';
import 'package:mic_visualization/data/local/app_database.dart';
import 'package:mic_visualization/data/models/classification_record.dart';

abstract class ClassificationRepository {
  Future<void> insert(ClassificationRecord record);
  Future<List<ClassificationRecord>> allForSlot(String slot);
  Future<List<ClassificationRecord>> page({
    required int limit,
    required int offset,
    DateTime? from,
    DateTime? to,
    String? slot,
  });
  Future<void> deleteAll();
}

class SqfliteClassificationRepository implements ClassificationRepository {
  @override
  Future<void> insert(ClassificationRecord record) async {
    final db = await AppDatabase.instance.database;
    await db.insert('classifications', record.toMap());
  }

  @override
  Future<List<ClassificationRecord>> allForSlot(String slot) async {
    final db = await AppDatabase.instance.database;
    final maps = await db.query(
      'classifications',
      where: 'slot = ?',
      whereArgs: [slot],
      orderBy: 'timestamp DESC',
    );
    return maps.map(ClassificationRecord.fromMap).toList();
  }

  @override
  Future<List<ClassificationRecord>> page({
    required int limit,
    required int offset,
    DateTime? from,
    DateTime? to,
    String? slot,
  }) async {
    final db = await AppDatabase.instance.database;

    final conditions = <String>[];
    final args = <Object?>[];
    if (from != null) {
      conditions.add('timestamp >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      conditions.add('timestamp <= ?');
      args.add(to.millisecondsSinceEpoch);
    }
    if (slot != null) {
      conditions.add('slot = ?');
      args.add(slot);
    }
    debugPrint('[ClassificationRepo] page() where=${conditions.join(' AND ')} args=$args');
    final maps = await db.query(
      'classifications',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map(ClassificationRecord.fromMap).toList();
  }

  @override
  Future<void> deleteAll() async {
    final db = await AppDatabase.instance.database;
    await db.delete('classifications');
  }
}