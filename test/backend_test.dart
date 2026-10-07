// Клиент приложения против настоящего сервера (реальная сеть, поэтому отдельно от widget-тестов).
import 'dart:io';

import 'package:flutter_application_3/storage/home_server_backend.dart';
import 'package:flutter_application_3/storage/storage_backend.dart';
import 'package:flutter_test/flutter_test.dart';

import '../server/bin/server.dart';

void main() {
  test('HomeServerBackend works with the real server', () async {
    final dir = await Directory.systemTemp.createTemp('cloud_app_test_');
    final server = CloudServer(storage: dir, token: 'pw');
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    try {
      final backend = HomeServerBackend(serverUrl: 'http://127.0.0.1:${server.port}/', token: 'pw');
      await backend.ping();

      final src = File('${dir.path}${Platform.pathSeparator}..${Platform.pathSeparator}'
          'src_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await src.writeAsBytes(List.filled(200000, 7));
      final progress = <double>[];
      await backend.upload(src, 'IMG_1.jpg', onProgress: progress.add);
      await src.delete();
      expect(progress.last, 1.0);

      final items = await backend.list();
      expect(items.single.name, 'IMG_1.jpg');
      expect(items.single.size, 200000);
      expect(items.single.kind, CloudItemKind.image);

      await backend.delete('IMG_1.jpg');
      expect(await backend.list(), isEmpty);

      final wrong = HomeServerBackend(serverUrl: 'http://127.0.0.1:${server.port}', token: 'x');
      await expectLater(wrong.ping(), throwsA(isA<StorageException>()
          .having((e) => e.message, 'message', 'Неверный пароль доступа')));
    } finally {
      await server.stop();
      await dir.delete(recursive: true);
    }
  });
}
