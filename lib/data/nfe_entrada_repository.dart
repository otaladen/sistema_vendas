import 'package:intl/intl.dart';

import '../model/fornecedor_nfe.dart';
import '../model/historico_entrada.dart';
import '../model/item_nota_temporario.dart';
import '../model/nfe_importada_registro.dart';
import '../model/produto.dart';
import '../model/vinculo_fornecedor_produto.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

/// Dados de uma linha prontos para montar a UI de conferencia.
class SugestaoLinhaConferencia {
  const SugestaoLinhaConferencia({
    required this.item,
    required this.produtoNovo,
    this.produtoExistenteId,
    required this.fatorInicial,
    required this.unidadeInternaInicial,
  });

  final ItemNotaTemporario item;
  final bool produtoNovo;
  final int? produtoExistenteId;
  final double fatorInicial;
  final String unidadeInternaInicial;
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
  NfeEntradaRepository(this._db);

  final ObjectBox _db;

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
    final qForn =
        _db.fornecedorNfeBox.query(FornecedorNfe_.cnpj.equals(cnpj)).build();
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
      if (item.codigoBarras.isNotEmpty) {
        produtoResolvido = _buscarProdutoPorCodigoBarras(item.codigoBarras);
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

      final fatorVinculo =
          (vinculo != null && vinculo.fatorConversao > 0)
              ? vinculo.fatorConversao
              : 1.0;

      if (produtoResolvido != null) {
        sugestoes.add(
          SugestaoLinhaConferencia(
            item: item,
            produtoNovo: false,
            produtoExistenteId: produtoResolvido.id,
            fatorInicial: fatorVinculo,
            unidadeInternaInicial: produtoResolvido.unidade.trim().isEmpty
                ? 'UN'
                : produtoResolvido.unidade.trim(),
          ),
        );
      } else {
        sugestoes.add(
          SugestaoLinhaConferencia(
            item: item,
            produtoNovo: true,
            produtoExistenteId: null,
            fatorInicial: fatorVinculo,
            unidadeInternaInicial: 'UN',
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
    final q =
        _db.produtoBox.query(Produto_.codigoBarras.equals(ean)).build();
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
              .and(
                VinculoFornecedorProduto_.fornecedor.equals(fornecedorId),
              ),
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
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final chaveNorm = nfe.chaveAcesso.replaceAll(RegExp(r'\D'), '');
      if (chaveNorm.length != 44) {
        throw StateError('Chave de acesso invalida para registro de importacao.');
      }
      final duplicada = _buscarImportacaoPorChave(chaveNorm);
      if (duplicada != null) {
        final quando = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
            .format(duplicada.dataHoraImportacao.toLocal());
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

        final qtdInterna =
            (linha.item.quantidadeComercial * fator).round();
        if (qtdInterna < 0) {
          throw StateError('Quantidade interna negativa (${linha.item.codigo}).');
        }

        final custoUnitInterno =
            linha.item.valorUnitarioComercial > 0 && fator > 0
                ? linha.item.valorUnitarioComercial / fator
                : 0.0;

        final nomeFantasiaOuRazao =
            fornecedor.nomeFantasia.trim().isNotEmpty
                ? fornecedor.nomeFantasia
                : fornecedor.razaoSocial;

        Produto produto;
        if (linha.produtoExistenteId != null) {
          final existente =
              _db.produtoBox.get(linha.produtoExistenteId!);
          if (existente == null) {
            throw StateError(
              'Produto id ${linha.produtoExistenteId} nao encontrado.',
            );
          }
          produto = existente;
          produto.estoqueReal = produto.estoqueReal + qtdInterna;
          produto.precoCusto = custoUnitInterno;
          produto.unidade = unidade;
          produto.fornecedor = nomeFantasiaOuRazao;
          if (linha.item.ncm.isNotEmpty) {
            produto.ncm = linha.item.ncm;
          }
          if (linha.item.codigoBarras.isNotEmpty &&
              produto.codigoBarras.isEmpty) {
            produto.codigoBarras = linha.item.codigoBarras;
          }
          _db.produtoBox.put(produto);
        } else {
          final codigoInterno = _gerarCodigoInterno(nfe, linha.item);
          produto = Produto(
            codigoInterno: codigoInterno,
            nome: linha.item.descricao.length > 120
                ? linha.item.descricao.substring(0, 120)
                : linha.item.descricao,
            descricao: linha.item.descricao,
            unidade: unidade,
            codigoBarras: linha.item.codigoBarras,
            ncm: linha.item.ncm,
            fornecedor: nomeFantasiaOuRazao,
            precoCusto: custoUnitInterno,
            precoVenda: 0,
            quantidadeMinima: 0,
            estoqueReal: qtdInterna,
          );
          _db.produtoBox.put(produto);
        }

        final vExistente =
            _buscarVinculo(fornecedor.id, linha.item.codigo);
        final v = vExistente ?? VinculoFornecedorProduto(
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
      }

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

    notificarAlteracaoParaRede();
  }

  FornecedorNfe? _buscarFornecedorPorCnpj(String cnpj) {
    final q = _db.fornecedorNfeBox.query(FornecedorNfe_.cnpj.equals(cnpj)).build();
    try {
      final list = q.find();
      return list.isEmpty ? null : list.first;
    } finally {
      q.close();
    }
  }

  String _gerarCodigoInterno(NfeXmlParseResult nfe, ItemNotaTemporario item) {
    final chave = nfe.chaveAcesso.replaceAll(RegExp(r'\D'), '');
    final sufixo = chave.length >= 8 ? chave.substring(chave.length - 8) : chave;
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
    final q =
        _db.produtoBox.query(Produto_.codigoInterno.equals(codigo)).build();
    try {
      return q.find().isEmpty;
    } finally {
      q.close();
    }
  }
}
