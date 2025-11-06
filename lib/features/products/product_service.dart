import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProductService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Usa em “Editar produto” (salva TODO o doc exigido pelas rules)
  static Future<void> salvarEdicaoProduto({
    required String tenantId,
    required String produtoId,
    required String nome,
    String categoria = '',
    String sku = '',
    double? preco, // opcional (se já existe algum preço no doc, pode omitir)
    required int quantidade, // valor final
    required int estoqueMinimo,
    required bool ativo,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Faça login para editar produtos.');
    final pRef = _db
        .collection('tenants')
        .doc(tenantId)
        .collection('produtos')
        .doc(produtoId);
    final mCol =
        _db.collection('tenants').doc(tenantId).collection('movimentos');

    await _db.runTransaction((tx) async {
      final snap = await tx.get(pRef);
      if (!snap.exists) throw Exception('Produto não encontrado.');
      final atual = snap.data() as Map<String, dynamic>;
      final antes = (atual['quantidade'] ?? 0) as int;
      final depois = quantidade;
      final delta = depois - antes;

      // UPDATE com todos os campos que as rules exigem
      final update = <String, dynamic>{
        'nome': nome,
        'nomeLower': nome.toLowerCase(),
        'categoria': categoria,
        'sku': sku,
        if (preco != null)
          'preco': preco, // Pode não mandar se já tem algum preço no doc
        'quantidade': max(0, depois),
        'estoqueMinimo': max(0, estoqueMinimo),
        'ativo': ativo,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      };
      tx.update(pRef, update);

      // Se mudou quantidade → registrar movimento
      if (delta != 0) {
        tx.set(mCol.doc(), {
          'tipo': delta > 0 ? 'entrada' : 'saida',
          'quantidade': delta.abs(),
          'produtoId': produtoId,
          'produtoNome': nome,
          'usuarioId': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'motivo': 'ajuste_por_edicao',
          'origem': 'product_edit',
          'snapshot': {'antes': antes, 'depois': depois},
          if (preco != null) 'preco': preco,
        });
      }
    });
  }

  /// Usa na telinha “Registrar entrada” do produto (apenas delta positivo).
  static Future<void> registrarEntradaNoProduto({
    required String tenantId,
    required String produtoId,
    required int quantidade, // delta > 0
    double? custoUnitario, // opcional: salva em 'preco' no movimento
    String motivo = 'entrada_manual',
  }) async {
    if (quantidade <= 0) throw Exception('Quantidade deve ser > 0.');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Faça login para registrar entrada.');

    final pRef = _db
        .collection('tenants')
        .doc(tenantId)
        .collection('produtos')
        .doc(produtoId);
    final mCol =
        _db.collection('tenants').doc(tenantId).collection('movimentos');

    await _db.runTransaction((tx) async {
      final snap = await tx.get(pRef);
      if (!snap.exists) throw Exception('Produto não encontrado.');
      final atual = snap.data() as Map<String, dynamic>;

      final nome = (atual['nome'] ?? '').toString();
      final antes = (atual['quantidade'] ?? 0) as int;
      final depois = antes + quantidade;

      // Prepara UPDATE com todos os campos obrigatórios das rules
      final update = <String, dynamic>{
        'nome': nome,
        'nomeLower': nome.toLowerCase(),
        'categoria': (atual['categoria'] ?? '').toString(),
        'sku': (atual['sku'] ?? '').toString(),
        // mantemos algum preço se já existir no doc (não obrigatório mandar)
        if (atual.containsKey('preco')) 'preco': atual['preco'],
        if (atual.containsKey('valor')) 'valor': atual['valor'],
        if (atual.containsKey('precoVenda')) 'precoVenda': atual['precoVenda'],
        'quantidade': max(0, depois),
        'estoqueMinimo': (atual['estoqueMinimo'] ?? 0) as int,
        'ativo': (atual['ativo'] is bool) ? atual['ativo'] as bool : true,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      };
      tx.update(pRef, update);

      // Movimento que passa nas rules
      tx.set(mCol.doc(), {
        'tipo': 'entrada',
        'quantidade': quantidade,
        'produtoId': produtoId,
        'produtoNome': nome,
        'usuarioId': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'motivo': motivo,
        'origem': 'quick_entry',
        'snapshot': {'antes': antes, 'depois': depois},
        if (custoUnitario != null) 'preco': custoUnitario,
      });
    });
  }
}
