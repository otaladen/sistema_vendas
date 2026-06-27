import '../../data/models/conta_pagar.dart';
import '../../model/auditoria_evento.dart';
import '../../model/item_lista_compra.dart';
import '../../model/recado_loja.dart';
import '../../model/movimento_estoque.dart';
import '../../model/reajuste_preco.dart';
import '../../model/reajuste_preco_item.dart';

/// Codecs LAN para kardex, contas a pagar, reajuste de preco e auditoria.
class SyncEntityCodecOperacional {
  SyncEntityCodecOperacional._();

  static String? _dt(DateTime? d) => d?.toUtc().toIso8601String();
  static DateTime? _parseDt(String? s) =>
      s == null || s.isEmpty ? null : DateTime.tryParse(s)?.toUtc();

  // --- MovimentoEstoque ---
  static Map<String, dynamic> movimentoEstoqueParaMap(MovimentoEstoque m) => {
        'id': m.id,
        'tipoMovimento': m.tipoMovimento,
        'deltaFisico': m.deltaFisico,
        'deltaReserva': m.deltaReserva,
        'saldoFisicoAntes': m.saldoFisicoAntes,
        'saldoFisicoDepois': m.saldoFisicoDepois,
        'saldoReservaAntes': m.saldoReservaAntes,
        'saldoReservaDepois': m.saldoReservaDepois,
        'documentoReferencia': m.documentoReferencia,
        'motivo': m.motivo,
        'usuarioLogin': m.usuarioLogin,
        'registradoEm': _dt(m.registradoEm),
        'produtoId': m.produto.targetId,
      };

  static MovimentoEstoque movimentoEstoqueDeMap(Map<String, dynamic> m) {
    final linha = MovimentoEstoque(
      id: (m['id'] as num?)?.toInt() ?? 0,
      tipoMovimento: (m['tipoMovimento'] ?? '').toString(),
      deltaFisico: (m['deltaFisico'] as num?)?.toInt() ?? 0,
      deltaReserva: (m['deltaReserva'] as num?)?.toInt() ?? 0,
      saldoFisicoAntes: (m['saldoFisicoAntes'] as num?)?.toInt() ?? 0,
      saldoFisicoDepois: (m['saldoFisicoDepois'] as num?)?.toInt() ?? 0,
      saldoReservaAntes: (m['saldoReservaAntes'] as num?)?.toInt() ?? 0,
      saldoReservaDepois: (m['saldoReservaDepois'] as num?)?.toInt() ?? 0,
      documentoReferencia: (m['documentoReferencia'] ?? '').toString(),
      motivo: (m['motivo'] ?? '').toString(),
      usuarioLogin: (m['usuarioLogin'] ?? '').toString(),
      registradoEm: _parseDt((m['registradoEm'] ?? '').toString()),
    );
    final pid = (m['produtoId'] as num?)?.toInt() ?? 0;
    if (pid > 0) linha.produto.targetId = pid;
    return linha;
  }

  // --- ContaPagar ---
  static Map<String, dynamic> contaPagarParaMap(ContaPagar c) => {
        'id': c.id,
        'nfeChave': c.nfeChave,
        'numeroNota': c.numeroNota,
        'numeroParcela': c.numeroParcela,
        'dataEmissao': _dt(c.dataEmissao),
        'dataVencimento': _dt(c.dataVencimento),
        'valorParcela': c.valorParcela,
        'status': c.status,
        'dataPagamento': _dt(c.dataPagamento),
        'valorPago': c.valorPago,
        'fornecedorId': c.fornecedor.targetId,
      };

  static ContaPagar contaPagarDeMap(Map<String, dynamic> m) {
    final c = ContaPagar(
      id: (m['id'] as num?)?.toInt() ?? 0,
      nfeChave: m['nfeChave']?.toString(),
      numeroNota: m['numeroNota']?.toString(),
      numeroParcela: (m['numeroParcela'] ?? '').toString(),
      dataEmissao: _parseDt((m['dataEmissao'] ?? '').toString()) ?? DateTime.now(),
      dataVencimento:
          _parseDt((m['dataVencimento'] ?? '').toString()) ?? DateTime.now(),
      valorParcela: (m['valorParcela'] as num?)?.toDouble() ?? 0,
      status: (m['status'] ?? ContaPagarStatus.pendente).toString(),
      dataPagamento: _parseDt((m['dataPagamento'] ?? '').toString()),
      valorPago: (m['valorPago'] as num?)?.toDouble(),
    );
    final fid = (m['fornecedorId'] as num?)?.toInt() ?? 0;
    if (fid > 0) c.fornecedor.targetId = fid;
    return c;
  }

  // --- ReajustePreco (+ itens) ---
  static Map<String, dynamic> reajustePrecoParaMap(ReajustePreco r) => {
        'id': r.id,
        'criadoEm': _dt(r.criadoEm),
        'usuarioLogin': r.usuarioLogin,
        'usuarioNome': r.usuarioNome,
        'motivo': r.motivo,
        'modo': r.modo,
        'percentualSobrePreco': r.percentualSobrePreco,
        'margemPercentual': r.margemPercentual,
        'baseCusto': r.baseCusto,
        'arredondamento': r.arredondamento,
        'tabelasCsv': r.tabelasCsv,
        'somenteAtivos': r.somenteAtivos,
        'protegerAbaixoCusto': r.protegerAbaixoCusto,
        'margemMinimaPercentual': r.margemMinimaPercentual,
        'totalEscopo': r.totalEscopo,
        'totalAlterados': r.totalAlterados,
        'totalIgnorados': r.totalIgnorados,
        'estornado': r.estornado,
        'estornadoEm': _dt(r.estornadoEm),
        'estornadoPorLogin': r.estornadoPorLogin,
        'reajusteOrigemId': r.reajusteOrigemId,
        'itens': r.itens.map(reajustePrecoItemParaMap).toList(),
      };

  static Map<String, dynamic> reajustePrecoItemParaMap(ReajustePrecoItem i) => {
        'id': i.id,
        'produtoId': i.produtoId,
        'codigoInterno': i.codigoInterno,
        'nome': i.nome,
        'preco1Antes': i.preco1Antes,
        'preco2Antes': i.preco2Antes,
        'preco3Antes': i.preco3Antes,
        'preco1Depois': i.preco1Depois,
        'preco2Depois': i.preco2Depois,
        'preco3Depois': i.preco3Depois,
        'alterouPreco1': i.alterouPreco1,
        'alterouPreco2': i.alterouPreco2,
        'alterouPreco3': i.alterouPreco3,
        'reajusteId': i.reajuste.targetId,
      };

  static ReajustePreco reajustePrecoDeMap(Map<String, dynamic> m) {
    final r = ReajustePreco(
      id: (m['id'] as num?)?.toInt() ?? 0,
      usuarioLogin: (m['usuarioLogin'] ?? '').toString(),
      usuarioNome: (m['usuarioNome'] ?? '').toString(),
      motivo: (m['motivo'] ?? '').toString(),
      modo: (m['modo'] ?? 'percentual').toString(),
      percentualSobrePreco: (m['percentualSobrePreco'] as num?)?.toDouble() ?? 0,
      margemPercentual: (m['margemPercentual'] as num?)?.toDouble() ?? 0,
      baseCusto: (m['baseCusto'] ?? 'custo_digitado').toString(),
      arredondamento: (m['arredondamento'] ?? 'centavos').toString(),
      tabelasCsv: (m['tabelasCsv'] ?? 'preco1,preco2,preco3').toString(),
      somenteAtivos: m['somenteAtivos'] != false,
      protegerAbaixoCusto: m['protegerAbaixoCusto'] != false,
      margemMinimaPercentual:
          (m['margemMinimaPercentual'] as num?)?.toDouble() ?? 0,
      totalEscopo: (m['totalEscopo'] as num?)?.toInt() ?? 0,
      totalAlterados: (m['totalAlterados'] as num?)?.toInt() ?? 0,
      totalIgnorados: (m['totalIgnorados'] as num?)?.toInt() ?? 0,
      estornado: m['estornado'] == true,
      estornadoPorLogin: (m['estornadoPorLogin'] ?? '').toString(),
      reajusteOrigemId: (m['reajusteOrigemId'] as num?)?.toInt() ?? 0,
      criadoEm: _parseDt((m['criadoEm'] ?? '').toString()),
      estornadoEm: _parseDt((m['estornadoEm'] ?? '').toString()),
    );
    return r;
  }

  static ReajustePrecoItem reajustePrecoItemDeMap(Map<String, dynamic> m) {
    final i = ReajustePrecoItem(
      id: (m['id'] as num?)?.toInt() ?? 0,
      produtoId: (m['produtoId'] as num?)?.toInt() ?? 0,
      codigoInterno: (m['codigoInterno'] ?? '').toString(),
      nome: (m['nome'] ?? '').toString(),
      preco1Antes: (m['preco1Antes'] as num?)?.toDouble() ?? 0,
      preco2Antes: (m['preco2Antes'] as num?)?.toDouble() ?? 0,
      preco3Antes: (m['preco3Antes'] as num?)?.toDouble() ?? 0,
      preco1Depois: (m['preco1Depois'] as num?)?.toDouble() ?? 0,
      preco2Depois: (m['preco2Depois'] as num?)?.toDouble() ?? 0,
      preco3Depois: (m['preco3Depois'] as num?)?.toDouble() ?? 0,
      alterouPreco1: m['alterouPreco1'] == true,
      alterouPreco2: m['alterouPreco2'] == true,
      alterouPreco3: m['alterouPreco3'] == true,
    );
    final rid = (m['reajusteId'] as num?)?.toInt() ?? 0;
    if (rid > 0) i.reajuste.targetId = rid;
    return i;
  }

  // --- AuditoriaEvento ---
  static Map<String, dynamic> auditoriaEventoParaMap(AuditoriaEvento e) => {
        'id': e.id,
        'dataHora': _dt(e.dataHora),
        'usuarioLogin': e.usuarioLogin,
        'modulo': e.modulo,
        'acao': e.acao,
        'entidade': e.entidade,
        'entidadeId': e.entidadeId,
        'resumo': e.resumo,
        'detalhesJson': e.detalhesJson,
      };

  static AuditoriaEvento auditoriaEventoDeMap(Map<String, dynamic> m) =>
      AuditoriaEvento(
        id: (m['id'] as num?)?.toInt() ?? 0,
        dataHora: _parseDt((m['dataHora'] ?? '').toString()),
        usuarioLogin: (m['usuarioLogin'] ?? '').toString(),
        modulo: (m['modulo'] ?? '').toString(),
        acao: (m['acao'] ?? '').toString(),
        entidade: (m['entidade'] ?? '').toString(),
        entidadeId: (m['entidadeId'] ?? '').toString(),
        resumo: (m['resumo'] ?? '').toString(),
        detalhesJson: (m['detalhesJson'] ?? '').toString(),
      );

  // --- ItemListaCompra ---
  static Map<String, dynamic> itemListaCompraParaMap(ItemListaCompra i) => {
        'id': i.id,
        'produtoId': i.produto.targetId,
        'descricaoLivre': i.descricaoLivre,
        'quantidadeSugerida': i.quantidadeSugerida,
        'quantidadeRecebida': i.quantidadeRecebida,
        'unidade': i.unidade,
        'fornecedorTexto': i.fornecedorTexto,
        'prioridade': i.prioridade,
        'observacao': i.observacao,
        'origem': i.origem,
        'status': i.status,
        'criadoPor': i.criadoPor,
        'criadoEm': _dt(i.criadoEm),
        'resolvidoEm': _dt(i.resolvidoEm),
        'nfeChaveResolucao': i.nfeChaveResolucao,
      };

  static ItemListaCompra itemListaCompraDeMap(Map<String, dynamic> m) {
    final item = ItemListaCompra(
      id: (m['id'] as num?)?.toInt() ?? 0,
      descricaoLivre: (m['descricaoLivre'] ?? '').toString(),
      quantidadeSugerida: (m['quantidadeSugerida'] as num?)?.toInt() ?? 1,
      quantidadeRecebida: (m['quantidadeRecebida'] as num?)?.toInt() ?? 0,
      unidade: (m['unidade'] ?? 'UN').toString(),
      fornecedorTexto: (m['fornecedorTexto'] ?? '').toString(),
      prioridade: (m['prioridade'] ?? '').toString(),
      observacao: (m['observacao'] ?? '').toString(),
      origem: (m['origem'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      criadoPor: (m['criadoPor'] ?? '').toString(),
      criadoEm: _parseDt((m['criadoEm'] ?? '').toString()) ?? DateTime.now(),
      resolvidoEm: _parseDt((m['resolvidoEm'] ?? '').toString()),
      nfeChaveResolucao: (m['nfeChaveResolucao'] ?? '').toString(),
    );
    final pid = (m['produtoId'] as num?)?.toInt() ?? 0;
    if (pid > 0) item.produto.targetId = pid;
    return item;
  }

  // --- RecadoLoja ---
  static Map<String, dynamic> recadoLojaParaMap(RecadoLoja r) => {
        'id': r.id,
        'texto': r.texto,
        'prioridade': r.prioridade,
        'destinoTipo': r.destinoTipo,
        'destinoPerfil': r.destinoPerfil,
        'criadoPorLogin': r.criadoPorLogin,
        'criadoPorNome': r.criadoPorNome,
        'leiturasJson': r.leiturasJson,
        'ativo': r.ativo,
        'criadoEm': _dt(r.criadoEm),
      };

  static RecadoLoja recadoLojaDeMap(Map<String, dynamic> m) => RecadoLoja(
        id: (m['id'] as num?)?.toInt() ?? 0,
        texto: (m['texto'] ?? '').toString(),
        prioridade: (m['prioridade'] ?? 'normal').toString(),
        destinoTipo: (m['destinoTipo'] ?? 'todos').toString(),
        destinoPerfil: (m['destinoPerfil'] ?? '').toString(),
        criadoPorLogin: (m['criadoPorLogin'] ?? '').toString(),
        criadoPorNome: (m['criadoPorNome'] ?? '').toString(),
        leiturasJson: (m['leiturasJson'] ?? '[]').toString(),
        ativo: m['ativo'] != false,
        criadoEm: _parseDt((m['criadoEm'] ?? '').toString()) ?? DateTime.now(),
      );
}
