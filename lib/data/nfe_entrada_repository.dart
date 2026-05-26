import 'package:intl/intl.dart';

import '../domain/produto_embalagem.dart';
import '../data/models/conta_pagar.dart';
import '../model/fornecedor_nfe.dart';
import '../model/historico_entrada.dart';
import '../model/item_nota_temporario.dart';
import '../model/nfe_importada_registro.dart';
import '../model/produto.dart';
import '../model/vinculo_fornecedor_produto.dart';
import '../objectbox.g.dart';
import '../services/gerenciador_estoque_service.dart';
import 'nfe_entrada_xml_store.dart';
import 'objectbox.dart';
import 'produto_repository.dart' show calcularCustoMedioPonderadoEntradasNfe;
import 'sync/sync_write_trigger.dart';

/// Origem do casamento produto/nota na conferencia de XML.
enum ConferenciaNfeMatchTipo {
  /// Produto encontrado pelo EAN (`cEAN` / `cEANTrib`) do XML.
  vinculadoPorEan,

  /// Produto encontrado pela tabela fornecedor + codigo do item (`cProd`).
  vinculoFornecedor,

  /// Sem cadastro automatico; na confirmacao sera criado produto novo (ou vinculo manual).
  produtoNovo,
}

/// Dados de uma linha prontos para montar a UI de conferencia.
class SugestaoLinhaConferencia {
  const SugestaoLinhaConferencia({
    required this.item,
    required this.produtoNovo,
    this.produtoExistenteId,
    required this.fatorInicial,
    required this.unidadeInternaInicial,
    required this.tipoMatch,
  });

  final ItemNotaTemporario item;
  final bool produtoNovo;
  final int? produtoExistenteId;
  final double fatorInicial;
  final String unidadeInternaInicial;

  /// Como o sistema casou o item do XML ao cadastro (para cores na UI).
  final ConferenciaNfeMatchTipo tipoMatch;
}

/// Linha da previa de estorno (o que sera revertido no estoque).
class LinhaPreviaEstornoNfe {
  const LinhaPreviaEstornoNfe({
    required this.nomeProduto,
    required this.quantidadeEstorno,
    required this.estoqueAtual,
  });

  final String nomeProduto;
  final int quantidadeEstorno;
  final int estoqueAtual;
}

/// Resultado da validacao antes de estornar uma NF-e importada.
class ValidacaoEstornoNfe {
  const ValidacaoEstornoNfe({
    required this.podeEstornar,
    this.motivoBloqueio,
    this.linhas = const [],
  });

  final bool podeEstornar;
  final String? motivoBloqueio;
  final List<LinhaPreviaEstornoNfe> linhas;
}

/// Linha confirmada pelo usuario na [ConferenciaXmlScreen].
class ConferenciaNfeLinhaConfirmacao {
  const ConferenciaNfeLinhaConfirmacao({
    required this.item,
    required this.fatorConversao,
    required this.unidadeInterna,
    this.produtoExistenteId,
  });

  final ItemNotaTemporario item;
  final double fatorConversao;
  final String unidadeInterna;
  final int? produtoExistenteId;
}

class NfeEntradaRepository {
  NfeEntradaRepository(this._db)
      : _estoque = GerenciadorEstoqueService(_db),
        _xmlStore = NfeEntradaXmlStore(_db.storeDirectoryPath);

  final ObjectBox _db;
  final GerenciadorEstoqueService _estoque;
  final NfeEntradaXmlStore _xmlStore;

  static const List<String> unidadesInternasValidas = [
    'UN',
    'M',
    'M2',
    'M3',
    'KG',
    'SC',
    'CX',
    'LT',
  ];

  /// Resolve EAN, vinculo fornecedor+cProd e valores iniciais de fator/unidade.
  List<SugestaoLinhaConferencia> prepararSugestoesConferencia(
    NfeXmlParseResult nfe,
  ) {
    final cnpj = nfe.emitente.cnpj;
    FornecedorNfe? fornDb;
    final qForn = _db.fornecedorNfeBox
        .query(FornecedorNfe_.cnpj.equals(cnpj))
        .build();
    try {
      final list = qForn.find();
      if (list.isNotEmpty) fornDb = list.first;
    } finally {
      qForn.close();
    }

    final fornecedorId = fornDb?.id ?? 0;
    final sugestoes = <SugestaoLinhaConferencia>[];

    for (final item in nfe.itens) {
      Produto? produtoResolvido;
      var resolvidoPorEan = false;
      if (item.codigoBarras.isNotEmpty) {
        produtoResolvido = _buscarProdutoPorCodigoBarras(item.codigoBarras);
        if (produtoResolvido != null) {
          resolvidoPorEan = true;
        }
      }

      VinculoFornecedorProduto? vinculo;
      if (fornecedorId > 0) {
        vinculo = _buscarVinculo(fornecedorId, item.codigo);
      }

      if (produtoResolvido == null &&
          vinculo != null &&
          vinculo.produto.hasValue) {
        final t = vinculo.produto.target;
        if (t != null) produtoResolvido = t;
      }

      final fatorVinculo = (vinculo != null && vinculo.fatorConversao > 0)
          ? vinculo.fatorConversao
          : 1.0;
      final fatorInicial = _fatorInicialConferencia(
        produto: produtoResolvido,
        fatorVinculo: fatorVinculo,
        unidadeNota: item.unidadeComercial,
      );

      if (produtoResolvido != null) {
        final tipo = resolvidoPorEan
            ? ConferenciaNfeMatchTipo.vinculadoPorEan
            : ConferenciaNfeMatchTipo.vinculoFornecedor;
        sugestoes.add(
          SugestaoLinhaConferencia(
            item: item,
            produtoNovo: false,
            produtoExistenteId: produtoResolvido.id,
            fatorInicial: fatorInicial,
            unidadeInternaInicial: produtoResolvido.unidade.trim().isEmpty
                ? 'UN'
                : produtoResolvido.unidade.trim(),
            tipoMatch: tipo,
          ),
        );
      } else {
        sugestoes.add(
          SugestaoLinhaConferencia(
            item: item,
            produtoNovo: true,
            produtoExistenteId: null,
            fatorInicial: fatorInicial,
            unidadeInternaInicial: 'UN',
            tipoMatch: ConferenciaNfeMatchTipo.produtoNovo,
          ),
        );
      }
    }

    return sugestoes;
  }

  /// Verifica se a chave de 44 digitos ja consta no log de importacoes.
  bool chaveNfeJaImportada(String chaveAcesso) {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    if (chave.length != 44) {
      return false;
    }
    return _buscarImportacaoPorChave(chave) != null;
  }

  /// Importacoes gravadas entre [inicioUtc] e [fimUtc] (data de entrada no sistema).
  List<NfeImportadaRegistro> listarImportacoesNoPeriodo({
    required DateTime inicioUtc,
    required DateTime fimUtc,
  }) {
    final q = _db.nfeImportadaRegistroBox
        .query(
          NfeImportadaRegistro_.dataHoraImportacao
              .greaterOrEqualDate(inicioUtc)
              .and(
                NfeImportadaRegistro_.dataHoraImportacao.lessOrEqualDate(fimUtc),
              ),
        )
        .order(
          NfeImportadaRegistro_.dataHoraImportacao,
          flags: Order.descending,
        )
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  /// Log de NF-e importadas (mais recentes primeiro).
  List<NfeImportadaRegistro> listarImportacoesNfeDesc() {
    final q = _db.nfeImportadaRegistroBox
        .query()
        .order(
          NfeImportadaRegistro_.dataHoraImportacao,
          flags: Order.descending,
        )
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  NfeImportadaRegistro? obterImportacaoPorId(int id) =>
      _db.nfeImportadaRegistroBox.get(id);

  /// Verifica se o estorno e possivel (estoque suficiente, sem reserva comprometida).
  ValidacaoEstornoNfe validarEstornoImportacao(int registroId) {
    final registro = obterImportacaoPorId(registroId);
    if (registro == null) {
      return const ValidacaoEstornoNfe(
        podeEstornar: false,
        motivoBloqueio: 'Registro da importacao nao encontrado.',
      );
    }
    final historico = listarHistoricoPorChaveNfe(registro.chaveAcesso);
    if (historico.isEmpty) {
      return const ValidacaoEstornoNfe(podeEstornar: true);
    }

    final linhas = <LinhaPreviaEstornoNfe>[];
    for (final h in historico) {
      final produto = h.produto.target;
      if (produto == null) {
        return const ValidacaoEstornoNfe(
          podeEstornar: false,
          motivoBloqueio:
              'Historico sem produto vinculado. Nao e possivel estornar com seguranca.',
        );
      }
      final qtd = h.quantidadeEntradaEstoque;
      if (qtd <= 0) continue;

      final nome = produto.nome.trim().isNotEmpty
          ? produto.nome
          : produto.codigoInterno;
      linhas.add(
        LinhaPreviaEstornoNfe(
          nomeProduto: nome,
          quantidadeEstorno: qtd,
          estoqueAtual: produto.estoqueReal,
        ),
      );

      if (produto.estoqueReal < qtd) {
        return ValidacaoEstornoNfe(
          podeEstornar: false,
          motivoBloqueio:
              'Estoque insuficiente em "$nome": fisico ${produto.estoqueReal}, '
              'entrada da nota $qtd. Provavelmente houve venda ou outra saida.',
          linhas: linhas,
        );
      }
      final estoqueApos = produto.estoqueReal - qtd;
      if (estoqueApos < produto.estoqueReservado) {
        return ValidacaoEstornoNfe(
          podeEstornar: false,
          motivoBloqueio:
              'Em "$nome" ha ${produto.estoqueReservado} un. reservadas; '
              'apos o estorno restariam $estoqueApos no fisico.',
          linhas: linhas,
        );
      }
    }

    return ValidacaoEstornoNfe(podeEstornar: true, linhas: linhas);
  }

  /// Estorna importacao: reverte estoque, remove historico e libera a chave para nova entrada.
  void estornarImportacaoNfe(int registroId) {
    final validacao = validarEstornoImportacao(registroId);
    if (!validacao.podeEstornar) {
      throw StateError(
        validacao.motivoBloqueio ?? 'Nao foi possivel estornar esta NF-e.',
      );
    }

    final registro = obterImportacaoPorId(registroId);
    if (registro == null) {
      throw StateError('Registro da importacao nao encontrado.');
    }
    final chaveNorm = registro.chaveAcesso.replaceAll(RegExp(r'\D'), '');
    final historico = listarHistoricoPorChaveNfe(chaveNorm);
    final idsProdutosParaRecalcularCusto = <int>{};
    for (final h in historico) {
      final pid = h.produto.targetId;
      if (pid != 0) idsProdutosParaRecalcularCusto.add(pid);
    }

    _db.store.runInTransaction(TxMode.write, () {
      final produtosParaRemover = <int>{};

      for (final h in historico) {
        final produto = h.produto.target;
        if (produto == null) continue;
        final qtd = h.quantidadeEntradaEstoque;
        if (qtd > 0) {
          _estoque.estornarEntradaPorNotaFiscal(produto, qtd);
        }
        _db.historicoEntradaBox.remove(h.id);

        if (_podeRemoverProdutoCriadoNaNfe(produto)) {
          produtosParaRemover.add(produto.id);
        }
      }

      for (final produtoId in produtosParaRemover) {
        _removerVinculosDoProduto(produtoId);
        _db.produtoBox.remove(produtoId);
      }

      _db.nfeImportadaRegistroBox.remove(registro.id);

      for (final pid in idsProdutosParaRecalcularCusto) {
        if (produtosParaRemover.contains(pid)) continue;
        final p = _db.produtoBox.get(pid);
        if (p == null) continue;
        final cm = calcularCustoMedioPonderadoEntradasNfe(_db, pid);
        if (cm != null) {
          p.custoMedio = cm;
        } else {
          p.custoMedio = p.precoCusto < 0 ? 0 : p.precoCusto;
        }
        _estoque.persistirProdutoMetadados(p);
      }
    });

    notificarAlteracaoParaRede();
  }

  /// Itens de estoque lançados nesta NF-e (mesma chave de 44 dígitos).
  List<HistoricoEntrada> listarHistoricoPorChaveNfe(String chaveAcesso) {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    if (chave.length != 44) {
      return const [];
    }
    final q = _db.historicoEntradaBox
        .query(HistoricoEntrada_.chaveAcesso.equals(chave))
        .order(HistoricoEntrada_.id)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  NfeImportadaRegistro? _buscarImportacaoPorChave(String chave44) {
    final q = _db.nfeImportadaRegistroBox
        .query(NfeImportadaRegistro_.chaveAcesso.equals(chave44))
        .build();
    try {
      final list = q.find();
      return list.isEmpty ? null : list.first;
    } finally {
      q.close();
    }
  }

  Produto? _buscarProdutoPorCodigoBarras(String ean) {
    final q = _db.produtoBox.query(Produto_.codigoBarras.equals(ean)).build();
    try {
      final list = q.find();
      return list.isEmpty ? null : list.first;
    } finally {
      q.close();
    }
  }

  VinculoFornecedorProduto? _buscarVinculo(int fornecedorId, String codigo) {
    if (codigo.isEmpty) return null;
    final q = _db.vinculoFornecedorProdutoBox
        .query(
          VinculoFornecedorProduto_.codigoProdutoFornecedor
              .equals(codigo)
              .and(VinculoFornecedorProduto_.fornecedor.equals(fornecedorId)),
        )
        .build();
    try {
      final list = q.find();
      return list.isEmpty ? null : list.first;
    } finally {
      q.close();
    }
  }

  /// Grava fornecedor, produtos, estoque e vinculos em uma unica transacao.
  void confirmarEntrada({
    required NfeXmlParseResult nfe,
    required List<ConferenciaNfeLinhaConfirmacao> linhas,
    String? xmlOriginal,
  }) {
    final chaveNorm = nfe.chaveAcesso.replaceAll(RegExp(r'\D'), '');
    _db.store.runInTransaction(TxMode.write, () {
      if (chaveNorm.length != 44) {
        throw StateError(
          'Chave de acesso invalida para registro de importacao.',
        );
      }
      final duplicada = _buscarImportacaoPorChave(chaveNorm);
      if (duplicada != null) {
        final quando = DateFormat(
          'dd/MM/yyyy HH:mm',
          'pt_BR',
        ).format(duplicada.dataHoraImportacao.toLocal());
        throw StateError(
          'Esta NF-e ja foi importada em $quando. A mesma nota nao pode dar entrada duas vezes.',
        );
      }

      var fornecedor = _buscarFornecedorPorCnpj(nfe.emitente.cnpj);
      if (fornecedor == null) {
        fornecedor = FornecedorNfe(
          cnpj: nfe.emitente.cnpj,
          razaoSocial: nfe.emitente.razaoSocial,
          nomeFantasia: nfe.emitente.nomeFantasia,
        );
      } else {
        fornecedor.razaoSocial = nfe.emitente.razaoSocial;
        fornecedor.nomeFantasia = nfe.emitente.nomeFantasia;
      }
      final fornecedorId = _db.fornecedorNfeBox.put(fornecedor);
      fornecedor.id = fornecedorId;

      final produtosAfetadosCustoMedio = <int>{};

      for (final linha in linhas) {
        final fator = linha.fatorConversao;
        if (fator <= 0) {
          throw StateError(
            'Fator de conversao invalido (${linha.item.codigo}).',
          );
        }
        final unidade = linha.unidadeInterna.trim().toUpperCase();
        if (!unidadesInternasValidas.contains(unidade)) {
          throw StateError('Unidade interna invalida: $unidade');
        }

        var embalagemMultiplica = true;
        Produto? produtoEmbalagemRef;
        if (linha.produtoExistenteId != null) {
          produtoEmbalagemRef = _db.produtoBox.get(linha.produtoExistenteId!);
          if (produtoEmbalagemRef != null) {
            embalagemMultiplica = produtoEmbalagemRef.embalagemMultiplica;
          }
        }

        final qtdInterna = ProdutoEmbalagem.quantidadeNotaParaEstoque(
          quantidadeComercial: linha.item.quantidadeComercial,
          fator: fator,
          embalagemMultiplica: embalagemMultiplica,
        );
        if (qtdInterna < 0) {
          throw StateError(
            'Quantidade interna negativa (${linha.item.codigo}).',
          );
        }

        final custoUnitInterno =
            linha.item.valorUnitarioComercial > 0 && fator > 0
            ? (embalagemMultiplica
                  ? linha.item.valorUnitarioComercial / fator
                  : linha.item.valorUnitarioComercial * fator)
            : 0.0;

        final nomeFantasiaOuRazao = fornecedor.nomeFantasia.trim().isNotEmpty
            ? fornecedor.nomeFantasia
            : fornecedor.razaoSocial;

        Produto produto;
        if (linha.produtoExistenteId != null) {
          final existente = _db.produtoBox.get(linha.produtoExistenteId!);
          if (existente == null) {
            throw StateError(
              'Produto id ${linha.produtoExistenteId} nao encontrado.',
            );
          }
          produto = existente;
          produto.precoCusto = custoUnitInterno;
          produto.unidade = unidade;
          _sincronizarEmbalagemProdutoComNota(
            produto,
            unidadeNota: linha.item.unidadeComercial,
            fator: fator,
            embalagemMultiplica: embalagemMultiplica,
          );
          produto.fornecedor = nomeFantasiaOuRazao;
          if (linha.item.ncm.isNotEmpty) {
            produto.ncm = linha.item.ncm;
          }
          if (linha.item.codigoBarras.isNotEmpty &&
              produto.codigoBarras.isEmpty) {
            produto.codigoBarras = linha.item.codigoBarras;
          }
          _estoque.persistirProdutoMetadados(produto);
          if (qtdInterna > 0) {
            _estoque.registrarEntradaPorNotaFiscal(produto, qtdInterna);
          }
        } else {
          final codigoInterno = _gerarCodigoInterno(nfe, linha.item);
          final uNota = ProdutoEmbalagem.normalizarUnidade(
            linha.item.unidadeComercial,
          );
          final uVenda = ProdutoEmbalagem.normalizarUnidade(unidade);
          final converteEmbalagem =
              uNota != uVenda && fator > 0 && (fator - 1).abs() > 0.0001;
          produto = Produto(
            codigoInterno: codigoInterno,
            nome: linha.item.descricao.length > 120
                ? linha.item.descricao.substring(0, 120)
                : linha.item.descricao,
            descricao: linha.item.descricao,
            unidade: unidade,
            unidadeCompra: converteEmbalagem ? uNota : '',
            quantidadePorEmbalagem: converteEmbalagem ? fator : 1,
            embalagemMultiplica: embalagemMultiplica,
            codigoBarras: linha.item.codigoBarras,
            ncm: linha.item.ncm,
            fornecedor: nomeFantasiaOuRazao,
            precoCusto: custoUnitInterno,
            precoVenda: 0,
            quantidadeMinima: 0,
            estoqueReal: 0,
            estoqueReservado: 0,
          );
          produto.id = _db.produtoBox.put(produto);
          if (qtdInterna > 0) {
            _estoque.registrarEntradaPorNotaFiscal(produto, qtdInterna);
          }
        }

        final vExistente = _buscarVinculo(fornecedor.id, linha.item.codigo);
        final v =
            vExistente ??
            VinculoFornecedorProduto(
              codigoProdutoFornecedor: linha.item.codigo,
              fatorConversao: fator,
            );
        v.fatorConversao = fator;
        v.fornecedor.target = fornecedor;
        v.produto.target = produto;
        _db.vinculoFornecedorProdutoBox.put(v);

        final hist = HistoricoEntrada(
          numeroNota: nfe.numeroNota,
          chaveAcesso: nfe.chaveAcesso,
          dataEmissao: nfe.dataEmissao,
          nomeFornecedor: nomeFantasiaOuRazao,
          cnpjFornecedor: fornecedor.cnpj,
          unidadeFornecedor: linha.item.unidadeComercial,
          quantidadeFornecedor: linha.item.quantidadeComercial,
          fatorConversaoUtilizado: fator,
          quantidadeEntradaEstoque: qtdInterna,
          precoCustoUnitarioNota: custoUnitInterno,
        );
        hist.produto.target = produto;
        _db.historicoEntradaBox.put(hist);
        produtosAfetadosCustoMedio.add(produto.id);
      }

      for (final pid in produtosAfetadosCustoMedio) {
        final p = _db.produtoBox.get(pid);
        if (p == null) continue;
        final cm = calcularCustoMedioPonderadoEntradasNfe(_db, pid);
        if (cm != null) {
          p.custoMedio = cm;
        } else {
          p.custoMedio = p.precoCusto < 0 ? 0 : p.precoCusto;
        }
        _estoque.persistirProdutoMetadados(p);
      }

      _persistirContasPagarNfeImportada(
        fornecedorPersistido: fornecedor,
        chave44: chaveNorm,
        nfe: nfe,
      );

      final nomeReg = fornecedor.nomeFantasia.trim().isNotEmpty
          ? fornecedor.nomeFantasia.trim()
          : fornecedor.razaoSocial.trim();
      final registro = NfeImportadaRegistro(
        chaveAcesso: chaveNorm,
        numeroNota: nfe.numeroNota,
        dataEmissao: nfe.dataEmissao,
        nomeFornecedor: nomeReg,
        cnpjFornecedor: fornecedor.cnpj,
        dataHoraImportacao: DateTime.now().toUtc(),
        quantidadeItens: linhas.length,
      );
      _db.nfeImportadaRegistroBox.put(registro);
    });

    if (xmlOriginal != null && xmlOriginal.trim().isNotEmpty) {
      _xmlStore.salvarXml(chaveNorm, xmlOriginal);
    }

    notificarAlteracaoParaRede();
  }

  /// Lança [ContaPagar] para a NF-e: parcelas do XML ou uma linha à vista (paga).
  void _persistirContasPagarNfeImportada({
    required FornecedorNfe fornecedorPersistido,
    required String chave44,
    required NfeXmlParseResult nfe,
  }) {
    final numeroNotaStr =
        nfe.numeroNota > 0 ? nfe.numeroNota.toString() : null;
    final dups = nfe.duplicatas;

    if (dups.isEmpty) {
      final total = nfe.valorTotalNota;
      if (total < 0) {
        throw StateError(
          'Valor total da NF-e invalido para lancamento financeiro a vista.',
        );
      }
      final conta = ContaPagar(
        nfeChave: chave44,
        numeroNota: numeroNotaStr,
        numeroParcela: '001/001',
        dataEmissao: nfe.dataEmissao,
        dataVencimento: nfe.dataEmissao,
        valorParcela: total,
        status: ContaPagarStatus.pago,
        dataPagamento: nfe.dataEmissao,
        valorPago: total,
      );
      conta.fornecedor.target = fornecedorPersistido;
      _db.contaPagarBox.put(conta);
      return;
    }

    for (final d in dups) {
      if (d.valorParcela <= 0) {
        throw StateError(
          'Valor da parcela "${d.numeroParcela}" invalido (esperado > 0).',
        );
      }
      final conta = ContaPagar(
        nfeChave: chave44,
        numeroNota: numeroNotaStr,
        numeroParcela: d.numeroParcela,
        dataEmissao: nfe.dataEmissao,
        dataVencimento: d.dataVencimento,
        valorParcela: d.valorParcela,
        status: ContaPagarStatus.pendente,
      );
      conta.fornecedor.target = fornecedorPersistido;
      _db.contaPagarBox.put(conta);
    }
  }

  FornecedorNfe? _buscarFornecedorPorCnpj(String cnpj) {
    final q = _db.fornecedorNfeBox
        .query(FornecedorNfe_.cnpj.equals(cnpj))
        .build();
    try {
      final list = q.find();
      return list.isEmpty ? null : list.first;
    } finally {
      q.close();
    }
  }

  String _gerarCodigoInterno(NfeXmlParseResult nfe, ItemNotaTemporario item) {
    final chave = nfe.chaveAcesso.replaceAll(RegExp(r'\D'), '');
    final sufixo = chave.length >= 8
        ? chave.substring(chave.length - 8)
        : chave;
    final base = 'NFE-$sufixo-${item.numeroItem}';
    if (_codigoInternoLivre(base)) return base;
    var i = 0;
    while (i < 1000) {
      final tentativa = '$base-$i';
      if (_codigoInternoLivre(tentativa)) return tentativa;
      i++;
    }
    return '$base-${DateTime.now().millisecondsSinceEpoch}';
  }

  bool _codigoInternoLivre(String codigo) {
    final q = _db.produtoBox
        .query(Produto_.codigoInterno.equals(codigo))
        .build();
    try {
      return q.find().isEmpty;
    } finally {
      q.close();
    }
  }

  bool _podeRemoverProdutoCriadoNaNfe(Produto produto) {
    if (!produto.codigoInterno.startsWith('NFE-')) return false;
    if (produto.estoqueReal != 0 || produto.estoqueReservado != 0) {
      return false;
    }
    if (_produtoTemReferenciasVenda(produto.id)) return false;
    if (_produtoEmKitOrcamento(produto.id)) return false;
    return _contarHistoricoProduto(produto.id) == 0;
  }

  int _contarHistoricoProduto(int produtoId) {
    final q = _db.historicoEntradaBox
        .query(HistoricoEntrada_.produto.equals(produtoId))
        .build();
    try {
      return q.count();
    } finally {
      q.close();
    }
  }

  bool _produtoTemReferenciasVenda(int produtoId) {
    final q = _db.itemVendaBox
        .query(ItemVenda_.produto.equals(produtoId))
        .build();
    try {
      return q.count() > 0;
    } finally {
      q.close();
    }
  }

  bool _produtoEmKitOrcamento(int produtoId) {
    final q = _db.kitOrcamentoItemBox
        .query(KitOrcamentoItem_.produto.equals(produtoId))
        .build();
    try {
      return q.count() > 0;
    } finally {
      q.close();
    }
  }

  void _removerVinculosDoProduto(int produtoId) {
    final q = _db.vinculoFornecedorProdutoBox
        .query(VinculoFornecedorProduto_.produto.equals(produtoId))
        .build();
    try {
      for (final v in q.find()) {
        _db.vinculoFornecedorProdutoBox.remove(v.id);
      }
    } finally {
      q.close();
    }
  }

  double _fatorInicialConferencia({
    required Produto? produto,
    required double fatorVinculo,
    required String unidadeNota,
  }) {
    if (produto != null) {
      final doCadastro = ProdutoEmbalagem.fatorSugeridoNotaParaEstoque(
        produto: produto,
        unidadeNota: unidadeNota,
      );
      if (doCadastro != null && doCadastro > 0) {
        if (fatorVinculo > 0 &&
            (fatorVinculo - 1).abs() > 0.0001 &&
            (fatorVinculo - doCadastro).abs() > 0.0001) {
          return fatorVinculo;
        }
        return doCadastro;
      }
    }
    return fatorVinculo > 0 ? fatorVinculo : 1.0;
  }

  void _sincronizarEmbalagemProdutoComNota(
    Produto produto, {
    required String unidadeNota,
    required double fator,
    required bool embalagemMultiplica,
  }) {
    if (fator <= 0 || (fator - 1).abs() < 0.0001) return;
    final uNota = ProdutoEmbalagem.normalizarUnidade(unidadeNota);
    final uVenda = ProdutoEmbalagem.normalizarUnidade(produto.unidade);
    if (uNota == uVenda) return;

    final compraVazia = produto.unidadeCompra.trim().isEmpty;
    final semConversao = !produto.temConversaoEmbalagem;
    if (!compraVazia && !semConversao) return;

    produto.unidadeCompra = uNota;
    produto.quantidadePorEmbalagem = fator;
    produto.embalagemMultiplica = embalagemMultiplica;
  }
}
