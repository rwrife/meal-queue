import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app/adaptive.dart';
import '../domain/backup.dart';
import '../domain/recipe_repository.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({required this.repository, super.key});
  final RecipeRepository repository;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String? message;
  bool busy = false;
  static const jsonType = XTypeGroup(
    label: 'JSON backup',
    extensions: ['json'],
    uniformTypeIdentifiers: ['public.json'],
  );

  Future<void> run(Future<void> Function() task) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await task();
    } catch (error) {
      if (mounted) setState(() => message = 'Backup failed: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() => run(() async {
    // Photos are intentionally omitted, including their paths.
    final json = await MealBackup(widget.repository.db).exportJson();
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/meal-queue-backup.json');
      await file.writeAsString(json, flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } else {
      final location = await getSaveLocation(
        suggestedName: 'meal-queue-backup.json',
        acceptedTypeGroups: [jsonType],
      );
      if (location == null) return;
      await XFile.fromData(
        utf8Bytes(json),
        mimeType: 'application/json',
      ).saveTo(location.path);
    }
    if (mounted) setState(() => message = 'Backup exported. Photos excluded.');
  });

  Future<void> restore() => run(() async {
    final file = await openFile(acceptedTypeGroups: [jsonType]);
    if (file == null) return;
    if (await file.length() > MealBackup.maxBytes) {
      throw const FormatException('Backup exceeds 8 MiB limit');
    }
    final json = await file.readAsString();
    if (!mounted) return;
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (ctx) => AdaptiveDialog(
        title: 'Replace local data?',
        content: const Text(
          'Import replaces recipes, plans, lists, stock and cook history. Export a backup first. Photos are excluded and cannot be restored.',
        ),
        actions: [
          AdaptiveButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(ctx, false),
          ),
          AdaptiveButton(
            label: 'Replace',
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await MealBackup(widget.repository.db).importJson(json);
    await widget.repository.cleanOrphanPhotos();
    if (mounted) setState(() => message = 'Backup restored. Photos excluded.');
  });

  // XFile.fromData avoids writing an arbitrary user-selected path with File.
  static Uint8List utf8Bytes(String text) =>
      Uint8List.fromList(utf8.encode(text));

  @override
  Widget build(BuildContext context) => AdaptiveScaffold(
    title: 'Backup and restore',
    onBack: () => Navigator.pop(context),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'JSON backup includes recipes, plans, shopping lists and checkboxes, stock, and cook history. Photos are excluded. Export before replacing data or uninstalling.',
        ),
        AdaptiveButton(
          label: 'Export JSON (no photos)',
          onPressed: busy ? null : export,
        ),
        AdaptiveButton(
          label: 'Import JSON and replace data',
          onPressed: busy ? null : restore,
        ),
        if (message != null) Text(message!, key: const Key('backup-result')),
      ],
    ),
  );
}
