import 'package:cloud_firestore/cloud_firestore.dart';

/// Movimentações de estoque (entrada/saída/ajuste) + atualização de produto.
///
/// Campos compatíveis com versões antigas:
/// - `preco`       → preço unitário (histórico)
/// - `valorTotal`  → total da linha (histórico)
///
/// Novos campos:
/// - `unitCost`    → custo unitário (para entradas)
/// - `unitPrice`   → preço de venda unitário (para saídas)
/// - `totalValue`  → total da linha (entrada ou saída)
class FirestoreMovements {
  final FirebaseFirestore db;
  final String tenantId;

  const FirestoreMovements(this.db, this.tenantId);

  CollectionReference<Map<String, dynamic>> get _prodCol =>
      db.collection('tenants').doc(tenantId).collection('produtos');

  CollectionReference<Map<String, dynamic>> get _movCol =>
      db.collection('tenants').doc(tenantId).collection('movimentos');

  DocumentReference<Map<String, dynamic>> _prodRef(String id) =>
      _prodCol.doc(id);

  /// Aplica uma movimentação de estoque + registra documento em `movimentos`.
  ///
  /// - [tipo]: 'entrada' | 'saida' | 'ajuste'
  /// - [preco]: para SAÍDA, é o preço unitário de venda (se não vier, usa o do produto)
  /// - [custo]: para ENTRADA, custo unitário (opcional)
  ///
  /// Sempre preenche:
  /// - `preco` (unitário)
  /// - `valorTotal` (total da linha)
  /// - `unitCost` / `unitPrice` / `totalValue` (novos campos)
  Future<void> applyMovement({
    required String produtoId,
    required String tipo, // 'entrada' | 'saida' | 'ajuste'
    required int quantidade,
    String? motivo,
    String? usuarioId,
    String? origem,
    String? mensagemOriginal,
    String? paymentMethod,
    String? paymentNote,
    double? preco, // unitário (principal para SAÍDA)
    double? custo, // custo unitário (principal para ENTRADA)
    bool allowNegative = false,
  }) async {
    assert(quantidade > 0, 'Quantidade deve ser > 0');

    final prodRef = _prodRef(produtoId);
    final movRef = _movCol.doc();

    await db.runTransaction((tx) async {
      final snap = await tx.get(prodRef);
      if (!snap.exists) {
        throw StateError('Produto $produtoId não encontrado.');
      }

      final data = snap.data()!;
      final nomeProduto = (data['nome'] ?? produtoId).toString();

      final atualAny = data['quantidade'] ?? 0;
      final atual =
          atualAny is num ? atualAny.toInt() : int.tryParse('$atualAny') ?? 0;

      int novoEstoque = atual;
      int delta = 0;

      switch (tipo) {
        case 'entrada':
          delta = quantidade;
          novoEstoque = atual + quantidade;
          break;
        case 'saida':
          delta = -quantidade;
          novoEstoque = atual - quantidade;
          break;
        case 'ajuste':
          // ajuste positivo ou negativo: quantidade vira delta "bruto"
          // aqui usamos quantidade como DELTA (pode ser negativo via allowNegative)
          delta = quantidade;
          novoEstoque = atual + quantidade;
          break;
        default:
          throw ArgumentError('tipo inválido: $tipo');
      }

      if (!allowNegative && novoEstoque < 0) {
        throw StateError(
          'Estoque insuficiente para $nomeProduto (atual: $atual, tentado: $quantidade).',
        );
      }

      // ==== definição de preço/custo ====
      // preço/custo baseados no produto
      double? prodPreco;
      final pAny = data['preco'] ?? data['precoVenda'] ?? data['valor'];
      if (pAny is num) {
        prodPreco = pAny.toDouble();
      } else {
        prodPreco = double.tryParse('$pAny');
      }

      double? unitCost;
      double? unitPrice;

      if (tipo == 'entrada') {
        // entrada: custo unitário principal
        unitCost = custo ?? preco ?? prodPreco ?? 0.0;
      } else if (tipo == 'saida') {
        // saída: preço unitário principal
        unitPrice = preco ?? prodPreco ?? 0.0;
      } else {
        // ajuste: se for negativo, tratamos como saída; se positivo, como entrada
        if (delta < 0) {
          unitPrice = preco ?? prodPreco ?? 0.0;
        } else if (delta > 0) {
          unitCost = custo ?? preco ?? prodPreco ?? 0.0;
        }
      }

      // total da linha (preferindo unitPrice ou unitCost conforme o caso)
      final baseUnit =
          unitPrice ?? unitCost ?? prodPreco ?? 0.0; // fallback defensivo
      final totalValue = baseUnit * quantidade;

      // ==== atualiza produto ====
      final updateProd = <String, dynamic>{
        'quantidade': novoEstoque,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (usuarioId != null) updateProd['updatedBy'] = usuarioId;

      // se recebemos um preço de venda explícito numa saída,
      // atualiza também o preço do produto (ajuda no saldo em estoque).
      if (tipo == 'saida' && unitPrice != null) {
        updateProd['preco'] = unitPrice;
      }

      tx.update(prodRef, updateProd);

      // ==== registra movimento ====
      final movimento = <String, dynamic>{
        'tipo': tipo,
        'produtoId': produtoId,
        'produtoNome': nomeProduto,
        'quantidade': quantidade,
        'tenantId': tenantId,
        'usuarioId': usuarioId,
        'origem': origem ?? 'manual',
        'motivo': motivo ?? _motivoPadrao(tipo),
        'createdAt': FieldValue.serverTimestamp(),
        if (mensagemOriginal != null && mensagemOriginal.isNotEmpty)
          'mensagemOriginal': mensagemOriginal,
        if (paymentMethod != null && paymentMethod.isNotEmpty)
          'paymentMethod': paymentMethod,
        if (paymentNote != null && paymentNote.isNotEmpty)
          'paymentNote': paymentNote,
      };

      // campos novos
      if (unitCost != null) movimento['unitCost'] = unitCost;
      if (unitPrice != null) movimento['unitPrice'] = unitPrice;
      movimento['totalValue'] = totalValue;

      // compat Legado: sempre salva `preco` e `valorTotal`
      final legacyUnit = unitPrice ?? unitCost ?? prodPreco ?? 0.0;
      movimento['preco'] = legacyUnit;
      movimento['valorTotal'] = totalValue;

      tx.set(movRef, movimento);
    });
  }

  String _motivoPadrao(String tipo) {
    switch (tipo) {
      case 'entrada':
        return 'entrada manual';
      case 'saida':
        return 'venda manual';
      case 'ajuste':
        return 'ajuste de estoque';
      default:
        return 'movimentação';
    }
  }
}
