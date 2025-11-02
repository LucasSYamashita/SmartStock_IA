import 'package:cloud_functions/cloud_functions.dart';

class ChatService {
  final FirebaseFunctions _func;

  ChatService({FirebaseFunctions? functions})
      : _func = functions ??
            FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  Future<Map<String, dynamic>> actCall({
    required String tenantId,
    required String role, // 'admin'/'staff'/'viewer' (só informativo)
    required List<Map<String, String>>
        messages, // [{role:'user'|'assistant', content:'...'}]
    bool dryRun = false,
  }) async {
    final callable = _func.httpsCallable('actCall');
    final resp = await callable.call(<String, dynamic>{
      'tenantId': tenantId,
      'role': role,
      'messages': messages,
      'dryRun': dryRun,
    });
    // sempre objeto JSON
    return Map<String, dynamic>.from(resp.data as Map);
  }
}
