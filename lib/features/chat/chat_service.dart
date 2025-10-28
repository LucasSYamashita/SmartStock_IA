import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  final _functions =
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  /// Faz 2 chamadas: dryRun (parse) -> execute (confirm).
  Future<List<String>> actStepwise({
    required String tenantId,
    required String role, // 'admin' | 'staff' | 'viewer'
    required String text,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw Exception('[unauthenticated] Faça login para usar o chat.');
    }
    if (tenantId.isEmpty) {
      throw Exception('[invalid-argument] Selecione/Crie uma loja (tenant).');
    }

    final callable = _functions.httpsCallable('actCall');

    Map<String, dynamic> _payload(bool dryRun, bool confirm) => {
          'tenantId': tenantId,
          'role': role,
          'dryRun': dryRun,
          'confirm': confirm,
          'createIfMissing': true,
          'messages': [
            {'role': 'user', 'content': text}
          ],
          'system': 'Interprete e execute ações de estoque com segurança.',
        };

    try {
      // 1) interpretação
      final r1 = await callable.call(_payload(true, false));
      final d1 = (r1.data as Map?) ?? {};
      final parsed = d1['parsed'];
      final assist = (d1['assistant_text'] as String?)?.trim() ??
          'Interpretei seu pedido.';

      if (parsed == null) {
        throw Exception(
            '[invalid-argument] Interpretação incompleta pelo parser.');
      }

      // 2) execução
      final r2 = await callable.call(_payload(false, true));
      final d2 = (r2.data as Map?) ?? {};
      final msg = (d2['assistant_text'] as String?)?.trim() ??
          (d2['result']?['message'] as String?)?.trim() ??
          'OK';

      return [assist, msg];
    } on FirebaseFunctionsException catch (e) {
      final code = e.code.isNotEmpty ? e.code : 'internal';
      final msg = e.message ?? 'Falha na função.';
      final det = e.details != null ? ' (${e.details})' : '';
      throw Exception('[$code] $msg$det');
    } catch (e) {
      throw Exception('Falha: $e');
    }
  }
}
