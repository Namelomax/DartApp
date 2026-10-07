// Сервер домашнего облака: хранит фото и видео в папке на этом компьютере.
//
// Запуск:
//   dart run server/bin/server.dart --dir D:\CloudStorage --port 8080 --token секрет
//
// API (все запросы требуют заголовок "Authorization: Bearer <token>"):
//   GET    /api/ping              проверка связи
//   GET    /api/files             список файлов (JSON)
//   PUT    /api/files/<name>      загрузить файл (тело запроса = содержимое)
//   GET    /api/files/<name>      скачать файл (поддерживает Range для видео)
//   DELETE /api/files/<name>      удалить файл
//
// Журнал пишется в консоль и в файл (--log, по умолчанию logs/server.log).

import 'dart:convert';
import 'dart:io';

IOSink? _logFile;

String _two(int n) => n.toString().padLeft(2, '0');

/// Пишет строку с временем в консоль и в файл журнала.
void log(String message) {
  final t = DateTime.now();
  final line = '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}  $message';
  stdout.writeln(line);
  _logFile?.writeln(line);
}

const _mimeTypes = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.heic': 'image/heic',
  '.mp4': 'video/mp4',
  '.mov': 'video/quicktime',
  '.3gp': 'video/3gpp',
  '.webm': 'video/webm',
  '.mkv': 'video/x-matroska',
};

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot).toLowerCase();
}

String mimeTypeOf(String name) =>
    _mimeTypes[_extension(name)] ?? 'application/octet-stream';

String kindOf(String name) {
  final mime = mimeTypeOf(name);
  if (mime.startsWith('image/')) return 'image';
  if (mime.startsWith('video/')) return 'video';
  return 'other';
}

/// Разрешаем только простые имена файлов, чтобы нельзя было выйти за пределы папки.
bool isSafeName(String name) =>
    name.isNotEmpty &&
    name.length <= 200 &&
    name != '.' &&
    name != '..' &&
    !name.startsWith('.') &&
    RegExp(r'^[\w\-. ()]+$', unicode: true).hasMatch(name);

class CloudServer {
  final Directory storage;
  final String token;
  HttpServer? _server;

  CloudServer({required this.storage, required this.token});

  int get port => _server!.port;

  Future<void> start({int port = 8080, InternetAddress? address}) async {
    await storage.create(recursive: true);
    _server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _server!.listen(_handle);
  }

  Future<void> stop() async => _server?.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final client = req.connectionInfo?.remoteAddress.address ?? '?';
    final range = req.headers.value(HttpHeaders.rangeHeader);
    try {
      if (req.headers.value(HttpHeaders.authorizationHeader) != 'Bearer $token') {
        return await _send(res, HttpStatus.unauthorized, {'error': 'Неверный токен'});
      }
      final segments = req.uri.pathSegments;
      if (segments.length < 2 || segments[0] != 'api') {
        return await _send(res, HttpStatus.notFound, {'error': 'Не найдено'});
      }
      if (segments.length == 2 && segments[1] == 'ping') {
        return await _send(res, HttpStatus.ok, {'ok': true});
      }
      if (segments[1] != 'files') {
        return await _send(res, HttpStatus.notFound, {'error': 'Не найдено'});
      }
      if (segments.length == 2 && req.method == 'GET') return await _list(res);
      if (segments.length != 3) {
        return await _send(res, HttpStatus.notFound, {'error': 'Не найдено'});
      }

      final name = segments[2];
      if (!isSafeName(name)) {
        return await _send(res, HttpStatus.badRequest, {'error': 'Недопустимое имя файла'});
      }
      final file = File('${storage.path}${Platform.pathSeparator}$name');
      switch (req.method) {
        case 'PUT':
          return await _upload(req, file);
        case 'GET':
        case 'HEAD':
          return await _download(req, file);
        case 'DELETE':
          if (!await file.exists()) {
            return await _send(res, HttpStatus.notFound, {'error': 'Файл не найден'});
          }
          await file.delete();
          log('Удалён файл: $name');
          return await _send(res, HttpStatus.ok, {'ok': true});
      }
      return await _send(res, HttpStatus.methodNotAllowed, {'error': 'Метод не поддерживается'});
    } catch (e) {
      log('ОШИБКА ${req.method} ${req.uri.path}: $e');
      try {
        await _send(res, HttpStatus.internalServerError, {'error': '$e'});
      } catch (_) {}
    } finally {
      log('$client  ${req.method} ${Uri.decodeComponent(req.uri.path)}'
          '${range == null ? '' : ' [$range]'} -> ${res.statusCode}');
    }
  }

  Future<void> _list(HttpResponse res) async {
    final items = <Map<String, Object>>[];
    await for (final entity in storage.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!isSafeName(name)) continue; // пропускаем .part и служебные файлы
      final stat = await entity.stat();
      items.add({
        'name': name,
        'size': stat.size,
        'modified': stat.modified.toUtc().toIso8601String(),
        'kind': kindOf(name),
      });
    }
    items.sort((a, b) => (b['modified'] as String).compareTo(a['modified'] as String));
    await _send(res, HttpStatus.ok, items);
  }

  Future<void> _upload(HttpRequest req, File file) async {
    // Пишем во временный файл, чтобы оборванная загрузка не оставила битый файл.
    final temp = File('${file.path}.part');
    final sink = temp.openWrite();
    try {
      await sink.addStream(req);
      await sink.close();
    } catch (e) {
      await sink.close().catchError((_) {});
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
    log('Загружен файл: ${file.uri.pathSegments.last} (${await file.length()} байт)');
    await _send(req.response, HttpStatus.created, {'ok': true});
  }

  Future<void> _download(HttpRequest req, File file) async {
    final res = req.response;
    if (!await file.exists()) {
      return _send(res, HttpStatus.notFound, {'error': 'Файл не найден'});
    }
    final length = await file.length();
    res.headers
      ..contentType = ContentType.parse(mimeTypeOf(file.path))
      ..set(HttpHeaders.acceptRangesHeader, 'bytes');

    var start = 0;
    var end = length - 1;
    final range = req.headers.value(HttpHeaders.rangeHeader);
    final match = range == null ? null : RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
    if (match != null && length > 0) {
      final from = match.group(1)!, to = match.group(2)!;
      if (from.isEmpty && to.isNotEmpty) {
        start = length - int.parse(to).clamp(0, length); // последние N байт
      } else if (from.isNotEmpty) {
        start = int.parse(from);
        if (to.isNotEmpty) end = int.parse(to).clamp(0, length - 1);
      }
      if (start > end || start >= length) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        return res.close();
      }
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
    }
    res.contentLength = length == 0 ? 0 : end - start + 1;
    if (req.method == 'HEAD' || length == 0) return res.close();
    await res.addStream(file.openRead(start, end + 1));
    await res.close();
  }

  Future<void> _send(HttpResponse res, int status, Object body) async {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    await res.close();
  }
}

Future<void> main(List<String> args) async {
  String? arg(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final dir = arg('dir') ?? 'cloud_storage';
  final port = int.tryParse(arg('port') ?? '') ?? 8080;
  final token = arg('token');
  if (token == null || token.isEmpty) {
    stderr.writeln('Укажите пароль доступа: --token <пароль>');
    exit(64);
  }

  final logPath = arg('log') ?? 'logs${Platform.pathSeparator}server.log';
  final logFile = File(logPath);
  await logFile.parent.create(recursive: true);
  _logFile = logFile.openWrite(mode: FileMode.append);

  final server = CloudServer(storage: Directory(dir), token: token);
  try {
    await server.start(port: port);
  } on SocketException {
    log('Порт $port уже занят — скорее всего, сервер уже запущен в другом окне или в фоне.');
    stdout.writeln('Закройте его (Диспетчер задач -> dartvm.exe / dart.exe) или укажите другой --port.');
    await _logFile!.flush();
    exit(1);
  }

  log('Облако запущено. Файлы: ${Directory(dir).absolute.path}');
  stdout.writeln('Журнал: ${logFile.absolute.path}');
  // Виртуальные адаптеры (WSL, Hyper-V, VPN) телефону недоступны — показываем их отдельно.
  final virtual = RegExp(r'vEthernet|WSL|Hyper-V|VirtualBox|VMware|tun|tap|docker|Loopback',
      caseSensitive: false);
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  final real = interfaces.where((i) => !virtual.hasMatch(i.name));
  final other = interfaces.where((i) => virtual.hasMatch(i.name));
  stdout.writeln('Адрес для приложения на телефоне (Wi-Fi / сеть):');
  for (final iface in real) {
    for (final addr in iface.addresses) {
      stdout.writeln('  http://${addr.address}:$port   (${iface.name})');
    }
  }
  if (other.isNotEmpty) {
    stdout.writeln('Виртуальные адаптеры, для телефона не подходят:');
    for (final iface in other) {
      for (final addr in iface.addresses) {
        stdout.writeln('  ${addr.address}   (${iface.name})');
      }
    }
  }
  stdout.writeln('Остановить: Ctrl+C');
}
