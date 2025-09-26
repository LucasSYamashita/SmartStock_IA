// lib/services/cloud_functions.dart
//
// Wrapper para chamar Cloud Functions (HTTPS Callable) com
// configuração de região, emulador em debug e tratamento de erros.
//
// Dep.: cloud_functions ^5.x
// import no código:  import 'package:smartstock/services/cloud_functions.dart';

import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:cloud_functions/cloud_functions.dart';

/// Região padrão do seu projeto (ajuste se necessário)
const _kRegion = 'us-central1';

/// Singleton simples para centralizar as chamadas às functions.
class AppFunctions {
  AppFunctions._();

  static final AppFunctions _i = AppFunctions._();
  static AppFunctions get I => _i;

  FirebaseFunctions get _fx {
    // instancia com região
    final inst = FirebaseFunctions.instanceFor(region: _kRegion);

    // Opcional: apontar para o emulador em debug
    // Ajuste a porta conforme o seu setup do emulador.
    if (kDebugMode) {
      // chame apenas uma vez; o plugin já evita reconfigurar repetidamente.
      inst.useFunctionsEmulator('localhost', 5001);
    }
    return inst;
  }

  /// Helper: chama uma function por nome com [data] e devolve o "result"
  Future<T> _call<T>(String name, Map<String, dynamic> data) async {
    try {
      final callable = _fx.httpsCallable(name);
      final resp = await callable.call<Map<String, dynamic>>(data);
      final res = resp.data;

      if (res == null) {
        throw Exception('Função "$name" retornou vazio.');
      }

      // Se você padronizar { ok: bool, data: any, error: string },
      // pode validar aqui:
      if (res is Map && res['ok'] == false) {
        throw Exception(res['error']?.toString() ?? 'Falha desconhecida');
      }

      // Caso o backend retorne diretamente o payload final:
      return (res['data'] ?? res) as T;
    } on FirebaseFunctionsException catch (e) {
      // Erros lançados pela Cloud Function (com code / details)
      final msg =
          e.details is String ? e.details as String : (e.message ?? e.code);
      throw Exception('($_kRegion/$name) $msg');
    } catch (e) {
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Abaixo estão *sugestões* de endpoints callable.
  // Ajuste os nomes para baterem com as suas funções no backend (index.ts/js).
  // ---------------------------------------------------------------------------

  /// Cria uma nova loja (tenant) e já faz o caller **admin**.
  /// Backend sugerido: exports.createTenant = onCall(...)
  Future<Map<String, dynamic>> createTenant({
    required String name,
  }) async {
    return _call<Map<String, dynamic>>('createTenant', {
      'name': name,
    });
  }

  /// Regenera o 'code' da loja (apenas **admin**).
  /// Backend: exports.regenerateTenantCode = onCall(...)
  Future<String> regenerateTenantCode({
    required String tenantId,
  }) async {
    final res = await _call<Map<String, dynamic>>('regenerateTenantCode', {
      'tenantId': tenantId,
    });
    // Supondo que o backend retorna { code: 'ABC123' }
    return res['code']?.toString() ?? '';
  }

  /// Adiciona/atualiza um membro (útil para promover/demitir/ativar/desativar).
  /// Backend: exports.setMember = onCall(...)
  Future<void> setMember({
    required String tenantId,
    required String userId,
    required String role, // 'admin' | 'staff' | 'viewer'
    bool? active,
  }) async {
    await _call<Map<String, dynamic>>('setMember', {
      'tenantId': tenantId,
      'userId': userId,
      'role': role,
      if (active != null) 'active': active,
    });
  }

  /// Finaliza/lança uma venda (e opcionalmente desconta o estoque).
  /// Backend: exports.finalizeSale = onCall(...)
  Future<Map<String, dynamic>> finalizeSale({
    required String tenantId,
    required List<Map<String, dynamic>>
        itens, // [{produtoId, nome, qtd, preco}]
    required num subtotal,
    required num total,
    String? pagamento,
    bool descontarEstoque = true,
  }) async {
    return _call<Map<String, dynamic>>('finalizeSale', {
      'tenantId': tenantId,
      'itens': itens,
      'subtotal': subtotal,
      'total': total,
      'pagamento': pagamento,
      'descontarEstoque': descontarEstoque,
    });
  }

  /// Movimentação via Function (opcional; você já tem via Firestore transaction).
  /// Útil se preferir centralizar regras no backend.
  /// Backend: exports.applyMovement = onCall(...)
  Future<void> applyMovement({
    required String tenantId,
    required String produtoId,
    required String tipo, // 'entrada' | 'saida' | 'ajuste'
    required int quantidade,
    String? motivo,
    String origem = 'chatbot',
    String? mensagemOriginal,
  }) async {
    await _call<Map<String, dynamic>>('applyMovement', {
      'tenantId': tenantId,
      'produtoId': produtoId,
      'tipo': tipo,
      'quantidade': quantidade,
      'motivo': motivo,
      'origem': origem,
      'mensagemOriginal': mensagemOriginal,
    });
  }

  /// Cria produto (opcional via Function).
  /// Backend: exports.createProduct = onCall(...)
  Future<String> createProduct({
    required String tenantId,
    required String nome,
    String? categoria,
    String? sku,
    num preco = 0,
    int quantidade = 0,
    int estoqueMinimo = 0,
    bool ativo = true,
  }) async {
    final res = await _call<Map<String, dynamic>>('createProduct', {
      'tenantId': tenantId,
      'nome': nome,
      'categoria': categoria,
      'sku': sku,
      'preco': preco,
      'quantidade': quantidade,
      'estoqueMinimo': estoqueMinimo,
      'ativo': ativo,
    });
    // Supondo que o backend retorna { id: '...' }
    return res['id']?.toString() ?? '';
  }

  /// Atualiza produto (opcional via Function).
  /// Backend: exports.updateProduct = onCall(...)
  Future<void> updateProduct({
    required String tenantId,
    required String productId,
    Map<String, dynamic>? data,
  }) async {
    await _call<Map<String, dynamic>>('updateProduct', {
      'tenantId': tenantId,
      'productId': productId,
      'data': data ?? {},
    });
  }
}
