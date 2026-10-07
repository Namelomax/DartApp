import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'storage_backend.dart';

/// Хранилище на своём компьютере (см. server/bin/server.dart).
class HomeServerBackend implements StorageBackend {
  final Uri baseUri;
  final String token;
  final http.Client _client;

  HomeServerBackend({required String serverUrl, required this.token, http.Client? client})
      : baseUri = Uri.parse(serverUrl.trim().replaceAll(RegExp(r'/+$'), '')),
        _client = client ?? http.Client();

  static const _timeout = Duration(seconds: 10);

  Uri _api(List<String> segments) =>
      baseUri.replace(pathSegments: [...baseUri.pathSegments, 'api', ...segments]);

  @override
  Map<String, String> get headers => {HttpHeaders.authorizationHeader: 'Bearer $token'};

  @override
  Uri fileUri(String name) => _api(['files', name]);

  @override
  Future<void> ping() async {
    _check(await _guard(() => _client.get(_api(['ping']), headers: headers)));
  }

  @override
  Future<List<CloudItem>> list() async {
    final res = _check(await _guard(() => _client.get(_api(['files']), headers: headers)));
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return data.map((e) => CloudItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> upload(File file, String name, {void Function(double progress)? onProgress}) async {
    final total = await file.length();
    final request = http.StreamedRequest('PUT', fileUri(name))
      ..headers.addAll(headers)
      ..contentLength = total;

    var sent = 0;
    file.openRead().listen(
      (chunk) {
        request.sink.add(chunk);
        sent += chunk.length;
        if (total > 0) onProgress?.call(sent / total);
      },
      onDone: request.sink.close,
      onError: (Object e) {
        request.sink.addError(e);
        request.sink.close();
      },
      cancelOnError: true,
    );

    final streamed = await _guard(() => _client.send(request), timeout: null);
    _check(await http.Response.fromStream(streamed));
  }

  @override
  Future<void> delete(String name) async {
    _check(await _guard(() => _client.delete(fileUri(name), headers: headers)));
  }

  Future<T> _guard<T>(Future<T> Function() call, {Duration? timeout = _timeout}) async {
    try {
      final future = call();
      return await (timeout == null ? future : future.timeout(timeout));
    } on TimeoutException {
      throw const StorageException(
          'Сервер не отвечает. Проверьте, что он запущен и телефон в той же сети.');
    } on SocketException {
      throw const StorageException(
          'Нет связи с сервером. Проверьте адрес и что телефон в той же Wi-Fi сети.');
    } on http.ClientException catch (e) {
      throw StorageException('Ошибка связи: ${e.message}');
    }
  }

  http.Response _check(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    if (res.statusCode == 401) throw const StorageException('Неверный пароль доступа');
    String message;
    try {
      message = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['error'] as String;
    } catch (_) {
      message = 'код ${res.statusCode}';
    }
    throw StorageException('Ошибка сервера: $message');
  }
}
