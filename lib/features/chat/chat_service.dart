// lib/features/chat/chat_service.dart
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';

class ActReply {
  final String requestId;
  final bool ok;
  final String message;

  ActReply({required this.requestId, required this.ok, required this.message});
}

class ChatService {
  final FirebaseFunctions _fx;

  ChatService({FirebaseFunctions? functions, String region = 'us-central1'})
      : _fx = (functions ?? FirebaseFunctions.instanceFor(region: region));

  Future<ActReply> send({
    required String tenantId,
    required String role,
    required String text,
    String? requestId,
  }) async {
    final callable = _fx.httpsCallable('actCall');
    final payload = {
      'requestId': requestId ?? _makeRequestId(),
      'tenantId': tenantId,
      'role': role,
      'text': text,
    };
    final res = await callable.call(payload);
    final data = Map<String, dynamic>.from(res.data as Map);
    return ActReply(
      requestId: data['requestId']?.toString() ?? '',
      ok: data['ok'] == true,
      message: data['message']?.toString() ?? 'Sem mensagem',
    );
  }
}

String _makeRequestId() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rnd = Random.secure();
  return List.generate(10, (_) => chars[rnd.nextInt(chars.length)]).join();
}
