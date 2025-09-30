// lib/data/datasources/firestore_products.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product.dart';

class FirestoreProducts {
  FirestoreProducts(this.db, this.tenantId);
  final FirebaseFirestore db;
  final String tenantId;

  CollectionReference<Map<String, dynamic>> get _col =>
      db.collection('tenants').doc(tenantId).collection('produtos');

  /// Stream de todos os produtos convertendo para Product
  Stream<List<Product>> streamAll() {
    return _col.orderBy('nomeLower').snapshots().map(
          (qs) => qs.docs
              .map((d) => Product.fromFirestore(d.id, d.data()))
              .toList(),
        );
  }

  /// Busca 1 produto por id
  Future<Product?> getById(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return Product.fromFirestore(doc.id, doc.data()!);
  }

  /// Cria produto com timestamps no servidor.
  /// Compatível com:
  ///   - createWithServerTimestamps(id: x, data: {...})
  ///   - createWithServerTimestamps(id: x, nome: ..., categoria: ..., sku: ..., preco: ..., quantidade: ..., estoqueMinimo: ..., ativo: ...)
  Future<String> createWithServerTimestamps({
    String? id,
    Map<String, dynamic>? data, // <- opcional
    String? nome,
    String? categoria,
    String? sku,
    num? preco,
    int? quantidade,
    int? estoqueMinimo,
    bool? ativo,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Usuário não autenticado');

    // Se vier 'data', usa; senão monta a partir dos campos nomeados
    final Map<String, dynamic> base = data != null
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{
            'nome': nome,
            'categoria': (categoria ?? '').toString(),
            'sku': (sku ?? '').toString(),
            'preco': preco,
            'quantidade': quantidade,
            'estoqueMinimo': estoqueMinimo,
            'ativo': ativo,
          };

    // Valida/normaliza
    final nomeFinal = (base['nome'] ?? base['Nome'] ?? '').toString().trim();
    if (nomeFinal.isEmpty) throw Exception("Campo 'nome' é obrigatório.");

    final payload = <String, dynamic>{
      'nome': nomeFinal,
      'nomeLower': nomeFinal.toLowerCase(),
      'categoria': (base['categoria'] ?? '').toString(),
      'sku': (base['sku'] ?? '').toString(),
      'preco': _toNum(base['preco'], 0).toDouble(),
      'quantidade': _toInt(base['quantidade'], 0),
      'estoqueMinimo': _toInt(base['estoqueMinimo'], 0),
      'ativo': (base['ativo'] is bool)
          ? base['ativo'] as bool
          : (base['ativo']?.toString().toLowerCase() == 'true'),
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (id != null && id.isNotEmpty) {
      await _col.doc(id).set(payload);
      return id;
    } else {
      final ref = await _col.add(payload);
      return ref.id;
    }
  }

  /// Atualiza produto com updatedAt/updatedBy
  Future<void> updateWithServerTimestamp({
    required String id,
    required Map<String, dynamic> data,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Usuário não autenticado');

    final update = Map<String, dynamic>.from(data);

    // Se mudar nome, atualiza nomeLower
    if (update.containsKey('nome')) {
      final nome = (update['nome'] ?? '').toString().trim();
      if (nome.isEmpty) throw Exception("Campo 'nome' não pode ficar vazio.");
      update['nome'] = nome;
      update['nomeLower'] = nome.toLowerCase();
    }

    // Normalização numérica se presente
    if (update.containsKey('preco')) {
      update['preco'] = _toNum(update['preco'], 0).toDouble();
    }
    if (update.containsKey('quantidade')) {
      update['quantidade'] = _toInt(update['quantidade'], 0);
    }
    if (update.containsKey('estoqueMinimo')) {
      update['estoqueMinimo'] = _toInt(update['estoqueMinimo'], 0);
    }
    if (update.containsKey('ativo')) {
      final v = update['ativo'];
      update['ativo'] =
          (v is bool) ? v : (v.toString().toLowerCase() == 'true');
    }

    update['updatedBy'] = uid;
    update['updatedAt'] = FieldValue.serverTimestamp();

    await _col.doc(id).update(update);
  }

  // -------- helpers --------
  num _toNum(dynamic v, num fallback) {
    if (v is num) return v;
    if (v is String) {
      final s = v.replaceAll(',', '.').trim();
      return num.tryParse(s) ?? fallback;
    }
    return fallback;
  }

  int _toInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }
}
