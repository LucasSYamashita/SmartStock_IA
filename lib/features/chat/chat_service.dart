// lib/features/chat/chat_service.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../tenant/tenant_provider.dart';
import '../tenant/role_providers.dart';

class ChatService {
  final Ref ref;
  const ChatService(this.ref);

  String get _baseUrl => const String.fromEnvironment('SMARTSTOCK_FUNC_BASE',
      defaultValue:
          'https://southamerica-east1-smartstock-ae7ad.cloudfunctions.net');

  Future<String> chatOnce({required List<Map<String, String>> history}) async {
    final tenantId = ref.read(tenantIdProvider) ?? 'TENANT01';
    final role = ref.read(effectiveRoleProvider(tenantId));

    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'x-tenant-id': tenantId,
      'x-role': role,
      'x-uid': 'MOBILE',
    };

    final resp = await http.post(
      Uri.parse('$_baseUrl/chat?stream=false'),
      headers: headers,
      body: jsonEncode({'messages': history}),
    );

    if (resp.statusCode == 200) {
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      return (j['text'] ?? '').toString();
    }
    throw 'HTTP ${resp.statusCode}: ${resp.body}';
  }

  Stream<String> chatStream(
      {required List<Map<String, String>> history}) async* {
    final txt = await chatOnce(history: history);
    yield txt;
  }

  Future<Map<String, dynamic>> act({
    required List<Map<String, String>> messages,
    bool dryRun = true,
    bool confirm = false,
    bool createIfMissing = false,
  }) async {
    final tenantId = ref.read(tenantIdProvider) ?? 'TENANT01';
    final role = ref.read(effectiveRoleProvider(tenantId));

    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'x-tenant-id': tenantId,
      'x-role': role,
      'x-uid': 'MOBILE',
    };

    final uri = Uri.parse(
        '$_baseUrl/act?dryRun=$dryRun&confirm=$confirm&createIfMissing=$createIfMissing');

    final resp = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'messages': messages}),
    );

    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw (j['error'] ?? resp.body).toString();
    }
    return j;
  }
}
