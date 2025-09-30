// lib/data/models/product.dart
class Product {
  final String id;
  final String nome;
  final String categoria; // sempre string (não-nula)
  final String? sku;
  final double preco;
  final int quantidade;
  final int estoqueMinimo;
  final bool ativo;

  const Product({
    required this.id,
    required this.nome,
    required this.categoria,
    this.sku,
    required this.preco,
    required this.quantidade,
    required this.estoqueMinimo,
    required this.ativo,
  });

  Product copyWith({
    String? id,
    String? nome,
    String? categoria,
    String? sku,
    double? preco,
    int? quantidade,
    int? estoqueMinimo,
    bool? ativo,
  }) {
    return Product(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      categoria: (categoria ?? this.categoria),
      sku: sku ?? this.sku,
      preco: preco ?? this.preco,
      quantidade: quantidade ?? this.quantidade,
      estoqueMinimo: estoqueMinimo ?? this.estoqueMinimo,
      ativo: ativo ?? this.ativo,
    );
  }

  /// Constrói a partir do Firestore (map cru)
  static Product fromFirestore(String id, Map<String, dynamic> data) {
    final precoAny = data['preco'];
    final quantidadeAny = data['quantidade'];
    final minimoAny = data['estoqueMinimo'];

    return Product(
      id: id,
      nome: (data['nome'] ?? data['Nome'] ?? '').toString(),
      categoria: (data['categoria'] ?? data['Categoria'] ?? '').toString(),
      sku: (data['sku'] ?? data['SKU'])?.toString(),
      preco: precoAny is num
          ? precoAny.toDouble()
          : double.tryParse('$precoAny') ?? 0.0,
      quantidade: quantidadeAny is num
          ? quantidadeAny.toInt()
          : int.tryParse('$quantidadeAny') ?? 0,
      estoqueMinimo: minimoAny is num
          ? minimoAny.toInt()
          : int.tryParse('$minimoAny') ?? 0,
      ativo: data['ativo'] is bool ? data['ativo'] as bool : true,
    );
  }

  /// Alias esperado por algumas telas: Product.fromMap(doc.id, doc.data())
  static Product fromMap(String id, Map<String, dynamic> data) =>
      fromFirestore(id, data);

  Map<String, dynamic> toFirestore({
    String? uid,
    bool includeAuditCreate = false,
    bool includeAuditUpdate = false,
  }) {
    final map = <String, dynamic>{
      'nome': nome,
      'nomeLower': nome.toLowerCase(),
      'categoria': categoria,
      'sku': sku ?? '',
      'preco': preco,
      'quantidade': quantidade,
      'estoqueMinimo': estoqueMinimo,
      'ativo': ativo,
    };
    if (includeAuditCreate) {
      map['createdBy'] = uid;
      // createdAt será setado como FieldValue.serverTimestamp() no datasource
    }
    if (includeAuditUpdate) {
      map['updatedBy'] = uid;
      // updatedAt também será setado no datasource
    }
    return map;
  }
}
