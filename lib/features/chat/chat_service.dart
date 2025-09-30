// lib/features/chat/chat_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/env.dart';

class ChatService {
  const ChatService();

  Uri _chatUri({required bool stream}) =>
      Uri.parse('$kFunctionsBase/chat?stream=$stream');

  Uri get _actUri => Uri.parse('$kFunctionsBase/act');

  Future<String> chatOnce({
    required List<Map<String, String>> history,
    String tenantId = 'TENANT01',
    String role = 'staff',
    String uid = 'teste',
  }) async {
    final r = await http.post(
      _chatUri(stream: false),
      headers: {
        'content-type': 'application/json',
        'x-tenant-id': tenantId,
        'x-role': role,
        'x-uid': uid,
      },
      body: jsonEncode({'messages': history}),
    );
    if (r.statusCode != 200) {
      throw Exception('HTTP ${r.statusCode}: ${r.body}');
    }
    final json = jsonDecode(r.body) as Map<String, dynamic>;
    return (json['text'] ?? '').toString();
  }

  Stream<String> chatStream({
    required List<Map<String, String>> history,
    String tenantId = 'TENANT01',
    String role = 'staff',
    String uid = 'teste',
  }) async* {
    final req = http.Request('POST', _chatUri(stream: true));
    req.headers.addAll({
      'content-type': 'application/json',
      'x-tenant-id': tenantId,
      'x-role': role,
      'x-uid': uid,
    });
    req.body = jsonEncode({'messages': history});

    final resp = await req.send();
    if (resp.statusCode != 200) {
      final body = await resp.stream.bytesToString();
      throw Exception('HTTP ${resp.statusCode}: $body');
    }

    final lines =
        resp.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (line.startsWith('data: ')) {
        final payload = line.substring(6).trim();
        if (payload == '[DONE]') break;
        try {
          final json = jsonDecode(payload) as Map<String, dynamic>;
          final delta = (json['delta'] ?? '').toString();
          if (delta.isNotEmpty) yield delta;
        } catch (_) {}
      }
    }
  }

  Future<Map<String, dynamic>> act({
    required List<Map<String, String>> messages,
    String tenantId = 'TENANT01',
    String role = 'staff',
    String uid = 'teste',
  }) async {
    final r = await http.post(
      _actUri,
      headers: {
        'content-type': 'application/json',
        'x-tenant-id': tenantId,
        'x-role': role,
        'x-uid': uid,
      },
      body: jsonEncode({'messages': messages}),
    );
    final txt = r.body;
    if (r.statusCode != 200) {
      throw Exception('HTTP ${r.statusCode}: $txt');
    }
    return jsonDecode(txt) as Map<String, dynamic>;
  }
}
