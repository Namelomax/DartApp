import 'dart:io';

enum CloudItemKind { image, video, other }

/// Файл в облаке.
class CloudItem {
  final String name;
  final int size;
  final DateTime modified;
  final CloudItemKind kind;

  const CloudItem({
    required this.name,
    required this.size,
    required this.modified,
    required this.kind,
  });

  factory CloudItem.fromJson(Map<String, dynamic> json) => CloudItem(
        name: json['name'] as String,
        size: json['size'] as int,
        modified: DateTime.parse(json['modified'] as String).toLocal(),
        kind: CloudItemKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => CloudItemKind.other,
        ),
      );
}

class StorageException implements Exception {
  final String message;
  const StorageException(this.message);

  @override
  String toString() => message;
}

/// Хранилище файлов. Сейчас есть реализация для своего компьютера
/// ([HomeServerBackend]); стороннее облако подключается новой реализацией
/// этого интерфейса без изменений в экранах.
abstract class StorageBackend {
  /// Проверка связи и пароля. Бросает [StorageException] при ошибке.
  Future<void> ping();

  /// Все файлы, новые первыми.
  Future<List<CloudItem>> list();

  Future<void> upload(File file, String name, {void Function(double progress)? onProgress});

  Future<void> delete(String name);

  /// Адрес для показа/проигрывания файла.
  Uri fileUri(String name);

  /// Заголовки, которые нужно передать при загрузке [fileUri].
  Map<String, String> get headers;
}
