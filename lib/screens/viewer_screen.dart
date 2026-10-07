import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../storage/storage_backend.dart';

/// Просмотр фото и видео с перелистыванием. Возвращает true, если что-то удалили.
class ViewerScreen extends StatefulWidget {
  final StorageBackend backend;
  final List<CloudItem> items;
  final int initialIndex;

  const ViewerScreen({
    super.key,
    required this.backend,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late final List<CloudItem> _items = [...widget.items];
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _changed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final item = _items[_index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить файл?'),
        content: Text('${item.name} будет удалён из облака.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.backend.delete(item.name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }
    if (!mounted) return;
    _changed = true;
    if (_items.length == 1) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _items.removeAt(_index);
      if (_index >= _items.length) _index = _items.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = _items[_index];
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: const TextStyle(fontSize: 15)),
              Text('${_formatDate(item.modified)} · ${_formatSize(item.size)}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
          actions: [
            IconButton(tooltip: 'Удалить', onPressed: _delete, icon: const Icon(Icons.delete)),
          ],
        ),
        body: PageView.builder(
          controller: _pages,
          itemCount: _items.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) {
            final it = _items[i];
            final uri = widget.backend.fileUri(it.name);
            return switch (it.kind) {
              CloudItemKind.image => InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      uri.toString(),
                      headers: widget.backend.headers,
                      loadingBuilder: (_, child, p) => p == null
                          ? child
                          : const CircularProgressIndicator(color: Colors.white),
                      errorBuilder: (_, _, _) =>
                          const _ErrorText('Не удалось загрузить изображение'),
                    ),
                  ),
                ),
              CloudItemKind.video => _VideoView(
                  key: ValueKey(it.name),
                  uri: uri,
                  headers: widget.backend.headers,
                ),
              CloudItemKind.other => const _ErrorText('Этот тип файла нельзя просмотреть'),
            };
          },
        ),
      ),
    );
  }
}

class _VideoView extends StatefulWidget {
  final Uri uri;
  final Map<String, String> headers;

  const _VideoView({super.key, required this.uri, required this.headers});

  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  late final VideoPlayerController _controller =
      VideoPlayerController.networkUrl(widget.uri, httpHeaders: widget.headers);
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onUpdate);
    _controller.initialize().then((_) {
      if (mounted) _controller.play();
    }).catchError((Object e) {
      if (mounted) setState(() => _error = 'Не удалось открыть видео');
    });
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final v = _controller.value;
    if (v.isPlaying) {
      _controller.pause();
    } else {
      if (v.position >= v.duration) _controller.seekTo(Duration.zero);
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _ErrorText(_error!);
    final v = _controller.value;
    if (!v.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _togglePlay,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_controller)),
                if (!v.isPlaying)
                  const Icon(Icons.play_circle_fill, size: 72, color: Colors.white70),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
            child: Row(
              children: [
                IconButton(
                  color: Colors.white,
                  onPressed: _togglePlay,
                  icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                Expanded(
                  child: VideoProgressIndicator(_controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
                const SizedBox(width: 12),
                Text('${_formatDuration(v.position)} / ${_formatDuration(v.duration)}',
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String text;
  const _ErrorText(this.text);

  @override
  Widget build(BuildContext context) =>
      Center(child: Text(text, style: const TextStyle(color: Colors.white70)));
}

String _two(int n) => n.toString().padLeft(2, '0');

String _formatDate(DateTime d) =>
    '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';

String _formatDuration(Duration d) =>
    '${d.inMinutes}:${_two(d.inSeconds.remainder(60))}';

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
}
