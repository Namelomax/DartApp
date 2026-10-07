import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/ai_words.dart';
import 'package:flutter_application_1/game.dart';
import 'package:flutter_application_1/word_list.dart';

/// Ten five-letter nouns, standing in for the downloaded dictionary.
const dictionaryWords = [
  'зверь',
  'зебра',
  'время',
  'место',
  'слово',
  'город',
  'книга',
  'стена',
  'полка',
  'ветер',
];

/// The dictionary as the server serves it: one word per line, plus noise the
/// parser is expected to drop.
String dictionaryBody() =>
    [...dictionaryWords, 'дом', 'короткое', 'hello', 'КЛЁСТ', ''].join('\n');

http.Response okBytes(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

/// A completion envelope whose message content is [content].
http.Response completion(String content) =>
    okBytes({'choices': [{'message': {'content': content}}]});

/// A mock that serves the dictionary on GET and [aiReply] on POST.
MockClient mockBackend({
  http.Response Function(http.Request request)? aiReply,
  int dictionaryStatus = 200,
}) => MockClient((request) async {
  if (request.method == 'POST') {
    if (aiReply == null) throw StateError('Unexpected AI call');
    return aiReply(request);
  }
  if (dictionaryStatus != 200) {
    return http.Response('nope', dictionaryStatus);
  }
  return http.Response.bytes(utf8.encode(dictionaryBody()), 200);
});

void configureAi({String key = 'test-key', int wordCount = 60}) {
  dotenv.loadFromString(
    envString: [
      'AI_BASE_URL=https://example.test/api/v1/',
      'AI_MODEL=test/model',
      'AI_API_KEY=$key',
      'AI_WORD_COUNT=$wordCount',
    ].join('\n'),
  );
}

void main() {
  setUp(() {
    // No AI by default; individual tests opt in via configureAi().
    dotenv.loadFromString(envString: 'AI_API_KEY=', isOptional: true);
    legalWords = ['такой'];
    legalGuesses = const [];
    allLegalGuesses = {'такой'};
  });

  group('dictionary', () {
    test('keeps only normalized five-letter Cyrillic words', () async {
      final source = await loadWordLists(client: mockBackend());

      expect(source, WordSource.dictionary);
      expect(allLegalGuesses, containsAll(dictionaryWords));
      // Wrong length, or not Cyrillic at all.
      expect(allLegalGuesses, isNot(contains('дом')));
      expect(allLegalGuesses, isNot(contains('короткое')));
      expect(allLegalGuesses, isNot(contains('hello')));
      // Uppercase folded down and "ё" folded to "е".
      expect(allLegalGuesses, contains('клест'));
      // Without AI, every legal guess can also be the hidden word.
      expect(legalWords.toSet(), allLegalGuesses);
    });

    test('leaves the fallback words in place when the download fails', () async {
      final fallback = List<String>.from(legalWords);

      await expectLater(
        loadWordLists(client: mockBackend(dictionaryStatus: 503)),
        throwsA(isA<http.ClientException>()),
      );
      expect(legalWords, fallback);
    });
  });

  group('AI-generated hidden words', () {
    test('keeps the words the dictionary confirms as nouns', () async {
      configureAi();
      final generated = [...dictionaryWords.take(6), 'абвгд', 'дом'];
      final source = await loadWordLists(
        client: mockBackend(
          aiReply: (_) => completion(jsonEncode({'words': generated})),
        ),
      );

      expect(source, WordSource.ai);
      // The six confirmed nouns become the hidden-word pool.
      expect(legalWords.toSet(), dictionaryWords.take(6).toSet());
      // "абвгд" has the right shape but is not in the dictionary.
      expect(legalWords, isNot(contains('абвгд')));
      // Guesses still come from the whole dictionary, not the AI subset.
      expect(allLegalGuesses, containsAll(dictionaryWords));
    });

    test('falls back to the dictionary when too few are confirmed', () async {
      configureAi();
      final source = await loadWordLists(
        client: mockBackend(
          // Right shape, but none of them real nouns.
          aiReply: (_) =>
              completion(jsonEncode({'words': ['абвгд', 'ежжзи']})),
        ),
      );

      expect(source, WordSource.dictionary);
      expect(legalWords.toSet(), allLegalGuesses);
    });

    test('falls back when the model call errors', () async {
      configureAi();
      final source = await loadWordLists(
        client: mockBackend(
          aiReply: (_) => http.Response('rate limited', 429),
        ),
      );

      expect(source, WordSource.dictionary);
      expect(legalWords.toSet(), allLegalGuesses);
    });

    test('is skipped entirely when .env has no key', () async {
      // mockBackend without aiReply throws if a POST is attempted.
      final source = await loadWordLists(client: mockBackend());

      expect(source, WordSource.dictionary);
    });
  });

  group('generateWords', () {
    test('throws when .env is not filled in', () async {
      expect(isAiConfigured, isFalse);
      await expectLater(
        generateWords(count: 5, client: mockBackend()),
        throwsA(isA<AiNotConfigured>()),
      );
    });

    test('sends the configured model and key to /chat/completions', () async {
      configureAi(key: 'secret-key');
      late http.Request seen;

      await generateWords(
        count: 7,
        client: mockBackend(
          aiReply: (request) {
            seen = request;
            return completion(jsonEncode({'words': dictionaryWords}));
          },
        ),
      );

      // The trailing slash in AI_BASE_URL must not produce a double slash.
      expect(seen.url.toString(), 'https://example.test/api/v1/chat/completions');
      expect(seen.headers['Authorization'], 'Bearer secret-key');

      final body = jsonDecode(utf8.decode(seen.bodyBytes)) as Map<String, Object?>;
      expect(body['model'], 'test/model');
      expect(body['response_format'], {'type': 'json_object'});
      expect(jsonEncode(body['messages']), contains('7'));
    });

    test('reads AI_WORD_COUNT from .env', () {
      configureAi(wordCount: 33);
      expect(aiWordCount, 33);
    });

    test('scrapes words from a reply that is not JSON', () async {
      configureAi();

      final words = await generateWords(
        count: 5,
        client: mockBackend(
          aiReply: (_) => completion(
            'Вот слова: зебра, время, место. Надеюсь, подойдут!',
          ),
        ),
      );

      expect(words, containsAll(['зебра', 'время', 'место']));
      // Longer words are dropped whole, not sliced into five-letter pieces.
      expect(words, isNot(contains('надею')));
      expect(words, isNot(contains('подой')));
    });

    test('retries without response_format when the model rejects it', () async {
      configureAi();
      final sentBodies = <Map<String, Object?>>[];

      final words = await generateWords(
        count: 5,
        client: mockBackend(
          aiReply: (request) {
            final body =
                jsonDecode(utf8.decode(request.bodyBytes))
                    as Map<String, Object?>;
            sentBodies.add(body);
            if (body.containsKey('response_format')) {
              return http.Response('response_format is unsupported', 400);
            }
            return completion(jsonEncode({'words': dictionaryWords}));
          },
        ),
      );

      expect(sentBodies, hasLength(2));
      expect(sentBodies.first.containsKey('response_format'), isTrue);
      expect(sentBodies.last.containsKey('response_format'), isFalse);
      expect(words, containsAll(dictionaryWords));
    });

    test('accepts a bare JSON array', () async {
      configureAi();

      final words = await generateWords(
        count: 5,
        client: mockBackend(
          aiReply: (_) => completion(jsonEncode(['зебра', 'КЛЁСТ', 'дом'])),
        ),
      );

      // Normalized on the way in; the three-letter word is dropped.
      expect(words, {'зебра', 'клест'});
    });
  });
}
