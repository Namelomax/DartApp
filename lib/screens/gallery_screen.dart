import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../main.dart';
import '../settings.dart';
import '../storage/storage_backend.dart';
import 'settings_screen.dart';
import 'viewer_screen.dart';

class GalleryScreen extends StatefulWidget {
  final BackendFactory backendFactory;

  const GalleryScreen({super.key, required this.backendFactory});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _picker = ImagePicker();

  ServerSettings? _settings;
  StorageBackend? _backend;
  List<CloudItem>? _items;
  String? _error;
  bool _loading = false;

  /// Текущая загрузка: «2 из 3», прогресс 0..1.
  String? _uploadLabel;
  double? _uploadProgress;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final settings = await ServerSettings.load();
    if (!mounted) return;
    _applySettings(settings);
    if (settings.isComplete) await _recoverLostCapture();
  }

  void _applySettings(ServerSettings settings) {
    setState(() {
      _settings = settings;
      _backend = settings.isComplete ? widget.backendFactory(settings) : null;
      _items = null;
      _error = null;
    });
    if (_backend != null) _refresh();
  }

  Future<void> _refresh() async {
    final backend = _backend;
    if (backend == null) return;
    setState(() => _loading = true);
    try {
      final items = await backend.list();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Android может выгрузить приложение, пока открыта камера. Тогда снятый файл
  /// возвращается при следующем запуске — загружаем его.
  Future<void> _recoverLostCapture() async {
    if (!Platform.isAndroid) return;
    try {
      final lost = await _picker.retrieveLostData();
      if (lost.isEmpty || lost.files == null) return;
      await _uploadAll(lost.files!);
    } catch (_) {}
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<ServerSettings>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          initial: _settings ?? const ServerSettings(serverUrl: '', token: ''),
          backendFactory: widget.backendFactory,
        ),
      ),
    );
    if (updated != null && mounted) _applySettings(updated);
  }

  Future<void> _addMedia() async {
    final choice = await showModalBottomSheet<_Source>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Сделать фото'),
              onTap: () => Navigator.pop(context, _Source.photo),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Снять видео'),
              onTap: () => Navigator.pop(context, _Source.video),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Выбрать из галереи'),
              onTap: () => Navigator.pop(context, _Source.gallery),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    try {
      final files = switch (choice) {
        _Source.photo => [await _picker.pickImage(source: ImageSource.camera, imageQuality: 90)],
        _Source.video => [await _picker.pickVideo(source: ImageSource.camera)],
        _Source.gallery => await _picker.pickMultipleMedia(),
      };
      await _uploadAll(files.whereType<XFile>().toList());
    } catch (e) {
      _showMessage('Не удалось открыть камеру или галерею: $e');
    }
  }

  Future<void> _uploadAll(List<XFile> files) async {
    final backend = _backend;
    if (backend == null || files.isEmpty) return;
    var done = 0;
    for (var i = 0; i < files.length; i++) {
      final name = uploadName(files[i].path, DateTime.now(), i);
      setState(() {
        _uploadLabel = files.length == 1 ? 'Загрузка…' : 'Загрузка ${i + 1} из ${files.length}…';
        _uploadProgress = 0;
      });
      try {
        await backend.upload(File(files[i].path), name,
            onProgress: (v) => mounted ? setState(() => _uploadProgress = v) : null);
        done++;
      } catch (e) {
        _showMessage('Не удалось загрузить ${p.basename(files[i].path)}: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _uploadLabel = null;
      _uploadProgress = null;
    });
    if (done > 0) {
      _showMessage(done == 1 ? 'Файл загружен в облако' : 'Загружено файлов: $done');
      await _refresh();
    }
  }

  Future<void> _openItem(int index) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ViewerScreen(backend: _backend!, items: _items!, initialIndex: index),
      ),
    );
    if (changed == true) await _refresh();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final uploading = _uploadLabel != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Моё облако'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _backend == null || _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Настройки',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
        bottom: uploading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_uploadLabel!, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: _uploadProgress),
                    ],
                  ),
                ),
              )
            : null,
      ),
      floatingActionButton: _backend == null
          ? null
          : FloatingActionButton.extended(
              onPressed: uploading ? null : _addMedia,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Добавить'),
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_settings == null) return const Center(child: CircularProgressIndicator());

    if (_backend == null) {
      return _Message(
        icon: Icons.cloud_off,
        text: 'Облако не настроено.\nУкажите адрес сервера на компьютере и пароль.',
        action: FilledButton(onPressed: _openSettings, child: const Text('Настроить')),
      );
    }

    final items = _items;
    if (items == null) {
      if (_error != null) {
        return _Message(
          icon: Icons.error_outline,
          text: _error!,
          action: FilledButton(onPressed: _refresh, child: const Text('Повторить')),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: items.isEmpty
          ? ListView(children: const [
              SizedBox(height: 120),
              _Message(
                icon: Icons.cloud_queue,
                text: 'В облаке пока пусто.\nНажмите «Добавить», чтобы снять фото или видео.',
              ),
            ])
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 88),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 140,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => _Tile(
                item: items[i],
                backend: _backend!,
                onTap: () => _openItem(i),
              ),
            ),
    );
  }
}

enum _Source { photo, video, gallery }

/// Имя файла в облаке: IMG_20261007_153012.jpg / VID_20261007_153012.mp4.
String uploadName(String localPath, DateTime time, [int index = 0]) {
  var ext = p.extension(localPath).toLowerCase();
  if (!RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(ext)) ext = '.jpg';
  const videoExt = {'.mp4', '.mov', '.3gp', '.webm', '.mkv'};
  final prefix = videoExt.contains(ext) ? 'VID' : 'IMG';
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp = '${time.year}${two(time.month)}${two(time.day)}_'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  // Миллисекунды + номер, чтобы файлы, снятые в одну секунду, не перезаписали друг друга.
  final suffix = '${time.millisecond.toString().padLeft(3, '0')}${index > 0 ? '_$index' : ''}';
  return '${prefix}_${stamp}_$suffix$ext';
}

class _Tile extends StatelessWidget {
  final CloudItem item;
  final StorageBackend backend;
  final VoidCallback onTap;

  const _Tile({required this.item, required this.backend, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget placeholder(IconData icon) => Container(
          color: scheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(icon, size: 36, color: scheme.onSurfaceVariant),
        );

    final Widget content = switch (item.kind) {
      CloudItemKind.image => Image.network(
          backend.fileUri(item.name).toString(),
          headers: backend.headers,
          fit: BoxFit.cover,
          cacheWidth: 300,
          errorBuilder: (_, _, _) => placeholder(Icons.broken_image),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : placeholder(Icons.image),
        ),
      CloudItemKind.video => Stack(
          fit: StackFit.expand,
          children: [
            placeholder(Icons.movie),
            const Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.play_circle_fill, color: Colors.white, size: 28),
              ),
            ),
          ],
        ),
      CloudItemKind.other => placeholder(Icons.insert_drive_file),
    };

    return Semantics(
      label: item.name,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ClipRRect(borderRadius: BorderRadius.circular(6), child: content),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
