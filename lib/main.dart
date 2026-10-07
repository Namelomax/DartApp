import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'game.dart';
import 'word_list.dart';

/// Letters per word, and therefore tiles per row.
const wordLength = 5;

Future<void> main() async {
  // isOptional: the game is fully playable with no .env at all, on the
  // downloaded noun dictionary.
  await dotenv.load(isOptional: true);
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Align(
            alignment: Alignment.centerLeft,
            child: Text('Birdle'),
          ),
        ),
        // Scrollable so a tall board still fits a short window: inside a
        // Center the scroll view shrinks to its content, so the board stays
        // vertically centred whenever there is room for it.
        body: const Center(
          child: SingleChildScrollView(child: DictionaryLoader()),
        ),
      ),
    );
  }
}

/// Downloads the dictionaries, then hands over to [GamePage].
///
/// If the download fails the game still starts, on the small built-in word
/// list, with a note explaining why the choice of words is so narrow.
class DictionaryLoader extends StatefulWidget {
  const DictionaryLoader({super.key});

  @override
  State<DictionaryLoader> createState() => _DictionaryLoaderState();
}

class _DictionaryLoaderState extends State<DictionaryLoader> {
  late final Future<WordSource> _loading;

  @override
  void initState() {
    super.initState();
    // Started here, not in build(), so a rebuild can't kick off a second
    // download.
    _loading = loadWordLists();
  }

  /// One line telling the player which pool the hidden word came from.
  String _statusFor(AsyncSnapshot<WordSource> snapshot) {
    if (snapshot.hasError) {
      return 'Словарь не загрузился — играем на встроенных '
          '${legalWords.length} словах.';
    }
    return switch (snapshot.data) {
      WordSource.ai => 'Слова сгенерированы ИИ: ${legalWords.length} шт.',
      _ => 'Слова из словаря существительных: ${legalWords.length} шт.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WordSource>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 16.0,
            children: [CircularProgressIndicator(), Text('Готовим слова…')],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _statusFor(snapshot),
                textAlign: TextAlign.center,
                style: snapshot.hasError
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const GamePage(),
          ],
        );
      },
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  // This manages game logic, and is out of scope for this lesson.
  Game _game = Game();

  /// The letters typed into the active row but not yet submitted.
  String _typed = '';

  /// Holds keyboard focus for the whole board; there is no text field now.
  final FocusNode _boardFocus = FocusNode(debugLabel: 'board');

  bool get _isOver => _game.didWin || _game.didLose;

  @override
  void dispose() {
    _boardFocus.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    // Ignore key-up; accept repeats so holding backspace keeps deleting.
    if (event is KeyUpEvent || _isOver) return;

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_typed.isNotEmpty) {
        setState(() => _typed = _typed.substring(0, _typed.length - 1));
      }
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _submitGuess();
      return;
    }

    // `character` is what the layout produced, so it follows the user's
    // keyboard rather than the physical key's US label.
    final char = event.character;
    if (char == null || _typed.length == wordLength) return;
    if (isRussianLetter(char)) {
      setState(() => _typed += normalizeWord(char));
    }
  }

  void _submitGuess() {
    if (_typed.length < wordLength) {
      _showMessage('Нужно $wordLength букв');
      return;
    }
    if (!_game.isLegalGuess(_typed)) {
      // The word stays on the board so it can be edited, not retyped.
      _showMessage('«$_typed» нет в словаре');
      return;
    }

    setState(() {
      _game.guess(_typed);
      _typed = '';
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  void _startNewGame() {
    setState(() {
      _game = Game();
      _typed = '';
    });
    // The button stole focus when it was tapped; take it back.
    _boardFocus.requestFocus();
  }

  String? get _status {
    if (_game.didWin) return 'Угадали!';
    if (_game.didLose) return 'Было загадано слово «${_game.hiddenWord}»';
    return null;
  }

  /// The letters to draw in row [row], which for the active row are the
  /// unsubmitted ones held in [_typed].
  List<Letter> _lettersFor(int row) {
    if (row != _game.activeIndex) return _game.guesses[row].toList();

    return [
      for (var i = 0; i < wordLength; i++)
        (char: i < _typed.length ? _typed[i] : '', type: HitType.none),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    return GestureDetector(
      // Clicking the board after a stray click elsewhere restores typing.
      onTap: _boardFocus.requestFocus,
      child: KeyboardListener(
        focusNode: _boardFocus,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 5.0,
            children: [
              for (var row = 0; row < _game.guesses.length; row++)
                _buildRow(row),
              if (status != null) ...[
                const SizedBox(height: 8.0),
                Text(status, style: Theme.of(context).textTheme.titleMedium),
                FilledButton(
                  onPressed: _startNewGame,
                  child: const Text('Новая игра'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(int row) {
    final letters = _lettersFor(row);
    final isActiveRow = !_isOver && row == _game.activeIndex;

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 5.0,
      children: [
        for (var col = 0; col < wordLength; col++)
          Tile(
            letters[col].char,
            letters[col].type,
            isCursor: isActiveRow && col == _typed.length,
          ),
      ],
    );
  }
}

class Tile extends StatelessWidget {
  const Tile(this.letter, this.hitType, {super.key, this.isCursor = false});

  final String letter;
  final HitType hitType;

  /// Whether this tile is where the next typed letter will land.
  final bool isCursor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        border: Border.all(
          color: isCursor
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade300,
          width: isCursor ? 2.5 : 1.0,
        ),
        color: switch (hitType) {
          HitType.hit => Colors.green,
          HitType.partial => Colors.yellow,
          HitType.miss => Colors.grey,
          _ => Colors.white,
        },
      ),
      child: Center(
        child: Text(
          letter.toUpperCase(),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}
