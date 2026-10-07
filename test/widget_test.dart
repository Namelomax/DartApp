import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/game.dart';
import 'package:flutter_application_1/main.dart';

/// Pumps the board on its own, so no test depends on the network.
Future<void> pumpGame(WidgetTester tester) => tester.pumpWidget(
  const MaterialApp(
    // Mirrors MainApp: a tall board scrolls rather than overflowing.
    home: Scaffold(
      body: Center(child: SingleChildScrollView(child: GamePage())),
    ),
  ),
);

/// Types [word] one letter at a time, as a physical keyboard would.
///
/// The logical key is irrelevant to the board, which reads `event.character`;
/// only backspace and enter are matched by key.
Future<void> type(WidgetTester tester, String word) async {
  for (final char in word.split('')) {
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: char);
  }
  await tester.pump();
}

Future<void> pressEnter(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

Future<void> pressBackspace(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
  await tester.pump();
}

/// The tiles of row [row], top to bottom.
List<Tile> tilesInRow(WidgetTester tester, int row) => tester
    .widgetList<Tile>(find.byType(Tile))
    .skip(row * wordLength)
    .take(wordLength)
    .toList();

String rowText(WidgetTester tester, int row) =>
    tilesInRow(tester, row).map((tile) => tile.letter).join();

void main() {
  setUp(() {
    // A one-word hidden list makes the round deterministic.
    legalWords = ['слово'];
    legalGuesses = ['время', 'места'];
    allLegalGuesses = {...legalWords, ...legalGuesses};
  });

  group('typing into the board', () {
    testWidgets('renders one tile per letter of every attempt', (
      tester,
    ) async {
      await pumpGame(tester);

      expect(
        find.byType(Tile),
        findsNWidgets(Game.defaultMaxGuesses * wordLength),
      );
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('letters land in the active row', (tester) async {
      await pumpGame(tester);

      await type(tester, 'вре');

      expect(rowText(tester, 0), 'вре');
      expect(rowText(tester, 1), '');
    });

    testWidgets('the cursor follows the next empty tile', (tester) async {
      await pumpGame(tester);
      expect(tilesInRow(tester, 0)[0].isCursor, isTrue);

      await type(tester, 'вр');

      expect(tilesInRow(tester, 0)[2].isCursor, isTrue);
      expect(tilesInRow(tester, 0)[0].isCursor, isFalse);
    });

    testWidgets('backspace deletes the last letter', (tester) async {
      await pumpGame(tester);

      await type(tester, 'вре');
      await pressBackspace(tester);

      expect(rowText(tester, 0), 'вр');
    });

    testWidgets('a sixth letter is ignored', (tester) async {
      await pumpGame(tester);

      await type(tester, 'времяя');

      expect(rowText(tester, 0), 'время');
    });

    testWidgets('non-Russian keys are ignored', (tester) async {
      await pumpGame(tester);

      await type(tester, 'ab1-');

      expect(rowText(tester, 0), '');
    });

    testWidgets('"ё" is typed as "е"', (tester) async {
      await pumpGame(tester);

      await type(tester, 'Ё');

      expect(rowText(tester, 0), 'е');
    });
  });

  group('submitting', () {
    testWidgets('enter scores the guess and moves to the next row', (
      tester,
    ) async {
      await pumpGame(tester);

      await type(tester, 'время');
      await pressEnter(tester);

      expect(rowText(tester, 0), 'время');
      expect(tilesInRow(tester, 0).first.hitType, isNot(HitType.none));
      // The cursor has moved down; the first row is no longer editable.
      expect(tilesInRow(tester, 1)[0].isCursor, isTrue);

      await type(tester, 'мест');
      expect(rowText(tester, 1), 'мест');
      expect(rowText(tester, 0), 'время');
    });

    testWidgets('an incomplete word is refused and kept on the board', (
      tester,
    ) async {
      await pumpGame(tester);

      await type(tester, 'вре');
      await pressEnter(tester);

      expect(find.text('Нужно 5 букв'), findsOneWidget);
      expect(rowText(tester, 0), 'вре');
    });

    testWidgets('a word outside the dictionary is refused and kept', (
      tester,
    ) async {
      await pumpGame(tester);

      await type(tester, 'ыыыыы');
      await pressEnter(tester);

      expect(find.text('«ыыыыы» нет в словаре'), findsOneWidget);
      // Still editable rather than wiped, so one wrong letter can be fixed.
      expect(rowText(tester, 0), 'ыыыыы');

      await pressBackspace(tester);
      expect(rowText(tester, 0), 'ыыыы');
    });

    testWidgets('guessing the word wins and offers a new game', (tester) async {
      await pumpGame(tester);

      await type(tester, 'слово');
      await pressEnter(tester);

      expect(find.text('Угадали!'), findsOneWidget);
      for (final tile in tilesInRow(tester, 0)) {
        expect(tile.hitType, HitType.hit);
      }

      // Typing after the game ends does nothing.
      await type(tester, 'время');
      expect(rowText(tester, 1), '');

      await tester.ensureVisible(find.text('Новая игра'));
      await tester.tap(find.text('Новая игра'));
      await tester.pump();

      expect(find.text('Угадали!'), findsNothing);
      expect(rowText(tester, 0), '');

      // The board took keyboard focus back from the button.
      await type(tester, 'вре');
      expect(rowText(tester, 0), 'вре');
    });
  });
}
