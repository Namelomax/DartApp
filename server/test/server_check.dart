// Проверка сервера без внешних пакетов: dart run server/test/server_check.dart
import 'dart:convert';
import 'dart:io';

import '../bin/server.dart';

var _failures = 0;

void check(bool ok, String what) {
  stdout.writeln('${ok ? 'OK  ' : 'FAIL'} $what');
  if (!ok) _failures++;
}

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('cloud_check_');
  final server = CloudServer(storage: dir, token: 'secret');
  await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  final base = 'http://127.0.0.1:${server.port}/api';
  final client = HttpClient();

  Future<(int, List<int>, HttpHeaders)> call(String method, String path,
      {List<int>? body, String token = 'secret', String? range}) async {
    final req = await client.openUrl(method, Uri.parse('$base$path'));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    if (body != null) req.add(body);
    final res = await req.close();
    final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    return (res.statusCode, bytes, res.headers);
  }

  try {
    check((await call('GET', '/ping', token: 'wrong')).$1 == 401, 'wrong token rejected');
    check((await call('GET', '/ping')).$1 == 200, 'ping');

    final data = List<int>.generate(1000, (i) => i % 256);
    check((await call('PUT', '/files/photo_1.jpg', body: data)).$1 == 201, 'upload');
    await call('PUT', '/files/clip.mp4', body: [1, 2, 3]);

    final list = jsonDecode(utf8.decode((await call('GET', '/files')).$2)) as List;
    check(list.length == 2, 'list has 2 files');
    final photo = list.firstWhere((e) => e['name'] == 'photo_1.jpg');
    check(photo['size'] == 1000 && photo['kind'] == 'image', 'photo metadata');
    check(list.any((e) => e['name'] == 'clip.mp4' && e['kind'] == 'video'), 'video kind');

    final full = await call('GET', '/files/photo_1.jpg');
    check(full.$1 == 200 && full.$2.length == 1000 && full.$2[999] == 999 % 256, 'download');
    check(full.$3.contentType?.mimeType == 'image/jpeg', 'content type');

    final part = await call('GET', '/files/photo_1.jpg', range: 'bytes=10-19');
    check(part.$1 == 206 && part.$2.length == 10 && part.$2.first == 10, 'range request');
    check(part.$3.value('content-range') == 'bytes 10-19/1000', 'content-range header');
    final tail = await call('GET', '/files/photo_1.jpg', range: 'bytes=990-');
    check(tail.$1 == 206 && tail.$2.length == 10, 'open-ended range');
    check((await call('GET', '/files/photo_1.jpg', range: 'bytes=5000-')).$1 == 416,
        'unsatisfiable range');

    check((await call('GET', '/files/..%5Cserver.dart')).$1 == 400, 'path traversal blocked');
    check((await call('GET', '/files/missing.jpg')).$1 == 404, 'missing file 404');

    check((await call('DELETE', '/files/clip.mp4')).$1 == 200, 'delete');
    final after = jsonDecode(utf8.decode((await call('GET', '/files')).$2)) as List;
    check(after.length == 1, 'file gone after delete');
  } finally {
    client.close(force: true);
    await server.stop();
    await dir.delete(recursive: true);
  }

  stdout.writeln(_failures == 0 ? 'Все проверки пройдены' : 'Провалено: $_failures');
  exit(_failures == 0 ? 0 : 1);
}
