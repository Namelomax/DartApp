import 'package:flutter/material.dart';

import '../main.dart';
import '../settings.dart';

class SettingsScreen extends StatefulWidget {
  final ServerSettings initial;
  final BackendFactory backendFactory;

  const SettingsScreen({super.key, required this.initial, required this.backendFactory});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _url = TextEditingController(
      text: widget.initial.serverUrl.isEmpty ? 'http://192.168.' : widget.initial.serverUrl);
  late final _token = TextEditingController(text: widget.initial.token);
  bool _checking = false;
  String? _status;
  bool _ok = false;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  ServerSettings get _current => ServerSettings(serverUrl: _url.text.trim(), token: _token.text);

  String? _validateUrl() {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty || !uri.scheme.startsWith('http')) {
      return 'Адрес вида http://192.168.1.10:8080';
    }
    return null;
  }

  /// Проверяет связь и сохраняет. Возвращает true, если всё хорошо.
  Future<bool> _check() async {
    final urlError = _validateUrl();
    if (urlError != null || _token.text.isEmpty) {
      setState(() {
        _ok = false;
        _status = urlError ?? 'Введите пароль';
      });
      return false;
    }
    setState(() {
      _checking = true;
      _status = null;
    });
    try {
      await widget.backendFactory(_current).ping();
      setState(() {
        _ok = true;
        _status = 'Соединение установлено';
      });
      return true;
    } catch (e) {
      setState(() {
        _ok = false;
        _status = '$e';
      });
      return false;
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _save() async {
    if (!await _check()) return;
    await _current.save();
    if (mounted) Navigator.of(context).pop(_current);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки облака')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Запустите на компьютере server/start_server.bat — он покажет адрес. '
            'Телефон и компьютер должны быть в одной Wi-Fi сети.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Адрес сервера',
              hintText: 'http://192.168.1.10:8080',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Пароль доступа',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(_ok ? Icons.check_circle : Icons.error,
                      color: _ok ? Colors.green : scheme.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_status!)),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _checking ? null : _check,
                  child: const Text('Проверить'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _checking ? null : _save,
                  child: _checking
                      ? const SizedBox.square(
                          dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Сохранить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
