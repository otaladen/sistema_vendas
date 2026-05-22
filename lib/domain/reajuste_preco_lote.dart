import '../model/produto.dart';
import '../model/reajuste_preco.dart';
import 'produto_precificacao.dart';

/// Tabela de preco afetada no reajuste em lote.
enum ReajusteTabelaPreco { preco1, preco2, preco3 }

/// Modo de calculo do novo preco.
enum ReajustePrecoModo {
  percentualSobrePrecoAtual,
  margemFixaSobreCusto,
}

enum ReajusteBaseCusto { custoDigitado, custoMedio }

/// Politica de arredondamento do preco calculado.
enum ReajusteArredondamento {
  centavos,
  dezena90,
  final99,
}

/// Parametros do reajuste.
class ReajustePrecoParametros {
  const ReajustePrecoParametros({
    required this.modo,
    required this.tabelas,
    this.percentualSobrePreco = 0,
    this.margemPercentual = 0,
    this.baseCusto = ReajusteBaseCusto.custoDigitado,
    this.arredondamento = ReajusteArredondamento.centavos,
    this.naoAlterarSeAbaixoDoCusto = true,
    this.somenteAtivos = true,
    this.margemMinimaPercentual = 5,
    this.percentualAbsolutoRequerAutorizacao = 15,
  });

  final ReajustePrecoModo modo;
  final Set<ReajusteTabelaPreco> tabelas;
  final double percentualSobrePreco;
  final double margemPercentual;
  final ReajusteBaseCusto baseCusto;
  final ReajusteArredondamento arredondamento;
  final bool naoAlterarSeAbaixoDoCusto;
  final bool somenteAtivos;
  final double margemMinimaPercentual;
  final double percentualAbsolutoRequerAutorizacao;

  String get tabelasCsv => tabelas.map(codigoTabela).join(',');

  static String codigoTabela(ReajusteTabelaPreco t) {
    switch (t) {
      case ReajusteTabelaPreco.preco1:
        return 'preco1';
      case ReajusteTabelaPreco.preco2:
        return 'preco2';
      case ReajusteTabelaPreco.preco3:
        return 'preco3';
    }
  }

  static Set<ReajusteTabelaPreco> tabelasFromCsv(String csv) {
    final out = <ReajusteTabelaPreco>{};
    for (final p in csv.split(',')) {
      switch (p.trim()) {
        case 'preco1':
          out.add(ReajusteTabelaPreco.preco1);
        case 'preco2':
          out.add(ReajusteTabelaPreco.preco2);
        case 'preco3':
          out.add(ReajusteTabelaPreco.preco3);
      }
    }
    return out;
  }

  static ReajustePrecoParametros fromReajustePreco(ReajustePreco r) {
    final modo = r.modo == 'margem'
        ? ReajustePrecoModo.margemFixaSobreCusto
        : ReajustePrecoModo.percentualSobrePrecoAtual;
    return ReajustePrecoParametros(
      modo: modo,
      tabelas: tabelasFromCsv(r.tabelasCsv),
      percentualSobrePreco: r.percentualSobrePreco,
      margemPercentual: r.margemPercentual,
      baseCusto: r.baseCusto == 'custo_medio'
          ? ReajusteBaseCusto.custoMedio
          : ReajusteBaseCusto.custoDigitado,
      arredondamento: arredondamentoFromCodigo(r.arredondamento),
      naoAlterarSeAbaixoDoCusto: r.protegerAbaixoCusto,
      somenteAtivos: r.somenteAtivos,
      margemMinimaPercentual: r.margemMinimaPercentual,
    );
  }

  static ReajusteArredondamento arredondamentoFromCodigo(String codigo) {
    switch (codigo) {
      case 'dezena_90':
        return ReajusteArredondamento.dezena90;
      case 'final_99':
        return ReajusteArredondamento.final99;
      default:
        return ReajusteArredondamento.centavos;
    }
  }

  static String codigoArredondamento(ReajusteArredondamento a) {
    switch (a) {
      case ReajusteArredondamento.dezena90:
        return 'dezena_90';
      case ReajusteArredondamento.final99:
        return 'final_99';
      case ReajusteArredondamento.centavos:
        return 'centavos';
    }
  }

  static String codigoModo(ReajustePrecoModo m) =>
      m == ReajustePrecoModo.margemFixaSobreCusto ? 'margem' : 'percentual';

  static String codigoBaseCusto(ReajusteBaseCusto b) =>
      b == ReajusteBaseCusto.custoMedio ? 'custo_medio' : 'custo_digitado';
}

/// Uma linha da simulacao / aplicacao.
class ReajustePrecoLinhaPreview {
  ReajustePrecoLinhaPreview({
    required this.produtoId,
    required this.codigoInterno,
    required this.nome,
    required this.precoCusto,
    required this.custoBaseCalculo,
    required this.preco1Antes,
    required this.preco2Antes,
    required this.preco3Antes,
    required this.preco1Depois,
    required this.preco2Depois,
    required this.preco3Depois,
    required this.seraAlterado,
    required this.exigeAutorizacaoGerente,
    this.motivoIgnorado,
    this.motivoAutorizacao,
  });

  final int produtoId;
  final String codigoInterno;
  final String nome;
  final double precoCusto;
  final double custoBaseCalculo;
  final double preco1Antes;
  final double preco2Antes;
  final double preco3Antes;
  final double preco1Depois;
  final double preco2Depois;
  final double preco3Depois;
  final bool seraAlterado;
  final bool exigeAutorizacaoGerente;
  final String? motivoIgnorado;
  final String? motivoAutorizacao;

  double get maiorVariacaoPercentual {
    var max = 0.0;
    for (final par in [
      (preco1Antes, preco1Depois),
      (preco2Antes, preco2Depois),
      (preco3Antes, preco3Depois),
    ]) {
      if (par.$1 <= 0) continue;
      final pct = ((par.$2 - par.$1) / par.$1) * 100;
      if (pct.abs() > max.abs()) max = pct;
    }
    return max;
  }

  double margemDepoisPrincipal(ReajustePrecoParametros params) {
    final custo = precoCusto;
    final preco = params.tabelas.contains(ReajusteTabelaPreco.preco1)
        ? preco1Depois
        : params.tabelas.contains(ReajusteTabelaPreco.preco2)
            ? preco2Depois
            : preco3Depois;
    return ProdutoPrecificacao.margemSobrePrecoVenda(
      custo: custo,
      precoVenda: preco,
    );
  }
}

class ReajustePrecoSimulacaoResumo {
  const ReajustePrecoSimulacaoResumo({
    required this.linhas,
    required this.totalEscopo,
    required this.totalAlterados,
    required this.totalIgnorados,
    required this.totalBloqueadosAbaixoCusto,
    required this.totalExigemAutorizacao,
  });

  final List<ReajustePrecoLinhaPreview> linhas;
  final int totalEscopo;
  final int totalAlterados;
  final int totalIgnorados;
  final int totalBloqueadosAbaixoCusto;
  final int totalExigemAutorizacao;

  double get variacaoMediaPercentual {
    final alteradas = linhas.where((l) => l.seraAlterado).toList();
    if (alteradas.isEmpty) return 0;
    var soma = 0.0;
    for (final l in alteradas) {
      soma += l.maiorVariacaoPercentual;
    }
    return soma / alteradas.length;
  }

  bool get precisaAutorizacaoGerente => totalExigemAutorizacao > 0;
}

class ReajustePrecoLoteAplicacaoResultado {
  const ReajustePrecoLoteAplicacaoResultado({
    required this.produtosGravados,
    required this.ignorados,
    this.reajustePrecoId = 0,
  });

  final int produtosGravados;
  final int ignorados;
  final int reajustePrecoId;
}

class ReajustePrecoLoteService {
  ReajustePrecoLoteService._();

  static double precoEfetivoTabela(Produto produto, ReajusteTabelaPreco tabela) {
    switch (tabela) {
      case ReajusteTabelaPreco.preco1:
        return produto.preco1 > 0 ? produto.preco1 : produto.precoVenda;
      case ReajusteTabelaPreco.preco2:
        return produto.preco2 > 0 ? produto.preco2 : produto.precoVenda;
      case ReajusteTabelaPreco.preco3:
        return produto.preco3 > 0 ? produto.preco3 : produto.precoVenda;
    }
  }

  static double custoParaCalculo(Produto produto, ReajusteBaseCusto base) {
    if (base == ReajusteBaseCusto.custoMedio) {
      if (produto.custoMedio > 0) return produto.custoMedio;
      return produto.precoCusto < 0 ? 0 : produto.precoCusto;
    }
    return produto.precoCusto < 0 ? 0 : produto.precoCusto;
  }

  static double arredondarPreco(double valor, ReajusteArredondamento modo) {
    if (valor.isNaN || valor.isInfinite || valor < 0) return 0;
    switch (modo) {
      case ReajusteArredondamento.centavos:
        return (valor * 100).roundToDouble() / 100;
      case ReajusteArredondamento.dezena90:
        return _arredondarTerminacao(valor, 0.90);
      case ReajusteArredondamento.final99:
        return _arredondarTerminacao(valor, 0.99);
    }
  }

  static double _arredondarTerminacao(double valor, double terminacao) {
    if (valor <= 0) return 0;
    final inteiro = valor.floor();
    var candidato = inteiro + terminacao;
    if (candidato < valor - 0.0001) {
      candidato = inteiro + 1 + terminacao;
    }
    return (candidato * 100).roundToDouble() / 100;
  }

  static double calcularNovoPreco({
    required double precoAtual,
    required Produto produto,
    required ReajustePrecoParametros params,
  }) {
    double bruto;
    switch (params.modo) {
      case ReajustePrecoModo.percentualSobrePrecoAtual:
        if (precoAtual <= 0) return precoAtual;
        bruto = precoAtual * (1 + (params.percentualSobrePreco / 100));
      case ReajustePrecoModo.margemFixaSobreCusto:
        final custo = custoParaCalculo(produto, params.baseCusto);
        if (custo <= 0) return precoAtual;
        bruto = ProdutoPrecificacao.precoComMargemSobreVenda(
          custo: custo,
          margemPercentual: params.margemPercentual,
        );
    }
    return arredondarPreco(bruto, params.arredondamento);
  }

  static bool _abaixoDoCusto(double novo, double custo) =>
      custo > 0 && novo > 0 && novo < custo - 0.0001;

  static String? _motivoAutorizacao({
    required ReajustePrecoLinhaPreview linha,
    required ReajustePrecoParametros params,
    required bool abaixoCustoAplicavel,
  }) {
    if (!linha.seraAlterado) return null;
    final motivos = <String>[];
    if (abaixoCustoAplicavel) {
      motivos.add('preco abaixo do custo');
    }
    final varPct = linha.maiorVariacaoPercentual.abs();
    if (params.percentualAbsolutoRequerAutorizacao > 0 &&
        varPct >= params.percentualAbsolutoRequerAutorizacao) {
      motivos.add('variacao ${varPct.toStringAsFixed(1)}%');
    }
    if (params.margemMinimaPercentual > 0) {
      final margem = linha.margemDepoisPrincipal(params);
      if (margem < params.margemMinimaPercentual - 0.05) {
        motivos.add(
          'margem ${margem.toStringAsFixed(1)}% < min ${params.margemMinimaPercentual.toStringAsFixed(0)}%',
        );
      }
    }
    if (motivos.isEmpty) return null;
    return motivos.join('; ');
  }

  static ReajustePrecoLinhaPreview simularProduto(
    Produto produto,
    ReajustePrecoParametros params,
  ) {
    final p1Antes = precoEfetivoTabela(produto, ReajusteTabelaPreco.preco1);
    final p2Antes = precoEfetivoTabela(produto, ReajusteTabelaPreco.preco2);
    final p3Antes = precoEfetivoTabela(produto, ReajusteTabelaPreco.preco3);
    final custoBase = custoParaCalculo(produto, params.baseCusto);

    var p1 = p1Antes;
    var p2 = p2Antes;
    var p3 = p3Antes;
    String? motivo;
    var abaixoCustoPotencial = false;

    if (params.somenteAtivos && !produto.ativo) {
      motivo = 'Produto inativo';
    } else if (params.tabelas.isEmpty) {
      motivo = 'Nenhuma tabela selecionada';
    } else {
      if (params.tabelas.contains(ReajusteTabelaPreco.preco1)) {
        p1 = calcularNovoPreco(
          precoAtual: p1Antes,
          produto: produto,
          params: params,
        );
      }
      if (params.tabelas.contains(ReajusteTabelaPreco.preco2)) {
        p2 = calcularNovoPreco(
          precoAtual: p2Antes,
          produto: produto,
          params: params,
        );
      }
      if (params.tabelas.contains(ReajusteTabelaPreco.preco3)) {
        p3 = calcularNovoPreco(
          precoAtual: p3Antes,
          produto: produto,
          params: params,
        );
      }

      final custo = produto.precoCusto;
      for (final novo in [
        if (params.tabelas.contains(ReajusteTabelaPreco.preco1)) p1,
        if (params.tabelas.contains(ReajusteTabelaPreco.preco2)) p2,
        if (params.tabelas.contains(ReajusteTabelaPreco.preco3)) p3,
      ]) {
        if (_abaixoDoCusto(novo, custo)) {
          abaixoCustoPotencial = true;
          break;
        }
      }

      if (params.naoAlterarSeAbaixoDoCusto && abaixoCustoPotencial) {
        motivo = 'Novo preco abaixo do custo';
        p1 = p1Antes;
        p2 = p2Antes;
        p3 = p3Antes;
      }

      if (params.modo == ReajustePrecoModo.margemFixaSobreCusto &&
          custoBase <= 0) {
        motivo = 'Sem custo para calcular margem';
        p1 = p1Antes;
        p2 = p2Antes;
        p3 = p3Antes;
      }

      if (params.modo == ReajustePrecoModo.percentualSobrePrecoAtual &&
          params.percentualSobrePreco == 0) {
        motivo = 'Percentual zero';
      }
    }

    final alteraP1 =
        params.tabelas.contains(ReajusteTabelaPreco.preco1) &&
        (p1 - p1Antes).abs() > 0.0001;
    final alteraP2 =
        params.tabelas.contains(ReajusteTabelaPreco.preco2) &&
        (p2 - p2Antes).abs() > 0.0001;
    final alteraP3 =
        params.tabelas.contains(ReajusteTabelaPreco.preco3) &&
        (p3 - p3Antes).abs() > 0.0001;
    final seraAlterado =
        motivo == null && (alteraP1 || alteraP2 || alteraP3);

    final linha = ReajustePrecoLinhaPreview(
      produtoId: produto.id,
      codigoInterno: produto.codigoInterno,
      nome: produto.nome,
      precoCusto: produto.precoCusto,
      custoBaseCalculo: custoBase,
      preco1Antes: p1Antes,
      preco2Antes: p2Antes,
      preco3Antes: p3Antes,
      preco1Depois: p1,
      preco2Depois: p2,
      preco3Depois: p3,
      seraAlterado: seraAlterado,
      exigeAutorizacaoGerente: false,
      motivoIgnorado: seraAlterado ? null : motivo ?? 'Sem alteracao',
    );

    final abaixoCustoAuth =
        !params.naoAlterarSeAbaixoDoCusto && abaixoCustoPotencial;
    final motivoAuth = _motivoAutorizacao(
      linha: linha,
      params: params,
      abaixoCustoAplicavel: abaixoCustoAuth,
    );

    return ReajustePrecoLinhaPreview(
      produtoId: linha.produtoId,
      codigoInterno: linha.codigoInterno,
      nome: linha.nome,
      precoCusto: linha.precoCusto,
      custoBaseCalculo: linha.custoBaseCalculo,
      preco1Antes: linha.preco1Antes,
      preco2Antes: linha.preco2Antes,
      preco3Antes: linha.preco3Antes,
      preco1Depois: linha.preco1Depois,
      preco2Depois: linha.preco2Depois,
      preco3Depois: linha.preco3Depois,
      seraAlterado: linha.seraAlterado,
      exigeAutorizacaoGerente:
          linha.seraAlterado && motivoAuth != null,
      motivoIgnorado: linha.motivoIgnorado,
      motivoAutorizacao: motivoAuth,
    );
  }

  static ReajustePrecoSimulacaoResumo simular(
    Iterable<Produto> produtos,
    ReajustePrecoParametros params,
  ) {
    final lista = produtos.toList();
    final linhas = <ReajustePrecoLinhaPreview>[];
    var alterados = 0;
    var ignorados = 0;
    var bloqueados = 0;
    var exigemAuth = 0;

    for (final p in lista) {
      final linha = simularProduto(p, params);
      linhas.add(linha);
      if (linha.seraAlterado) {
        alterados++;
        if (linha.exigeAutorizacaoGerente) exigemAuth++;
      } else {
        ignorados++;
        if (linha.motivoIgnorado?.contains('custo') == true) {
          bloqueados++;
        }
      }
    }

    return ReajustePrecoSimulacaoResumo(
      linhas: linhas,
      totalEscopo: lista.length,
      totalAlterados: alterados,
      totalIgnorados: ignorados,
      totalBloqueadosAbaixoCusto: bloqueados,
      totalExigemAutorizacao: exigemAuth,
    );
  }

  static void aplicarLinhaNoProduto(
    Produto produto,
    ReajustePrecoLinhaPreview linha,
    ReajustePrecoParametros params,
  ) {
    if (!linha.seraAlterado) return;
    if (params.tabelas.contains(ReajusteTabelaPreco.preco1) &&
        (linha.preco1Depois - linha.preco1Antes).abs() > 0.0001) {
      produto.preco1 = linha.preco1Depois;
      produto.precoVenda = linha.preco1Depois;
    }
    if (params.tabelas.contains(ReajusteTabelaPreco.preco2) &&
        (linha.preco2Depois - linha.preco2Antes).abs() > 0.0001) {
      produto.preco2 = linha.preco2Depois;
    }
    if (params.tabelas.contains(ReajusteTabelaPreco.preco3) &&
        (linha.preco3Depois - linha.preco3Antes).abs() > 0.0001) {
      produto.preco3 = linha.preco3Depois;
    }
  }

  static void restaurarPrecosAntesNoProduto(
    Produto produto,
    ReajustePrecoItemSnapshot item,
  ) {
    if (item.alterouPreco1) {
      produto.preco1 = item.preco1Antes;
      produto.precoVenda = item.preco1Antes;
    }
    if (item.alterouPreco2) {
      produto.preco2 = item.preco2Antes;
    }
    if (item.alterouPreco3) {
      produto.preco3 = item.preco3Antes;
    }
  }
}

/// Dados minimos para estorno (evita acoplamento circular no domain).
class ReajustePrecoItemSnapshot {
  const ReajustePrecoItemSnapshot({
    required this.produtoId,
    required this.preco1Antes,
    required this.preco2Antes,
    required this.preco3Antes,
    required this.alterouPreco1,
    required this.alterouPreco2,
    required this.alterouPreco3,
  });

  final int produtoId;
  final double preco1Antes;
  final double preco2Antes;
  final double preco3Antes;
  final bool alterouPreco1;
  final bool alterouPreco2;
  final bool alterouPreco3;
}
