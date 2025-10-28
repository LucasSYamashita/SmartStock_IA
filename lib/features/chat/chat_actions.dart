import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smartstock_flutter_only/data/datasources/product_service.dart';

enum ChatIntentType {
  createProduct,
  updatePrice,
  updateMin,
  adjustPlus, // entrada
  adjustMinus, // saída
  deleteProduct,
  unknown
}

class ChatIntent {
  final ChatIntentType type;
  final String? nome; // “arroz”
  final double? preco; // 12.50
  final int? quantidade; // 5 (ajuste)
  final int? minimo; // 3
  ChatIntent({
    required this.type,
    this.nome,
    this.preco,
    this.quantidade,
    this.minimo,
  });
}

class ChatActions {
  /// Regras simples (regex) para PT-BR
  static ChatIntent parse(String text) {
    final t = text.toLowerCase().trim();

    // criar produto
    // “crie produto arroz com preço 12 e quantidade 5 (min 2)”
    final regCreate = RegExp(
      r'(cria|crie|cadastrar|novo).*(produto|item)\s+([a-z0-9\s\-_.]+).*?(pre(ço|co)\s*([0-9]+([.,][0-9]+)?))?.*?(qtd|quantidade)\s*([0-9]+)?(?:.*?min(?:imo)?\s*([0-9]+))?',
    );
    final mC = regCreate.firstMatch(t);
    if (mC != null) {
      final nome = mC.group(3)?.trim();
      final precoStr = mC.group(6) ?? '0';
      final qtdStr = mC.group(9) ?? '0';
      final minStr = mC.group(11) ?? '0';
      return ChatIntent(
        type: ChatIntentType.createProduct,
        nome: nome?.isEmpty == true ? null : nome,
        preco: double.tryParse(precoStr.replaceAll(',', '.')) ?? 0,
        quantidade: int.tryParse(qtdStr) ?? 0,
        minimo: int.tryParse(minStr) ?? 0,
      );
    }

    // atualizar preço
    // “mude o preço do arroz para 10,50”
    final regPrice = RegExp(
        r'(pre(ço|co).*(de|do)\s+([a-z0-9\s\-_.]+).*(para|pra)\s*([0-9]+([.,][0-9]+)?))');
    final mP = regPrice.firstMatch(t);
    if (mP != null) {
      final nome = mP.group(4)?.trim();
      final precoStr = (mP.group(6) ?? '0').replaceAll(',', '.');
      return ChatIntent(
        type: ChatIntentType.updatePrice,
        nome: nome,
        preco: double.tryParse(precoStr) ?? 0,
      );
    }

    // atualizar mínimo
    // “defina mínimo do arroz para 3”
    final regMin = RegExp(
        r'(min(imo)?).*(de|do)\s+([a-z0-9\s\-_.]+).*(para|pra)\s*([0-9]+)');
    final mM = regMin.firstMatch(t);
    if (mM != null) {
      final nome = mM.group(4)?.trim();
      final min = int.tryParse(mM.group(6) ?? '0') ?? 0;
      return ChatIntent(
          type: ChatIntentType.updateMin, nome: nome, minimo: min);
    }

    // entrada / saída
    // “adicione 5 no arroz”, “retire 2 do arroz”
    final regPlus = RegExp(
        r'(adiciona|entrada|soma|compr(a|e)).*?([0-9]+).*?(no|no\s+produto|em)\s+([a-z0-9\s\-_.]+)');
    final mPlus = regPlus.firstMatch(t);
    if (mPlus != null) {
      return ChatIntent(
        type: ChatIntentType.adjustPlus,
        quantidade: int.tryParse(mPlus.group(3) ?? '0') ?? 0,
        nome: mPlus.group(5)?.trim(),
      );
    }
    final regMinus = RegExp(
        r'(retira|baixa|vende|sa(í|i)da).*?([0-9]+).*?(do|do\s+produto)\s+([a-z0-9\s\-_.]+)');
    final mMinus = regMinus.firstMatch(t);
    if (mMinus != null) {
      return ChatIntent(
        type: ChatIntentType.adjustMinus,
        quantidade: int.tryParse(mMinus.group(3) ?? '0') ?? 0,
        nome: mMinus.group(5)?.trim(),
      );
    }

    // excluir
    final regDel =
        RegExp(r'(exclui|apaga|deleta).*(produto|item)\s+([a-z0-9\s\-_.]+)');
    final mD = regDel.firstMatch(t);
    if (mD != null) {
      return ChatIntent(
        type: ChatIntentType.deleteProduct,
        nome: mD.group(3)?.trim(),
      );
    }

    return ChatIntent(type: ChatIntentType.unknown);
  }

  /// Executa a intenção
  static Future<String> act({
    required String tenantId,
    required ChatIntent intent,
  }) async {
    try {
      switch (intent.type) {
        case ChatIntentType.createProduct:
          if ((intent.nome ?? '').isEmpty) {
            return 'Preciso do nome do produto para criar.';
          }
          final id = await ProductService.createProduct(
            tenantId: tenantId,
            nome: intent.nome!,
            preco: intent.preco ?? 0,
            quantidade: intent.quantidade ?? 0,
            estoqueMinimo: intent.minimo ?? 0,
          );
          return 'Produto “${intent.nome}” criado (id $id).';

        case ChatIntentType.updatePrice:
          final pid = await _requireProductId(tenantId, intent.nome);
          await ProductService.updateProductFields(
            tenantId: tenantId,
            productId: pid,
            data: {'preco': intent.preco ?? 0},
          );
          return 'Preço de “${intent.nome}” atualizado para R\$ ${(intent.preco ?? 0).toStringAsFixed(2)}.';

        case ChatIntentType.updateMin:
          final pid2 = await _requireProductId(tenantId, intent.nome);
          await ProductService.updateProductFields(
            tenantId: tenantId,
            productId: pid2,
            data: {'estoqueMinimo': intent.minimo ?? 0},
          );
          return 'Estoque mínimo de “${intent.nome}” agora é ${(intent.minimo ?? 0)}.';

        case ChatIntentType.adjustPlus:
        case ChatIntentType.adjustMinus:
          final pid3 = await _requireProductId(tenantId, intent.nome);
          final delta = (intent.quantidade ?? 0) *
              (intent.type == ChatIntentType.adjustMinus ? -1 : 1);
          await ProductService.adjustQuantityWithLog(
            tenantId: tenantId,
            productId: pid3,
            produtoNome: intent.nome ?? '',
            delta: delta,
            origem: 'chat_adjust',
            motivo: intent.type == ChatIntentType.adjustMinus
                ? 'saída (chat)'
                : 'entrada (chat)',
          );
          return 'Movimentação feita: ${intent.type == ChatIntentType.adjustMinus ? 'saída' : 'entrada'} de ${intent.quantidade ?? 0} em “${intent.nome}”.';

        case ChatIntentType.deleteProduct:
          final pid4 = await _requireProductId(tenantId, intent.nome);
          await ProductService.deleteProduct(
              tenantId: tenantId, productId: pid4);
          return 'Produto “${intent.nome}” excluído.';

        case ChatIntentType.unknown:
          return 'Não entendi. Exemplos: “crie produto arroz preço 12 quantidade 5”, “mude o preço do arroz para 9,99”, “adicione 3 no arroz”, “retire 1 do arroz”, “defina mínimo do arroz para 2”.';
      }
    } on FirebaseException catch (e) {
      return 'Falhou (firebase): ${e.code} – ${e.message}';
    } catch (e) {
      return 'Erro: $e';
    }
  }

  static Future<String> _requireProductId(String tenantId, String? nome) async {
    if ((nome ?? '').isEmpty) throw Exception('Informe o nome do produto.');
    final pid = await ProductService.findProductIdByName(
        tenantId: tenantId, nome: nome!);
    if (pid == null) throw Exception('Produto “$nome” não encontrado.');
    return pid;
  }
}
