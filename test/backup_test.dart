import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mealqueue/domain/backup.dart';
import 'package:mealqueue/domain/database_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late Database db;
  late MealBackup backup;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('meal-queue-backup-');
    db = await databaseFactoryFfi.openDatabase(
      '${dir.path}/data.db',
      options: OpenDatabaseOptions(
        version: AppDatabaseSchema.currentVersion,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => AppDatabaseSchema.createSchema(db),
      ),
    );
    backup = MealBackup(db);
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
    'round trip keeps checked lines and cook history; omits photos',
    () async {
      await db.insert('recipes', {
        'id': 'r',
        'title': 'Soup',
        'servings': 2,
        'steps': 'Cook',
        'photo_path': 'photos/source.jpg',
        'created_at': 1,
        'updated_at': 2,
      });
      await db.insert('planned_meals', {
        'id': 'p',
        'plan_date': '2026-10-30',
        'slot': 'Dinner',
        'kind': 'recipe',
        'recipe_id': 'r',
        'servings': 3,
      });
      await db.insert('shopping_snapshots', {
        'id': 's',
        'created_at': 3,
        'label': 'Week',
      });
      await db.insert('shopping_lines', {
        'id': 'l',
        'snapshot_id': 's',
        'item': 'Eggs',
        'is_checked': 1,
      });
      await db.insert('cook_events', {
        'id': 'c',
        'plan_date': '2026-10-30',
        'slot': 'Dinner',
        'recipe_id': 'r',
        'recipe_title': 'Soup',
        'cooked_at': 4,
      });
      final json = await backup.exportJson();
      expect(json, contains('"photos":"excluded"'));
      expect(json, isNot(contains('photos/source.jpg')));
      await backup.importJson(json);
      expect((await db.query('recipes')).single['photo_path'], isNull);
      expect((await db.query('shopping_lines')).single['is_checked'], 1);
      expect((await db.query('cook_events')).single['recipe_title'], 'Soup');
      expect((await db.query('planned_meals')).single['servings'], 3);
    },
  );

  test('invalid photo path and schema leave existing data intact', () async {
    await db.insert('recipes', {
      'id': 'keep',
      'title': 'Keep',
      'servings': 1,
      'steps': '',
      'created_at': 1,
      'updated_at': 1,
    });
    final json = await backup.exportJson();
    await expectLater(
      backup.importJson(
        json.replaceFirst('"photo_path":null', '"photo_path":"../escape"'),
      ),
      throwsFormatException,
    );
    await expectLater(
      backup.importJson(json.replaceFirst('"version":1', '"version":99')),
      throwsFormatException,
    );
    expect((await db.query('recipes')).single['title'], 'Keep');
  });

  test('constraint failure rolls back replacement', () async {
    await db.insert('recipes', {
      'id': 'keep',
      'title': 'Keep',
      'servings': 1,
      'steps': '',
      'created_at': 1,
      'updated_at': 1,
    });
    final json = await backup.exportJson();
    await expectLater(
      backup.importJson(json.replaceFirst('"servings":1', '"servings":0')),
      throwsA(isA<Exception>()),
    );
    expect((await db.query('recipes')).single['title'], 'Keep');
  });
}
