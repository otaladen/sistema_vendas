import 'dart:convert';

import '../../model/item_venda.dart';
import '../../model/produto.dart';
import '../item_venda_produto_orfao.dart';
import '../produto_embalagem.dart';

/// Motivo de saida de carreto sem baixa/reserva de estoque.
abstract final class CarretoSaidaSemBaixaMotivo {
  CarretoSaidaSemBaixaMotivo._();

  static const produtoExcluido = 'produto_excluido';
  static const reservaInconsistente = 'reserva_inconsistente';
  static const forcaAdmin = 'forca_admin';
}

/// Linha de carreto sem baixa de estoque (orfao, reserva perdida ou forcada).
class CarretoSaidaProdutoOrfaoLinha {
  const CarretoSaidaProdutoOrfaoLinha({
    required this.itemVendaId,
    required this.nomeProduto,
    required this.quantidade,
    required this.unidade,
    this.motivo = CarretoSaidaSemBaixaMotivo.produtoExcluido,
    this.reservadoCadastro = 0,
  });

  final int itemVendaId;
  final String nomeProduto;
  final int quantidade;
  final String unidade;
  final String motivo;
  final int reservadoCadastro;

  Map<String, dynamic> toJson() => {
        'itemVendaId': itemVendaId,
        'nomeProduto': nomeProduto,
        'quantidade': quantidade,
        'unidade': unidade,
        'motivo': motivo,
        'reservadoCadastro': reservadoCadastro,
      };
}

/// Auditoria de saida de carreto para itens sem produto no cadastro (JSON em historico).
class CarretoSaidaProdutoOrfaoEvento {
  const CarretoSaidaProdutoOrfaoEvento({
    required this.vendaId,
    required this.numeroOrcamento,
    required this.documento,
    required this.dataHora,
    required this.linhas,
  });

  static const int versao = 1;

  final int vendaId;
  final int numeroOrcamento;
  final String documento;
  final DateTime dataHora;
  final List<CarretoSaidaProdutoOrfaoLinha> linhas;

  String get textoHumano {
    final trecho = linhas.map(_textoLinha).join('; ');
    if (trecho.isEmpty) {
      return 'Saida carreto sem baixa de estoque.';
    }
    return 'Saida carreto (sem baixa de saldo): $trecho.';
  }

  static String _textoLinha(CarretoSaidaProdutoOrfaoLinha l) {
    final base = '${l.nomeProduto} ${l.quantidade} ${l.unidade}';
    switch (l.motivo) {
      case CarretoSaidaSemBaixaMotivo.reservaInconsistente:
        return '$base (reserva ${l.reservadoCadastro} no cadastro)';
      case CarretoSaidaSemBaixaMotivo.forcaAdmin:
        return '$base (liberacao forcada)';
      case CarretoSaidaSemBaixaMotivo.produtoExcluido:
      default:
        return '$base (cadastro excluido)';
    }
  }

  String encode() => jsonEncode({
        'v': versao,
        'vendaId': vendaId,
        'numeroOrcamento': numeroOrcamento,
        'documento': documento,
        'dataHora': dataHora.toUtc().toIso8601String(),
        'linhas': linhas.map((l) => l.toJson()).toList(),
      });

  static CarretoSaidaProdutoOrfaoEvento? tryParse(String raw) {
    final t = raw.trim();
    if (t.isEmpty || !t.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(t);
      if (decoded is! Map) return null;
      final m = Map<String, dynamic>.from(decoded);
      final linhasRaw = m['linhas'];
      final linhas = <CarretoSaidaProdutoOrfaoLinha>[];
      if (linhasRaw is List) {
        for (final e in linhasRaw) {
          if (e is! Map) continue;
          final lm = Map<String, dynamic>.from(e);
          final q = (lm['quantidade'] as num?)?.toInt() ?? 0;
          if (q <= 0) continue;
          linhas.add(
            CarretoSaidaProdutoOrfaoLinha(
              itemVendaId: (lm['itemVendaId'] as num?)?.toInt() ?? 0,
              nomeProduto: (lm['nomeProduto'] ?? '').toString(),
              quantidade: q,
              unidade: (lm['unidade'] ?? 'UN').toString(),
              motivo: (lm['motivo'] ?? CarretoSaidaSemBaixaMotivo.produtoExcluido)
                  .toString(),
              reservadoCadastro:
                  (lm['reservadoCadastro'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      }
      if (linhas.isEmpty) return null;
      return CarretoSaidaProdutoOrfaoEvento(
        vendaId: (m['vendaId'] as num?)?.toInt() ?? 0,
        numeroOrcamento: (m['numeroOrcamento'] as num?)?.toInt() ?? 0,
        documento: (m['documento'] ?? '').toString(),
        dataHora: DateTime.tryParse((m['dataHora'] ?? '').toString())
                ?.toUtc() ??
            DateTime.now().toUtc(),
        linhas: linhas,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Romaneio / carga quando o produto da linha nao existe mais no cadastro.
abstract final class RomaneioProdutoOrfaoHelper {
  RomaneioProdutoOrfaoHelper._();

  static const alertaProdutoNaoEncontrado =
      'Produto nao encontrado no cadastro atual';

  static bool itemOrfao(
    ItemVenda item, {
    Produto? Function(int id)? obterProduto,
  }) {
    return ItemVendaProdutoOrfaoHelper.itemSemProdutoVinculado(
      item,
      obterProduto: obterProduto,
    );
  }

  /// Unidade gravada na venda quando possivel; senao UN.
  static String unidadeSnapshot(
    ItemVenda item, {
    Produto? Function(int id)? obterProduto,
  }) {
    Produto? ligado;
    try {
      ligado = item.produto.target;
    } catch (_) {}
    if (ligado != null) {
      return ProdutoEmbalagem.normalizarUnidade(ligado.unidade);
    }
    final pid = item.produto.targetId;
    if (pid > 0 && obterProduto != null) {
      final p = obterProduto(pid);
      if (p != null) {
        return ProdutoEmbalagem.normalizarUnidade(p.unidade);
      }
    }
    return 'UN';
  }

  static String nomeSnapshot(ItemVenda item) {
    final nome = item.nomeProduto.trim();
    return nome.isEmpty ? 'Produto sem nome' : nome;
  }
}
