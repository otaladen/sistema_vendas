import 'dart:convert';

import 'package:shelf/shelf.dart';

Response lanApiJson(Object body, {int status = 200}) {
  return Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );
}

Future<Map<String, dynamic>?> lanApiReadJsonMap(Request request) async {
  try {
    final raw = jsonDecode(await request.readAsString());
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  } catch (_) {
    return null;
  }
}

int lanApiQueryInt(Request request, String key, {int fallback = 0}) =>
    int.tryParse(request.url.queryParameters[key] ?? '') ?? fallback;

DateTime? lanApiQueryDate(Request request, String key) {
  final s = (request.url.queryParameters[key] ?? '').trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toUtc();
}
