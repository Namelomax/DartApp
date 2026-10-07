import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_3/main.dart';
import 'package:flutter_application_3/screens/gallery_screen.dart';
import 'package:flutter_application_3/storage/storage_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../server/bin/server.dart';

class FakeBackend implements StorageBackend {
  final List<CloudItem> items;
  final deleted = <String>[];
  FakeBackend(this.items);

  @override
  Future<void> ping() async {}

  @override
  Future<List<CloudItem>> list() async => [...items];

  @override
  Future<void> upload(File file, String name, {void Function(double)? onProgress}) async {}

  @override
  Future<void> delete(String name) async {
    deleted.add(name);
    items.removeWhere((e) => e.name == name);
  }

  @override
  Uri fileUri(String name) => Uri.parse('http://fake/$name');

  @override
  Map<String, String> get headers => const {};
}

CloudItem item(String name, CloudItemKind kind) =>
    CloudItem(name: name, size: 1024, modified: DateTime(2026, 10, 7, 12), kind: kind);

void main() {
  group('uploadName', () {
    final t = DateTime(2026, 10, 7, 9, 5, 3, 42);
    test('photo and video prefixes', () {
      expect(uploadName('/cache/abc.JPG', t), 'IMG_20261007_090503_042.jpg');
      expect(uploadName('/cache/rec.mp4', t), 'VID_20261007_090503_042.mp4');
      expect(uploadName('/cache/x.mp4', t, 2), 'VID_20261007_090503_042_2.mp4');
    });
    test('accepted by server name check', () {
      expect(isSafeName(uploadName('/cache/noext', t)), isTrue);
    });
  });

  testWidgets('asks for setup when server is not configured', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(CloudApp(backendFactory: (_) => FakeBackend([])));
    await tester.pumpAndSettle();
    expect(find.textContaining('Облако не настроено'), findsOneWidget);
    expect(find.text('Настроить'), findsOneWidget);
  });

  testWidgets('shows files from storage and deletes from viewer', (tester) async {
    SharedPreferences.setMockInitialValues({'server_url': 'http://pc:8080', 'server_token': 't'});
    final backend = FakeBackend([
      item('VID_2.mp4', CloudItemKind.video),
      item('IMG_1.jpg', CloudItemKind.image),
    ]);
    await tester.pumpWidget(CloudApp(backendFactory: (_) => backend));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('IMG_1.jpg'), findsOneWidget);
    expect(find.bySemanticsLabel('VID_2.mp4'), findsOneWidget);
    expect(find.text('Добавить'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('IMG_1.jpg'));
    await tester.pumpAndSettle();
    expect(find.text('IMG_1.jpg'), findsOneWidget);

    await tester.tap(find.byTooltip('Удалить'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();

    expect(backend.deleted, ['IMG_1.jpg']);
    expect(find.text('VID_2.mp4'), findsOneWidget); // перелистнулось на оставшийся файл
  });
}
