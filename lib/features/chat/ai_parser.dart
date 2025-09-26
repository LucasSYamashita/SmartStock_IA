import 'package:cloud_functions/cloud_functions.dart';

class AiParsedOp {
  final String tipo; // 'entrada' | 'saida'
  final int quantidade;
  final String produtoNome;
  final String? motivo;

  AiParsedOp(
      {required this.tipo,
      required this.quantidade,
      required this.produtoNome,
      this.motivo});

  factory AiParsedOp.fromMap(Map<String, dynamic> m) => AiParsedOp(
        tipo: (m['tipo'] ?? '').toString(),
        quantidade: (m['quantidade'] as num).toInt(),
        produtoNome: (m['produtoNome'] ?? '').toString(),
        motivo: (m['motivo'] as String?),
      );
}

class AiParser {
  static final _callable =
      FirebaseFunctions.instance.httpsCallable('parseStockCommand');

  static Future<List<AiParsedOp>> parse(String text,
      {String locale = 'pt-BR'}) async {
    final res = await _callable
        .call<Map<String, dynamic>>({'text': text, 'locale': locale});
    final data = res.data;
    final list = (data['operations'] as List?) ?? const [];
    return list
        .map((e) => AiParsedOp.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
