import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Ajuste para sua região/projeto
const _kRegion = 'southamerica-east1';
const _kProject = 'smartstock-ae7ad';
const String kFunctionsBaseUrl =
    'https://$_kRegion-$_kProject.cloudfunctions.net';

class ChatService {
  const ChatService();

  /// Chat “livre”: não mexe em estoque, só responde texto.
  Future<String> chatOnce({
    required List<Map<String, String>> history,
    String? system,
  }) async {
    final uri = Uri.parse('$kFunctionsBaseUrl/chat?stream=false');

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'messages': history,
        if (system != null) 'system': system,
      }),
    );

    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return (json['text'] ?? '').toString();
  }

  /// Stream de chat (SSE _simulado_ pelo endpoint; se não usar stream, pode remover)
  Stream<String> chatStream(
      {required List<Map<String, String>> history}) async* {
    // Mantive só como exemplo, chamando o mesmo endpoint “once”.
    // Se quiser SSE real, troque para /chat?stream=true no back e faça parsing de Server-Sent Events.
    final txt = await chatOnce(history: history);
    yield txt;
  }

  /// Interpreta e opcionalmente executa (dryRun/confirm), com tenant/role/uid nos headers
  Future<Map<String, dynamic>> act({
    required List<Map<String, String>> messages,
    required String tenantId,
    required String role,
    required String uid,
    bool dryRun = true,
    bool confirm = false,
    bool createIfMissing = false,
    String? system,
  }) async {
    final uri = Uri.parse(
      '$kFunctionsBaseUrl/act?dryRun=$dryRun&confirm=$confirm&createIfMissing=$createIfMissing',
    );

    final headers = {
      'Content-Type': 'application/json',
      'x-tenant-id': tenantId,
      'x-role': role, // "staff" | "admin" | "viewer"
      'x-uid': uid,
    };

    final resp = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'messages': messages,
        if (system != null) 'system': system,
      }),
    );

    final bodyText = resp.body;
    Map<String, dynamic> json;
    try {
      json = jsonDecode(bodyText) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('HTTP ${resp.statusCode}: $bodyText');
    }

    if (resp.statusCode != 200) {
      final err = (json['error'] ?? bodyText).toString();
      throw Exception(err);
    }
    return json;
  }
}
