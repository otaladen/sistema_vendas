import 'pdv_obra_calculadora_insercao.dart';

/// Item acumulado no projeto de obra (sessao PDV).
class ObraCalculadoraProjetoItem {
  const ObraCalculadoraProjetoItem({
    required this.rotuloReceita,
    required this.resumo,
    required this.montagem,
  });

  final String rotuloReceita;
  final String resumo;
  final PdvObraCalculadoraMontagem montagem;
}

/// Projeto de obra na sessao: varios calculos antes de ir ao carrinho.
class ObraCalculadoraProjetoSessao {
  ObraCalculadoraProjetoSessao({
    this.nomeObra = '',
    this.nomeCliente = '',
    List<ObraCalculadoraProjetoItem>? itens,
  }) : itens = itens ?? [];

  String nomeObra;
  String nomeCliente;
  final List<ObraCalculadoraProjetoItem> itens;

  bool get vazio => itens.isEmpty;

  int get quantidadeItens => itens.length;

  void adicionar(ObraCalculadoraProjetoItem item) => itens.add(item);

  void limpar() => itens.clear();

  List<PdvObraCalculadoraLinhaInsercao> linhasConsolidadas() =>
      ObraCalculadoraProjetoUtil.consolidarLinhas(
        itens.expand((i) => i.montagem.linhas).toList(),
      );
}

abstract final class ObraCalculadoraProjetoUtil {
  ObraCalculadoraProjetoUtil._();

  static List<PdvObraCalculadoraLinhaInsercao> consolidarLinhas(
    List<PdvObraCalculadoraLinhaInsercao> linhas,
  ) {
    final map = <int, PdvObraCalculadoraLinhaInsercao>{};
    for (final l in linhas) {
      final id = l.produto.id;
      final existente = map[id];
      if (existente == null) {
        map[id] = l;
        continue;
      }
      map[id] = PdvObraCalculadoraLinhaInsercao(
        produto: existente.produto,
        quantidade: existente.quantidade + l.quantidade,
        material: existente.material,
        substitutoAplicado: existente.substitutoAplicado || l.substitutoAplicado,
        produtoOriginalNome: existente.produtoOriginalNome ?? l.produtoOriginalNome,
      );
    }
    return map.values.toList();
  }
}
