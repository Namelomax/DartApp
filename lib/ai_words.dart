import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'word_list.dart';

/// Prefix on every log line from this file, so `[ai]` filters the console.
const _tag = '[ai]';

void _log(String message) => debugPrint('$_tag $message');

/// Output ceiling for the completion.
///
/// Left unset, some gateways default low, and a reasoning model can spend the
/// whole allowance on thinking tokens and return empty content.
const _maxTokens = 4096;

/// How much of a reply to print before truncating.
const _logExcerpt = 600;

/// Reads [name] from the loaded `.env`, treating blank values as unset.
String? readEnv(String name) {
  if (!dotenv.isInitialized) return null;
  final value = dotenv.maybeGet(name)?.trim();
  return (value == null || value.isEmpty) ? null : value;
}

/// Whether `.env` carries enough to call the model.
///
/// When false the game skips generation entirely and plays on the downloaded
/// dictionary, so an unfilled `.env` is a supported configuration.
bool get isAiConfigured =>
    readEnv('AI_BASE_URL') != null &&
    readEnv('AI_MODEL') != null &&
    readEnv('AI_API_KEY') != null;

/// How many words to request per round, from `AI_WORD_COUNT`.
int get aiWordCount => int.tryParse(readEnv('AI_WORD_COUNT') ?? '') ?? 60;

/// Thrown when `.env` is missing values [generateWords] needs.
class AiNotConfigured implements Exception {
  const AiNotConfigured();

  @override
  String toString() =>
      'AI is not configured: fill AI_BASE_URL, AI_MODEL '
      'and AI_API_KEY in .env';
}

const _systemPrompt = '''
Ты генератор слов для игры «5 букв» — русского аналога Wordle.

Требования к каждому слову:
- ровно пять букв русского алфавита;
- существительное, именительный падеж, единственное число;
- нарицательное: никаких имён, географических названий и брендов;
- без буквы «ё», без дефисов, пробелов и цифр;
- общеупотребительное: такое, которое носитель языка знает без словаря.

Ответь ТОЛЬКО объектом JSON вида {"words": ["слово", "время"]}.
Без пояснений и без markdown-разметки.
''';

/// Asks the configured model for [count] Russian five-letter nouns.
///
/// Returns the normalized candidates that are shaped like a Russian
/// five-letter word. The model's claim that they are nouns is NOT trusted
/// here — `loadWordLists` confirms each one against the noun dictionary.
///
/// Logs each step under the `[ai]` tag: the request, the HTTP result, token
/// usage, an excerpt of the reply, and what survived parsing.
Future<Set<String>> generateWords({
  required int count,
  http.Client? client,
}) async {
  final baseUrl = readEnv('AI_BASE_URL');
  final model = readEnv('AI_MODEL');
  final apiKey = readEnv('AI_API_KEY');
  if (baseUrl == null || model == null || apiKey == null) {
    throw const AiNotConfigured();
  }

  // Tolerate a trailing slash in the configured URL.
  final endpoint = Uri.parse(
    '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/chat/completions',
  );

  final httpClient = client ?? http.Client();
  final stopwatch = Stopwatch()..start();
  try {
    _log('POST $endpoint');
    _log('model=$model  words=$count  max_tokens=$_maxTokens');

    var response = await _postCompletion(
      httpClient,
      endpoint: endpoint,
      apiKey: apiKey,
      model: model,
      count: count,
      jsonMode: true,
    );

    // Not every model on an OpenAI-compatible gateway accepts
    // `response_format`; those that don't answer 400. The prompt asks for
    // JSON on its own, so retrying without the field usually works.
    if (response.statusCode == 400) {
      _log('HTTP 400 with response_format; retrying without it.');
      _log('  server said: ${utf8.decode(response.bodyBytes)}');
      response = await _postCompletion(
        httpClient,
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        count: count,
        jsonMode: false,
      );
    }

    final raw = utf8.decode(response.bodyBytes);
    _log(
      'HTTP ${response.statusCode} in ${stopwatch.elapsedMilliseconds} ms, '
      '${raw.length} bytes',
    );

    if (response.statusCode != 200) {
      _log('Body: $raw');
      throw http.ClientException(
        'Word generation failed with ${response.statusCode}',
        endpoint,
      );
    }

    return _parseReply(raw);
  } finally {
    // Only close a client this function created.
    if (client == null) httpClient.close();
  }
}

/// Posts one chat-completion request.
///
/// [jsonMode] adds `response_format`, which some models reject.
Future<http.Response> _postCompletion(
  http.Client httpClient, {
  required Uri endpoint,
  required String apiKey,
  required String model,
  required int count,
  required bool jsonMode,
}) => httpClient.post(
  endpoint,
  headers: {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json; charset=utf-8',
  },
  // Encode to bytes rather than passing a String: the Cyrillic prompt
  // must go out as UTF-8 regardless of the client's default codec.
  body: utf8.encode(
    jsonEncode({
      'model': model,
      'max_tokens': _maxTokens,
      if (jsonMode) 'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': 'Выдай $count слов.'},
      ],
    }),
  ),
);

/// Digs the word list out of a completion envelope, narrating as it goes.
Set<String> _parseReply(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (error) {
    _log('Reply is not JSON at all: $error');
    _log('Body: $raw');
    throw FormatException('Completion envelope was not JSON', raw);
  }

  if (decoded is! Map<String, Object?>) {
    _log('Body: $raw');
    throw FormatException('Completion envelope was not an object', raw);
  }

  // Gateways report quota and routing problems in an `error` object, with
  // HTTP 200 on the response itself.
  if (decoded['error'] case final Object error) {
    _log('Gateway returned an error object: ${jsonEncode(error)}');
    throw http.ClientException('Word generation failed: $error');
  }

  if (decoded['usage'] case final Map<String, Object?> usage) {
    _log('usage: ${jsonEncode(usage)}');
  }

  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty) {
    _log('No choices in the reply.');
    _log('Body: $raw');
    throw FormatException('Completion had no choices', raw);
  }

  final choice = choices.first;
  if (choice is! Map<String, Object?>) {
    _log('Body: $raw');
    throw FormatException('Completion choice was not an object', raw);
  }

  final finishReason =
      choice['finish_reason'] ?? choice['native_finish_reason'];
  _log('finish_reason=$finishReason');
  if (finishReason == 'length') {
    _log(
      'The model hit max_tokens. Lower AI_WORD_COUNT, or pick a model that '
      'does not spend the whole budget on reasoning.',
    );
  }

  final message = choice['message'];
  if (message is! Map<String, Object?>) {
    _log('Body: $raw');
    throw FormatException('Completion had no message', raw);
  }

  if (message['refusal'] case final Object refusal) {
    _log('Model refused: $refusal');
  }

  var text = switch (message['content']) {
    final String content => content,
    // Some gateways return content as an array of parts.
    final List<Object?> parts => parts
        .map(
          (part) => switch (part) {
            {'text': final String text} => text,
            final String text => text,
            _ => '',
          },
        )
        .join(),
    _ => '',
  };

  if (text.trim().isEmpty) {
    _log('message.content is empty.');
    // Reasoning models sometimes leave content blank and put everything in a
    // reasoning field; the words may still be in there.
    if (message['reasoning'] case final String reasoning
        when reasoning.trim().isNotEmpty) {
      _log('Falling back to message.reasoning (${reasoning.length} chars).');
      text = reasoning;
    } else {
      _log('Nothing to parse. Body: $raw');
      return const {};
    }
  }

  _log('reply (${text.length} chars): ${_excerpt(text)}');
  return _extractWords(text);
}

/// Pulls candidate words out of the model's reply text.
///
/// Tries the requested JSON first, then falls back to scanning the raw text,
/// which covers models that wrap JSON in prose or ignore `response_format`.
Set<String> _extractWords(String content) {
  final candidates = <String>[];
  var how = 'text scan';

  try {
    final json = jsonDecode(content);
    if (json case {'words': final List<Object?> words}) {
      candidates.addAll(words.whereType<String>());
      how = 'JSON field "words"';
    } else if (json is List) {
      candidates.addAll(json.whereType<String>());
      how = 'bare JSON array';
    } else {
      _log('Reply was JSON but held no word list.');
    }
  } on FormatException {
    _log('Reply text is not JSON; scanning it as prose instead.');
  }

  if (candidates.isEmpty) {
    // Split into maximal runs of Cyrillic letters and keep whole five-letter
    // runs. Matching a five-letter pattern instead would slice a longer word
    // such as "Надеюсь" into "надею".
    candidates.addAll(
      content.split(RegExp('[^а-яёА-ЯЁ]+')).where((word) => word.length == 5),
    );
    how = 'text scan';
  }

  final accepted = <String>{};
  final rejected = <String>[];
  for (final candidate in candidates) {
    if (isFiveLetterRussianWord(candidate)) {
      accepted.add(normalizeWord(candidate));
    } else {
      rejected.add(candidate);
    }
  }

  _log('extracted ${candidates.length} candidates via $how');
  _log('${accepted.length} of them look like five-letter Russian words');
  if (rejected.isNotEmpty) {
    _log('wrong shape (${rejected.length}): ${_excerpt(rejected.join(", "))}');
  }
  return accepted;
}

/// Flattens [text] to one line and caps it, so a log line stays readable.
String _excerpt(String text) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= _logExcerpt
      ? flat
      : '${flat.substring(0, _logExcerpt)}… (+${flat.length - _logExcerpt} chars)';
}
