import 'package:flutter/foundation.dart';

import '../../domain/entrega_filtro_util.dart';
import '../../domain/entrega_venda_helper.dart';
import '../../domain/entregas/agenda_carreto_ocupacao.dart';
import '../../domain/entregas/loja_origem_mercadoria.dart';
import '../../domain/filtro_listagem_entregas.dart';
import '../../domain/fiscal/nfe_venda_sync.dart';
import '../../domain/fiscal/venda_nfce_obrigatoria_helper.dart';
import '../../domain/limite_credito_helper.dart';
import '../../domain/listagem_vendas_periodo.dart';
import '../../domain/pagamento_orcamento.dart';
import '../../domain/ultimas_vendas_finalizadas_ordenacao.dart';
import '../../domain/venda_finalizacao_caixa_helper.dart';
import '../../model/cliente.dart';
import '../caixa_sessao_repository.dart';
import '../../model/historico_entrega.dart';
import '../../model/item_venda.dart';
import '../../model/produto.dart';
import '../../model/vendedor.dart';
import '../../model/registro_devolucao.dart';
import '../../model/recebimento_fiado.dart';
import '../../model/titulo_receber.dart';
import '../../model/venda.dart';
import '../sync/sync_entity_codec_extras.dart';
import '../titulo_receber_repository.dart';
import '../venda_repository.dart';
import 'lan_api_client.dart';
import 'lan_api_event_hub.dart';

/// Vendas/orcamentos via API (cache em memoria + mutacoes remotas).
class VendaApiRepository extends ChangeNotifier {
  VendaApiRepository(this._client);

  final LanApiClient _client;
  final Map<int, Venda> _porId = {};
  List<Venda> _orcamentos = [];
  final Map<int, List<ItemVenda>> _itens = {};
  List<TituloReceberResumoLinha> _titulosAbertos = [];
  final Map<int, TituloReceber> _titulosPorId = {};
  final Map<int, RecebimentoFiado> _recebimentosPorId = {};
  final Map<int, List<RecebimentoFiado>> _recebimentosPorCliente = {};
  final Map<int, List<TituloReceber>> _titulosQuitadosPorCliente = {};
  /// Saldo restante do cliente apos um recebimento (cache do payload da API).
  final Map<int, double> _saldoAposRecebimento = {};

  Never get objectBox =>
      throw StateError('Terminal leve: sem ObjectBox local.');

  bool get _offline => LanApiEventHub.instance.deveBloquearOperacoes;

  void _exigirServidorOnline() {
    if (_offline) {
      throw LanApiException(LanApiEventHub.msgServidorOffline);
    }
  }

  late final _RecebimentosApi recebimentos = _RecebimentosApi(this);
  late final _TitulosApi titulos = _TitulosApi(this);

  Future<void> hidratarTitulos() async {
    _exigirServidorOnline();
    final raw = await _client.listarTitulosAbertos();
    _titulosAbertos = raw
        .map((m) {
          final titulo = SyncEntityCodecExtras.tituloReceberDeMap(m);
          if (titulo.id > 0) _titulosPorId[titulo.id] = titulo;
          return TituloReceberResumoLinha(
            titulo: titulo,
            numeroOrcamento: (m['numeroOrcamento'] as num?)?.toInt() ?? 0,
            nomeCliente: (m['nomeCliente'] ?? '').toString(),
            diasAtraso: (m['diasAtraso'] as num?)?.toInt() ?? 0,
          );
        })
        .toList(growable: false);
    notifyListeners();
  }

  Future<int> registrarRecebimentoTituloRemoto({
    required int tituloId,
    required double valorRecebido,
    required String formaPagamento,
    String observacao = '',
  }) async {
    _exigirServidorOnline();
    final m = await _client.receberTitulo(
      tituloId,
      valorRecebido: valorRecebido,
      formaPagamento: formaPagamento,
      observacao: observacao,
    );
    _cacheRecebimentoPayload(m);
    await hidratarTitulos();
    return (m['id'] as num?)?.toInt() ?? 0;
  }

  void _cacheRecebimentoPayload(Map<String, dynamic> m) {
    final item = m['item'];
    if (item is Map) {
      final rec = SyncEntityCodecExtras.recebimentoFiadoDeMap(
        Map<String, dynamic>.from(item),
      );
      if (rec.id > 0) {
        _recebimentosPorId[rec.id] = rec;
        final cid = rec.cliente.targetId;
        if (cid > 0) {
          final lista = List<RecebimentoFiado>.from(
            _recebimentosPorCliente[cid] ?? const [],
          );
          lista.removeWhere((e) => e.id == rec.id);
          lista.insert(0, rec);
          _recebimentosPorCliente[cid] = lista;
        }
        final saldo = (m['saldoRestanteCliente'] as num?)?.toDouble();
        if (saldo != null) _saldoAposRecebimento[rec.id] = saldo;
      }
    }
    final alocados = m['titulosAlocados'];
    if (alocados is List) {
      for (final raw in alocados) {
        if (raw is! Map) continue;
        final t = SyncEntityCodecExtras.tituloReceberDeMap(
          Map<String, dynamic>.from(raw),
        );
        if (t.id > 0) _titulosPorId[t.id] = t;
      }
    }
  }

  Future<RecebimentoFiado?> obterRecebimentoRemoto(int id) async {
    _exigirServidorOnline();
    final cached = _recebimentosPorId[id];
    if (cached != null) return cached;
    final m = await _client.obterRecebimento(id);
    _cacheRecebimentoPayload(m);
    return _recebimentosPorId[id];
  }

  /// Saldo de fiado em aberto do cliente logo apos o recebimento [recebimentoId].
  double? saldoRestanteAposRecebimento(int recebimentoId) =>
      _saldoAposRecebimento[recebimentoId];

  Future<List<RecebimentoFiado>> listarRecebimentosPorClienteRemoto(
    int clienteId,
  ) async {
    _exigirServidorOnline();
    final raw = await _client.listarRecebimentosPorCliente(clienteId);
    final lista = raw
        .map(SyncEntityCodecExtras.recebimentoFiadoDeMap)
        .toList(growable: false);
    _recebimentosPorCliente[clienteId] = lista;
    for (final r in lista) {
      _recebimentosPorId[r.id] = r;
    }
    notifyListeners();
    return lista;
  }

  Future<List<TituloReceber>> listarTitulosQuitadosPorClienteRemoto(
    int clienteId, {
    int limite = 100,
  }) async {
    _exigirServidorOnline();
    final raw = await _client.listarTitulosQuitadosPorCliente(
      clienteId,
      limit: limite,
    );
    final lista = raw
        .map(SyncEntityCodecExtras.tituloReceberDeMap)
        .toList(growable: false);
    _titulosQuitadosPorCliente[clienteId] = lista;
    for (final t in lista) {
      _titulosPorId[t.id] = t;
    }
    notifyListeners();
    return lista;
  }

  Future<void> hidratarOrcamentos({int limit = 120}) async {
    _exigirServidorOnline();
    final items = await _client.listarOrcamentos(limit: limit);
    _orcamentos = items
        .where((v) => v.status == 'orcamento' && !v.cancelada)
        .toList();
    for (final v in items) {
      _porId[v.id] = v;
      _cacheItensDaVenda(v);
    }
    notifyListeners();
  }

  Future<void> hidratarVendasFinalizadas({int limit = 120}) async {
    _exigirServidorOnline();
    final items = await _client.listarVendas(
      status: 'finalizada',
      limit: limit,
    );
    for (final v in items) {
      _porId[v.id] = v;
      _cacheItensDaVenda(v);
    }
    _vendasFinalizadas = items
        .where((v) => v.status == 'finalizada' && !v.cancelada)
        .toList();
    notifyListeners();
  }

  ListagemVendasPagina? _listagemRemota;
  Object? _listagemFiltroAssinatura;

  Object _assinaturaFiltroListagem(dynamic filtro) {
    try {
      return (
        filtro.textoBusca,
        filtro.dataInicioUtc,
        filtro.dataFimUtc,
        filtro.filtroCancelamento,
        filtro.canceladaPorFiltro,
        filtro.formaPagamento,
        filtro.tipoEntrega,
        filtro.entregaPendente,
        filtro.filtroFiscal,
        filtro.clienteId,
        filtro.vendedorId,
      );
    } catch (_) {
      return filtro;
    }
  }

  /// Baixa uma pagina da listagem no servidor com os filtros atuais.
  Future<ListagemVendasPagina> hidratarListagemVendas(
    dynamic filtro, {
    required int offset,
    required int limite,
  }) async {
    _exigirServidorOnline();
    DateTime? desde;
    DateTime? ate;
    String filtroCancelamento = 'ativas';
    String canceladaPor = 'todos';
    String formaPagamento = 'todos';
    String tipoEntrega = 'todos';
    String entregaPendente = 'todos';
    String filtroFiscal = 'todos';
    String busca = '';
    int? clienteId;
    try {
      desde = filtro.dataInicioUtc as DateTime?;
      ate = filtro.dataFimUtc as DateTime?;
      filtroCancelamento = (filtro.filtroCancelamento ?? 'ativas').toString();
      canceladaPor = (filtro.canceladaPorFiltro ?? 'todos').toString();
      formaPagamento = (filtro.formaPagamento ?? 'todos').toString();
      tipoEntrega = (filtro.tipoEntrega ?? 'todos').toString();
      entregaPendente = (filtro.entregaPendente ?? 'todos').toString();
      filtroFiscal = (filtro.filtroFiscal ?? 'todos').toString();
      busca = (filtro.textoBusca ?? '').toString();
      clienteId = filtro.clienteId as int?;
    } catch (_) {}

    final pagina = await _client.listarVendasPagina(
      status: 'finalizada',
      limit: limite,
      offset: offset,
      desde: desde,
      ate: ate,
      clienteId: clienteId,
      filtroCancelamento: filtroCancelamento,
      formaPagamento: formaPagamento,
      tipoEntrega: tipoEntrega,
      entregaPendente: entregaPendente,
      filtroFiscal: filtroFiscal,
      busca: busca,
      canceladaPor: canceladaPor,
    );
    for (final v in pagina.vendas) {
      _vincularAlvos(v);
      _porId[v.id] = v;
      _cacheItensDaVenda(v);
      final i = _vendasFinalizadas.indexWhere((e) => e.id == v.id);
      if (i >= 0) {
        _vendasFinalizadas[i] = v;
      } else {
        _vendasFinalizadas.add(v);
      }
    }
    _listagemRemota = pagina;
    _listagemFiltroAssinatura = _assinaturaFiltroListagem(filtro);
    notifyListeners();
    return pagina;
  }

  /// Todas as vendas do filtro (paginas acumuladas) para CSV/PDF no terminal.
  Future<List<Venda>> listarListagemVendasExportacao(
    dynamic filtro, {
    int pageSize = 250,
    int teto = 20000,
  }) async {
    _exigirServidorOnline();
    DateTime? desde;
    DateTime? ate;
    String filtroCancelamento = 'ativas';
    String canceladaPor = 'todos';
    String formaPagamento = 'todos';
    String tipoEntrega = 'todos';
    String entregaPendente = 'todos';
    String filtroFiscal = 'todos';
    String busca = '';
    int? clienteId;
    try {
      desde = filtro.dataInicioUtc as DateTime?;
      ate = filtro.dataFimUtc as DateTime?;
      filtroCancelamento = (filtro.filtroCancelamento ?? 'ativas').toString();
      canceladaPor = (filtro.canceladaPorFiltro ?? 'todos').toString();
      formaPagamento = (filtro.formaPagamento ?? 'todos').toString();
      tipoEntrega = (filtro.tipoEntrega ?? 'todos').toString();
      entregaPendente = (filtro.entregaPendente ?? 'todos').toString();
      filtroFiscal = (filtro.filtroFiscal ?? 'todos').toString();
      busca = (filtro.textoBusca ?? '').toString();
      clienteId = filtro.clienteId as int?;
    } catch (_) {}

    final all = <Venda>[];
    var offset = 0;
    while (offset < teto) {
      final pagina = await _client.listarVendasPagina(
        status: 'finalizada',
        limit: pageSize,
        offset: offset,
        desde: desde,
        ate: ate,
        clienteId: clienteId,
        filtroCancelamento: filtroCancelamento,
        formaPagamento: formaPagamento,
        tipoEntrega: tipoEntrega,
        entregaPendente: entregaPendente,
        filtroFiscal: filtroFiscal,
        busca: busca,
        canceladaPor: canceladaPor,
      );
      for (final v in pagina.vendas) {
        _vincularAlvos(v);
        _porId[v.id] = v;
        _cacheItensDaVenda(v);
      }
      all.addAll(pagina.vendas);
      if (pagina.vendas.length < pageSize || all.length >= pagina.total) {
        break;
      }
      offset += pagina.vendas.length;
    }
    return all;
  }

  Future<void> hidratarEntregas({int limit = 500}) async {
    _exigirServidorOnline();
    final items = await _client.listarEntregas(limit: limit);
    _entregas = List<Venda>.from(items);
    for (final v in items) {
      _porId[v.id] = v;
      _cacheItensDaVenda(v);
    }
    notifyListeners();
  }

  Future<AgendaCarretoOcupacaoMes> obterOcupacaoAgendaCarretoMes(
    DateTime mesRef, {
    bool incluirProdutos = true,
  }) async {
    _exigirServidorOnline();
    return _client.obterOcupacaoAgendaCarreto(
      mesRef,
      incluirProdutos: incluirProdutos,
    );
  }

  List<Venda> _vendasFinalizadas = [];
  List<Venda> _entregas = [];

  /// Vendas baixadas para os relatorios, indexadas por id.
  final Map<int, Venda> _vendasRelatorio = {};
  DateTime? _janelaRelatorioInicio;
  DateTime? _janelaRelatorioFim;

  final List<RegistroDevolucao> _devolucoes = [];
  final Map<int, double> _impactoFaturamentoPorRegistro = {};
  final Map<int, double> _impactoLucroPorRegistro = {};
  final Map<int, int> _vendedorPorRegistroDevolucao = {};
  final Map<int, int> _clientePorRegistroDevolucao = {};
  final List<HistoricoEntrega> _historicoEntregas = [];
  final Map<int, int> _vendaPorHistoricoEntrega = {};

  /// Vinculos resolvidos pelos outros repositorios da API (injetados no boot).
  Cliente? Function(int clienteId)? resolverCliente;
  Vendedor? Function(int vendedorId)? resolverVendedor;
  Produto? Function(int produtoId)? resolverProduto;

  bool get relatorioCarregado => _janelaRelatorioInicio != null;

  /// True quando a janela bateu o teto de paginas e pode faltar nota.
  bool relatorioJanelaTruncada = false;

  static const int _paginaRelatorio = 2500;
  static const int _tetoNotasRelatorio = 100000;

  /// Baixa (e mantem) a janela de vendas usada pelos relatorios.
  Future<void> garantirPeriodoRelatorioCarregado(
    DateTime inicio,
    DateTime fim,
  ) async {
    final ini = DateTime(inicio.year, inicio.month, inicio.day).toUtc();
    final fimDia = DateTime(fim.year, fim.month, fim.day, 23, 59, 59).toUtc();
    final cobre =
        _janelaRelatorioInicio != null &&
        _janelaRelatorioFim != null &&
        !ini.isBefore(_janelaRelatorioInicio!) &&
        !fimDia.isAfter(_janelaRelatorioFim!);
    if (cobre) return;
    _exigirServidorOnline();
    final novoInicio = _janelaRelatorioInicio == null
        ? ini
        : (ini.isBefore(_janelaRelatorioInicio!) ? ini : _janelaRelatorioInicio!);
    final novoFim = _janelaRelatorioFim == null
        ? fimDia
        : (fimDia.isAfter(_janelaRelatorioFim!) ? fimDia : _janelaRelatorioFim!);
    _vendasRelatorio.clear();
    var offset = 0;
    var truncada = false;
    while (offset < _tetoNotasRelatorio) {
      final pagina = await _client.listarVendas(
        status: 'todas',
        desde: novoInicio,
        ate: novoFim,
        limit: _paginaRelatorio,
        offset: offset,
      );
      for (final v in pagina) {
        _vincularAlvos(v);
        _vendasRelatorio[v.id] = v;
        _porId[v.id] = v;
      }
      offset += pagina.length;
      if (pagina.length < _paginaRelatorio) {
        truncada = false;
        break;
      }
      if (offset >= _tetoNotasRelatorio) {
        truncada = true;
        break;
      }
    }
    relatorioJanelaTruncada = truncada;
    await _hidratarDevolucoes(novoInicio, novoFim);
    await _hidratarHistoricoEntregas(novoInicio, novoFim);
    _janelaRelatorioInicio = novoInicio;
    _janelaRelatorioFim = novoFim;
    notifyListeners();
  }

  Future<void> _hidratarDevolucoes(DateTime inicio, DateTime fim) async {
    try {
      final brutos = await _client.listarDevolucoes(desde: inicio, ate: fim);
      _devolucoes.clear();
      _impactoFaturamentoPorRegistro.clear();
      _impactoLucroPorRegistro.clear();
      _vendedorPorRegistroDevolucao.clear();
      _clientePorRegistroDevolucao.clear();
      for (final m in brutos) {
        final reg = SyncEntityCodecExtras.registroDevolucaoDeMap(m);
        final origemId = (m['vendaOrigemId'] as num?)?.toInt() ?? 0;
        reg.vendaOrigem.targetId = origemId;
        final origem = _vendasRelatorio[origemId];
        if (origem != null) reg.vendaOrigem.target = origem;
        final entradas = m['linhasEntrada'];
        if (entradas is List) {
          for (final raw in entradas.whereType<Map>()) {
            final lm = Map<String, dynamic>.from(raw);
            final linha = SyncEntityCodecExtras.linhaDevolucaoDeMap(lm)
              ..produto.targetId = (lm['produtoId'] as num?)?.toInt() ?? 0;
            reg.linhasEntrada.add(linha);
          }
        }
        final saidas = m['linhasSaidaTroca'];
        if (saidas is List) {
          for (final raw in saidas.whereType<Map>()) {
            final lm = Map<String, dynamic>.from(raw);
            final linha = SyncEntityCodecExtras.linhaTrocaDeMap(lm)
              ..produto.targetId = (lm['produtoId'] as num?)?.toInt() ?? 0;
            reg.linhasSaidaTroca.add(linha);
          }
        }
        _devolucoes.add(reg);
        _impactoFaturamentoPorRegistro[reg.id] =
            (m['impactoFaturamento'] as num?)?.toDouble() ?? 0;
        _impactoLucroPorRegistro[reg.id] =
            (m['impactoLucro'] as num?)?.toDouble() ?? 0;
        _vendedorPorRegistroDevolucao[reg.id] =
            (m['vendedorId'] as num?)?.toInt() ?? 0;
        _clientePorRegistroDevolucao[reg.id] =
            (m['clienteId'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      debugPrint('Terminal leve: devolucoes indisponiveis: $e');
    }
  }

  Future<void> _hidratarHistoricoEntregas(
    DateTime inicio,
    DateTime fim,
  ) async {
    try {
      final brutos = await _client.listarHistoricoEntregas(
        desde: inicio,
        ate: fim,
      );
      _historicoEntregas.clear();
      _vendaPorHistoricoEntrega.clear();
      for (final m in brutos) {
        final h = SyncEntityCodecExtras.historicoEntregaDeMap(m);
        final vendaId = (m['vendaId'] as num?)?.toInt() ?? 0;
        h.venda.targetId = vendaId;
        final venda = _vendasRelatorio[vendaId];
        if (venda != null) h.venda.target = venda;
        _historicoEntregas.add(h);
        _vendaPorHistoricoEntrega[h.id] = vendaId;
      }
    } catch (e) {
      debugPrint('Terminal leve: historico de entregas indisponivel: $e');
    }
  }

  List<Venda> listarTodas() =>
      List<Venda>.unmodifiable(_vendasRelatorio.values);

  List<Venda> listarPorPeriodo(PeriodoFiltro periodo) {
    final ini = periodo.inicio.toUtc();
    final fim = periodo.fim.toUtc();
    return _vendasRelatorio.values.where((v) {
      final d = v.data.toUtc();
      return !d.isBefore(ini) && !d.isAfter(fim);
    }).toList();
  }

  List<Venda> _finalizadasNoPeriodo(DateTime inicio, DateTime fim) {
    final ini = inicio.toUtc();
    final f = fim.toUtc();
    return _vendasRelatorio.values.where((v) {
      if (v.status != 'finalizada' || v.cancelada) return false;
      final d = v.data.toUtc();
      return !d.isBefore(ini) && !d.isAfter(f);
    }).toList();
  }

  List<VendaPromocaoRelatorioLinha> listarVendasPromocaoPeriodo({
    required DateTime inicio,
    required DateTime fim,
    int? promocaoId,
  }) {
    final out = <VendaPromocaoRelatorioLinha>[];
    for (final v in _finalizadasNoPeriodo(inicio, fim)) {
      final nomeCli = _nomeCliente(v.cliente.targetId);
      final nota = v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id;
      for (final item in itensDaVendaSafe(v)) {
        if (item.promocaoId <= 0) continue;
        if (promocaoId != null && item.promocaoId != promocaoId) continue;
        final qtd = item.quantidade - item.quantidadeDevolvida;
        if (qtd <= 0) continue;
        out.add(
          VendaPromocaoRelatorioLinha(
            dataVenda: v.data.toLocal(),
            vendaId: v.id,
            nota: nota,
            promocaoId: item.promocaoId,
            promocaoNome: item.promocaoNomeSnapshot.trim().isNotEmpty
                ? item.promocaoNomeSnapshot.trim()
                : 'Promocao #${item.promocaoId}',
            produtoNome: item.nomeProduto,
            codigoInterno: _codigoProduto(item.produto.targetId),
            quantidade: qtd,
            valorUnitario: item.precoUnitario,
            total: qtd * item.precoUnitario,
            lucro: qtd * (item.precoUnitario - item.precoCustoUnitario),
            clienteNome: nomeCli.isEmpty ? '-' : nomeCli,
            itemVendaId: item.id,
          ),
        );
      }
    }
    out.sort((a, b) {
      final c = b.dataVenda.compareTo(a.dataVenda);
      return c != 0 ? c : b.vendaId.compareTo(a.vendaId);
    });
    return out;
  }

  List<SaidaProdutoRelatorioLinha> listarSaidasProdutoPeriodo({
    required int produtoId,
    required DateTime inicio,
    required DateTime fim,
  }) {
    final out = <SaidaProdutoRelatorioLinha>[];
    for (final v in _finalizadasNoPeriodo(inicio, fim)) {
      final nomeCli = _nomeCliente(v.cliente.targetId);
      final nota = v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id;
      for (final item in itensDaVendaSafe(v)) {
        if (item.produto.targetId != produtoId) continue;
        final qtd = item.quantidade - item.quantidadeDevolvida;
        if (qtd <= 0) continue;
        final brutoLinha = qtd * item.precoUnitario;
        final somaItens = v.somaSubtotalItens;
        final acrescimo = somaItens > 0.0001
            ? v.descontoImplicitoTotal * (brutoLinha / somaItens)
            : 0.0;
        out.add(
          SaidaProdutoRelatorioLinha(
            dataVenda: v.data.toLocal(),
            quantidade: qtd,
            valorUnitario: item.precoUnitario,
            total: brutoLinha,
            nota: nota,
            lucro: qtd * (item.precoUnitario - item.precoCustoUnitario),
            acrescimo: acrescimo,
            clienteNome: nomeCli.isEmpty ? '-' : nomeCli,
            vendaId: v.id,
            itemVendaId: item.id,
          ),
        );
      }
    }
    out.sort((a, b) => a.dataVenda.compareTo(b.dataVenda));
    return out;
  }

  ImpactosDevolucaoTrocaPeriodo calcularImpactosDevolucaoTrocaPeriodo(
    PeriodoFiltro periodo,
  ) {
    var faturamento = 0.0;
    var lucro = 0.0;
    final porVendedorFat = <int, double>{};
    final porVendedorLuc = <int, double>{};
    final porClienteFat = <int, double>{};
    final porClienteLuc = <int, double>{};
    final porVendaFat = <int, double>{};
    final porVendaLuc = <int, double>{};
    for (final r in listarRegistrosDevolucaoPorPeriodo(periodo)) {
      final fat = impactoFaturamentoRegistro(r);
      final luc = impactoLucroRegistro(r);
      faturamento += fat;
      lucro += luc;
      final vendedorId = _vendedorPorRegistroDevolucao[r.id] ?? 0;
      final clienteId = _clientePorRegistroDevolucao[r.id] ?? 0;
      porVendedorFat[vendedorId] = (porVendedorFat[vendedorId] ?? 0) + fat;
      porVendedorLuc[vendedorId] = (porVendedorLuc[vendedorId] ?? 0) + luc;
      porClienteFat[clienteId] = (porClienteFat[clienteId] ?? 0) + fat;
      porClienteLuc[clienteId] = (porClienteLuc[clienteId] ?? 0) + luc;
      final vendaId = r.vendaOrigem.targetId;
      if (vendaId > 0) {
        porVendaFat[vendaId] = (porVendaFat[vendaId] ?? 0) + fat;
        porVendaLuc[vendaId] = (porVendaLuc[vendaId] ?? 0) + luc;
      }
    }
    return ImpactosDevolucaoTrocaPeriodo(
      impactoFaturamentoTotal: faturamento,
      impactoLucroTotal: lucro,
      porVendedorFaturamento: porVendedorFat,
      porVendedorLucro: porVendedorLuc,
      porClienteFaturamento: porClienteFat,
      porClienteLucro: porClienteLuc,
      porVendaFaturamento: porVendaFat,
      porVendaLucro: porVendaLuc,
    );
  }

  String _nomeCliente(int clienteId) {
    if (clienteId <= 0) return '';
    return (resolverCliente?.call(clienteId)?.nomeRazao ?? '').trim();
  }

  String _codigoProduto(int produtoId) {
    if (produtoId <= 0) return '';
    return (resolverProduto?.call(produtoId)?.codigoInterno ?? '').trim();
  }

  List<Venda> listarListagemVendasCompleto(dynamic filtro) {
    return List.unmodifiable(_filtrarListagem(_vendasFinalizadas, filtro));
  }

  ListagemVendasPagina listarListagemVendasPaginaComTotal(
    dynamic filtro, {
    required int offset,
    required int limite,
  }) {
    final remota = _listagemRemota;
    if (remota != null &&
        _listagemFiltroAssinatura == _assinaturaFiltroListagem(filtro)) {
      return remota;
    }
    final todas = _filtrarListagem(_vendasFinalizadas, filtro);
    final total = todas.length;
    final totalValor = todas.fold<double>(0, (s, v) => s + v.total);
    if (offset >= total || limite <= 0) {
      return ListagemVendasPagina(
        vendas: const [],
        total: total,
        totalValor: totalValor,
      );
    }
    final end = (offset + limite).clamp(0, total);
    return ListagemVendasPagina(
      vendas: todas.sublist(offset, end),
      total: total,
      totalValor: totalValor,
    );
  }

  List<Venda> _filtrarListagem(List<Venda> base, dynamic filtro) {
    var out = List<Venda>.from(base);
    if (filtro == null) return out;

    DateTime? dataInicioUtc;
    DateTime? dataFimUtc;
    String filtroCancelamento = 'ativas';
    String canceladaPorFiltro = 'todos';
    String formaPagamento = 'todos';
    String tipoEntrega = 'todos';
    String entregaPendente = 'todos';
    String filtroFiscal = 'todos';
    String textoBusca = '';
    int? clienteId;
    int? vendedorId;
    try {
      dataInicioUtc = filtro.dataInicioUtc as DateTime?;
      dataFimUtc = filtro.dataFimUtc as DateTime?;
      filtroCancelamento = (filtro.filtroCancelamento ?? 'ativas').toString();
      canceladaPorFiltro = (filtro.canceladaPorFiltro ?? 'todos').toString();
      formaPagamento = (filtro.formaPagamento ?? 'todos').toString();
      tipoEntrega = (filtro.tipoEntrega ?? 'todos').toString();
      entregaPendente = (filtro.entregaPendente ?? 'todos').toString();
      filtroFiscal = (filtro.filtroFiscal ?? 'todos').toString();
      textoBusca = (filtro.textoBusca ?? '').toString().trim().toLowerCase();
      clienteId = filtro.clienteId as int?;
      vendedorId = filtro.vendedorId as int?;
    } catch (_) {
      return out;
    }

    out = out.where((v) {
      if (!ListagemVendasPeriodo.noIntervaloUtc(
        v,
        inicioUtc: dataInicioUtc,
        fimUtc: dataFimUtc,
      )) {
        return false;
      }
      if (filtroCancelamento == 'ativas' && v.cancelada) return false;
      if (filtroCancelamento == 'canceladas' && !v.cancelada) return false;
      if (canceladaPorFiltro != 'todos' &&
          v.canceladaPor.trim() != canceladaPorFiltro) {
        return false;
      }
      if (formaPagamento != 'todos' && v.formaPagamento != formaPagamento) {
        return false;
      }
      if (tipoEntrega != 'todos') {
        if (tipoEntrega == EntregaVendaHelper.tipoEntregaLoja) {
          if (v.tipoEntrega != EntregaVendaHelper.tipoEntregaLoja &&
              v.tipoEntrega != EntregaVendaHelper.tipoMisto) {
            return false;
          }
        } else if (v.tipoEntrega != tipoEntrega) {
          return false;
        }
      }
      if (entregaPendente == 'sim' && !v.entregaPendente) return false;
      if (entregaPendente == 'nao' && v.entregaPendente) return false;
      if (clienteId != null && clienteId > 0 && v.cliente.targetId != clienteId) {
        return false;
      }
      if (vendedorId != null &&
          vendedorId > 0 &&
          v.vendedor.targetId != vendedorId) {
        return false;
      }
      if (filtroFiscal == 'sem_nfce_eletronico' &&
          !VendaNfceObrigatoriaHelper.ehPendenteEmissao(v)) {
        return false;
      }
      if (textoBusca.isNotEmpty) {
        final n = v.numeroOrcamento > 0 ? '${v.numeroOrcamento}' : '${v.id}';
        final cli = _nomeCliente(v.cliente.targetId).toLowerCase();
        final hay = '$n ${v.nfceNumero} ${v.nfeNumero} $cli'.toLowerCase();
        if (!hay.contains(textoBusca)) return false;
      }
      return true;
    }).toList();

    out.sort((a, b) => b.data.compareTo(a.data));
    return out;
  }

  void _cacheItensDaVenda(Venda v) {
    final anexos = LanApiClient.itensExtraidos[v];
    if (anexos != null && anexos.isNotEmpty) {
      _itens[v.id] = List<ItemVenda>.from(anexos);
      return;
    }
    try {
      final locais = v.itens.toList();
      if (locais.isNotEmpty) {
        _itens[v.id] = locais;
      }
    } catch (_) {}
  }

  /// Apos cancelamento remoto: tira da lista de ultimas vendas do caixa.
  void _aplicarVendaCanceladaNoCache(Venda v) {
    _porId[v.id] = v;
    _orcamentos.removeWhere((e) => e.id == v.id);
    _vendasFinalizadas.removeWhere((e) => e.id == v.id);
    _vendasRelatorio[v.id] = v;
    _cacheItensDaVenda(v);
  }

  /// Atualiza venda finalizada no cache (ex.: apos emitir NFC-e no terminal).
  Future<Venda?> atualizarVendaFinalizadaNoCache(int vendaId) async {
    if (vendaId <= 0) return null;
    _exigirServidorOnline();
    final v = await _client.obterVenda(vendaId);
    if (v == null) return null;
    _porId[vendaId] = v;
    _cacheItensDaVenda(v);
    if (v.cancelada || v.status != 'finalizada') {
      _vendasFinalizadas.removeWhere((e) => e.id == vendaId);
    } else {
      final i = _vendasFinalizadas.indexWhere((e) => e.id == vendaId);
      if (i >= 0) {
        _vendasFinalizadas[i] = v;
      } else {
        _vendasFinalizadas.insert(0, v);
      }
    }
    _vendasRelatorio[vendaId] = v;
    notifyListeners();
    return v;
  }

  /// Itens da venda sem depender de ToMany (relatorios / ABC / promo).
  List<ItemVenda> itensDaVendaSafe(Venda v) {
    final cached = _itens[v.id];
    if (cached != null && cached.isNotEmpty) {
      return List.unmodifiable(cached);
    }
    _cacheItensDaVenda(v);
    return List.unmodifiable(_itens[v.id] ?? const []);
  }

  /// Liga cliente/vendedor/produto via resolvers (sem depender de ToOne.target).
  void _vincularAlvos(Venda v) {
    // So preenche cache de itens; UI resolve cliente/vendedor por targetId.
    _cacheItensDaVenda(v);
  }

  List<String> listarDistintosCanceladaPor() {
    final unicos = <String>{};
    for (final v in _vendasFinalizadas) {
      if (!v.cancelada) continue;
      final t = v.canceladaPor.trim();
      if (t.isNotEmpty) unicos.add(t);
    }
    final lista = unicos.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return lista;
  }

  int contarOrcamentosPendentesAte(DateTime ate) {
    final fim = DateTime(ate.year, ate.month, ate.day, 23, 59, 59).toUtc();
    return _orcamentos.where((v) => !v.data.isAfter(fim)).length;
  }

  int cancelarOrcamentosPendentesAte(
    DateTime ate, {
    String motivo = '',
    String canceladaPor = '',
  }) =>
      0;

  /// Cancela orcamentos pendentes ate [ate] via API (terminal leve).
  Future<int> cancelarOrcamentosPendentesAteRemoto(
    DateTime ate, {
    String motivo = '',
    String canceladaPor = '',
  }) async {
    _exigirServidorOnline();
    final alvo = listarOrcamentosPendentes(ate: ate);
    final motivoPadrao = motivo.trim().isEmpty
        ? 'Manutencao: limpeza de orcamentos em aberto'
        : motivo.trim();
    var n = 0;
    for (final v in List<Venda>.from(alvo)) {
      await cancelarVendaRemoto(
        v.id,
        motivo: motivoPadrao,
        canceladaPor: canceladaPor,
      );
      n++;
    }
    return n;
  }

  void cancelarVenda(
    int vendaId, {
    String motivo = '',
    String canceladaPor = '',
    bool omitirAuditoriaIndividual = false,
    dynamic usuarioExecutor,
  }) {
    throw StateError(
      'Terminal leve: use cancelarVendaRemoto (async) na listagem/cancelamento.',
    );
  }

  void vincularClienteVendaFinalizada(int vendaId, int clienteId) {
    throw StateError(
      'Terminal leve: use vincularClienteVendaFinalizadaRemoto (async).',
    );
  }

  int registrarOrcamentoFreteRetiradaFutura({
    required int vendaMaeId,
    required double valorFreteCobrado,
    required DadosPagamentoOrcamento pagamento,
    required String enderecoEntrega,
    required String observacaoEntrega,
    required String prioridadeEntrega,
    required String janelaEntrega,
    required DateTime dataEntregaMarcada,
    int? vendedorId,
  }) {
    throw StateError(
      'Terminal leve: use registrarOrcamentoFreteRetiradaFuturaRemoto (async).',
    );
  }

  int registrarDevolucaoOuTroca({
    required int vendaOrigemId,
    required String tipo,
    required String motivo,
    required String observacaoFinanceira,
    required String registradoPor,
    required List<LinhaDevolucaoEntradaInput> entradas,
    required List<LinhaTrocaSaidaInput> saidasTroca,
    bool permitirVendaSemEstoque = true,
  }) {
    throw StateError(
      'Terminal leve: use registrarDevolucaoOuTrocaRemoto (async).',
    );
  }

  List<Venda> listarEntregasModoMotorista(String nomeMotorista) {
    final alvo = nomeMotorista.trim().toLowerCase();
    if (alvo.isEmpty) return const [];
    final ativos = <String>{
      'roteirizada',
      'saiu_entrega',
      'entregue_complemento_pendente',
    };
    return listarEntregas()
        .where((v) {
          if (!ativos.contains(v.statusEntrega)) return false;
          return v.motoristaEntrega.trim().toLowerCase() == alvo;
        })
        .toList()
      ..sort((a, b) {
        final oa = a.ordemEntrega;
        final ob = b.ordemEntrega;
        if (oa > 0 && ob > 0 && oa != ob) return oa.compareTo(ob);
        return a.id.compareTo(b.id);
      });
  }

  List<Venda> listarEntregas({DateTime? desde, DateTime? ate, int? limit}) {
    var lista = List<Venda>.from(_entregas);
    if (limit != null && limit > 0 && lista.length > limit) {
      lista = lista.sublist(0, limit);
    }
    return lista;
  }

  List<Venda> listarEntregasFiltradas(FiltroListagemEntregas filtro) {
    return EntregaFiltroUtil.aplicarEmMemoria(
      listarEntregas(),
      filtro,
      vendedorRepository: _resolverVendedorComoRepo(),
    );
  }

  dynamic _resolverVendedorComoRepo() {
    final resolver = resolverVendedor;
    if (resolver == null) return null;
    return _VendedorResolverAdapter(resolver);
  }

  ResultadoListagemEntregas carregarListagemEntregasComResumo({
    required FiltroListagemEntregas filtroLista,
    required FiltroListagemEntregas filtroContagem,
  }) {
    final base = listarEntregas();
    final paraContagem = EntregaFiltroUtil.aplicarEmMemoria(
      base,
      filtroContagem,
      vendedorRepository: _resolverVendedorComoRepo(),
    );
    var atrasadas = 0;
    var pendentesHoje = 0;
    for (final v in paraContagem) {
      if (EntregaFiltroUtil.ehAtrasada(v)) atrasadas++;
      if (EntregaFiltroUtil.ehAgendaHoje(v)) pendentesHoje++;
    }
    final entregas = EntregaFiltroUtil.aplicarEmMemoria(
      base,
      filtroLista,
      vendedorRepository: _resolverVendedorComoRepo(),
    );
    entregas.sort((a, b) {
      int peso(String p) => switch (p) {
            'urgente' => 3,
            'alta' => 2,
            'normal' => 1,
            _ => 0,
          };
      final c = peso(b.prioridadeEntrega).compareTo(peso(a.prioridadeEntrega));
      if (c != 0) return c;
      return b.data.compareTo(a.data);
    });
    return ResultadoListagemEntregas(
      entregas: entregas,
      atrasadas: atrasadas,
      pendentesHoje: pendentesHoje,
    );
  }

  List<Venda> listarEntregasPaginadas(
    dynamic filtro, {
    int offset = 0,
    int limit = 50,
  }) {
    final todas = filtro is FiltroListagemEntregas
        ? listarEntregasFiltradas(filtro)
        : listarEntregas();
    if (offset >= todas.length) return const [];
    final end = (offset + limit).clamp(0, todas.length);
    return todas.sublist(offset, end);
  }

  Venda? _vendaMutavel(int vendaId) {
    final cached = _porId[vendaId];
    if (cached != null) return cached;
    for (final v in _entregas) {
      if (v.id == vendaId) return v;
    }
    return null;
  }

  void _sincronizarEntregaNoCache(Venda v) {
    _porId[v.id] = v;
    final i = _entregas.indexWhere((e) => e.id == v.id);
    if (i >= 0) {
      _entregas[i] = v;
    }
  }

  /// Atualiza o cache apos baixa confirmada pelo servidor (sem exigir online).
  void incorporarEntregaDaApi(Venda v) {
    _sincronizarEntregaNoCache(v);
    _cacheItensDaVenda(v);
    notifyListeners();
  }

  /// Persistencia remota: use [atualizarMotoristaEntregaRemoto].
  void atualizarMotoristaEntrega(int vendaId, String motorista) {
    throw StateError(
      'Terminal leve: use atualizarMotoristaEntregaRemoto (async).',
    );
  }

  /// Persistencia remota: use [atualizarMotoristaEntregaEmLoteRemoto].
  int atualizarMotoristaEntregaEmLote(Set<int> ids, String motorista) {
    throw StateError(
      'Terminal leve: use atualizarMotoristaEntregaEmLoteRemoto (async).',
    );
  }

  void atualizarDataEntregaMarcada(int vendaId, DateTime? novaData) {
    final v = _vendaMutavel(vendaId);
    if (v == null) return;
    v.dataEntregaMarcada = novaData?.toUtc();
    _sincronizarEntregaNoCache(v);
    notifyListeners();
  }

  void atualizarPrioridadeEntrega(int vendaId, String novaPrioridade) {
    final v = _vendaMutavel(vendaId);
    if (v == null) return;
    v.prioridadeEntrega = novaPrioridade.trim().isEmpty
        ? 'normal'
        : novaPrioridade.trim();
    _sincronizarEntregaNoCache(v);
    notifyListeners();
  }

  void atualizarChecklistCargaEntrega(
    int vendaId, {
    bool? separado,
    bool? carregado,
    bool? saiu,
    String? lojaOrigemMercadoria,
    Map<int, String>? origemPorItem,
  }) {
    throw StateError(
      'Terminal leve: use atualizarChecklistCargaEntregaRemoto (async).',
    );
  }

  void atualizarStatusEntrega(
    int vendaId,
    String statusEntrega, {
    String? complementoEntregaJson,
    bool retornouParaLoja = false,
  }) {
    throw StateError(
      'Terminal leve: use atualizarStatusEntregaRemoto (async).',
    );
  }

  void registrarHistoricoStatusEntrega({
    required int vendaId,
    required String statusAnterior,
    required String statusNovo,
    String motivo = '',
    String usuario = '',
  }) {
    throw StateError(
      'Terminal leve: historico de status e gravado no PC servidor via Remoto.',
    );
  }

  void registrarOcorrenciaEntrega({
    required int vendaId,
    required String status,
    String motivo = '',
    String usuario = '',
    String? detalhesEstruturados,
  }) {
    throw StateError(
      'Terminal leve: use registrarOcorrenciaEntregaRemoto (async).',
    );
  }

  void definirGrupoEntregaLogistica(
    Set<int> ids, {
    String motoristaEntrega = '',
  }) {
    throw StateError(
      'Terminal leve: use definirGrupoEntregaLogisticaRemoto (async).',
    );
  }

  void limparGrupoEntregaLogisticaEm(Set<int> ids) {
    throw StateError(
      'Terminal leve: use limparGrupoEntregaLogisticaEmRemoto.',
    );
  }

  Future<void> limparGrupoEntregaLogisticaEmRemoto(Set<int> ids) async {
    if (ids.isEmpty) return;
    _exigirServidorOnline();
    await _client.limparGrupoEntrega(ids: ids.toList());
    await hidratarEntregas(limit: 500);
  }

  void definirMotoristaEntregaNoGrupo(int grupoId, String motorista) {
    throw StateError(
      'Terminal leve: use definirMotoristaEntregaNoGrupoRemoto.',
    );
  }

  Future<void> definirMotoristaEntregaNoGrupoRemoto(
    int grupoId,
    String motorista,
  ) async {
    _exigirServidorOnline();
    await _client.definirMotoristaGrupoEntrega(
      grupoId: grupoId,
      motoristaEntrega: motorista,
    );
    await hidratarEntregas(limit: 500);
  }

  void atualizarSequenciaEntregaNoGrupo(
    int grupoId,
    List<int> vendaIdsOrdenados,
  ) {
    throw StateError(
      'Terminal leve: use atualizarSequenciaEntregaNoGrupoRemoto.',
    );
  }

  Future<void> atualizarSequenciaEntregaNoGrupoRemoto(
    int grupoId,
    List<int> vendaIdsOrdenados,
  ) async {
    _exigirServidorOnline();
    await _client.atualizarSequenciaGrupoEntrega(
      grupoId: grupoId,
      ids: vendaIdsOrdenados,
    );
    await hidratarEntregas(limit: 500);
  }

  void atualizarSequenciaEntregaMotorista(
    String motorista,
    List<int> vendaIdsOrdenados,
  ) {
    throw StateError(
      'Terminal leve: use atualizarSequenciaEntregaMotoristaRemoto.',
    );
  }

  Future<void> atualizarSequenciaEntregaMotoristaRemoto(
    String motorista,
    List<int> vendaIdsOrdenados,
  ) async {
    _exigirServidorOnline();
    await _client.atualizarSequenciaMotoristaEntrega(
      motoristaEntrega: motorista,
      ids: vendaIdsOrdenados,
    );
    await hidratarEntregas(limit: 500);
  }

  void registrarRetiradaParcialLojaCarretoAntesSaida(
    int vendaId,
    Map<int, int> quantidadesPorItemId, {
    required String usuario,
    String? retiradoPor,
    bool permitirSemConferenciaEstoque = true,
  }) {
    throw UnsupportedError(
      'Terminal leve: use registrarRetiradaParcialLojaCarretoAntesSaidaRemoto.',
    );
  }

  void registrarRetiradaParcial(
    int vendaId,
    Map<int, int> quantidadePorItemVendaId, {
    required String usuario,
    String? retiradoPor,
    bool permitirSemConferenciaEstoque = true,
  }) {
    throw UnsupportedError(
      'Terminal leve: use registrarRetiradaParcialRemoto.',
    );
  }

  Future<void> registrarRetiradaParcialRemoto(
    int vendaId,
    Map<int, int> quantidades, {
    required String usuario,
    String? retiradoPor,
  }) async {
    _exigirServidorOnline();
    await _client.registrarRetiradaParcial(
      vendaId,
      quantidades: quantidades,
      usuario: usuario,
      retiradoPor: retiradoPor,
      tipo: 'futura',
    );
    await hidratarEntregas(limit: 500);
    await hidratarVendasFinalizadas(limit: 200);
  }

  Future<void> registrarRetiradaParcialLojaCarretoAntesSaidaRemoto(
    int vendaId,
    Map<int, int> quantidades, {
    required String usuario,
    String? retiradoPor,
  }) async {
    _exigirServidorOnline();
    await _client.registrarRetiradaParcial(
      vendaId,
      quantidades: quantidades,
      usuario: usuario,
      retiradoPor: retiradoPor,
      tipo: 'loja_carreto',
    );
    await hidratarEntregas(limit: 500);
    await hidratarVendasFinalizadas(limit: 200);
  }

  Future<void> registrarPodEntregaRemoto({
    required int vendaId,
    required String recebidoPor,
    required String usuarioLogin,
    String fotoPathLocal = '',
    String fotoPathServidor = '',
    String ocorrenciaMotivo = '',
  }) async {
    _exigirServidorOnline();
    final m = await _client.registrarPodEntrega(
      vendaId,
      recebidoPor: recebidoPor,
      usuarioLogin: usuarioLogin,
      fotoPathLocal: fotoPathLocal,
      fotoPathServidor: fotoPathServidor,
      ocorrenciaMotivo: ocorrenciaMotivo,
    );
    final item = m['item'];
    if (item is Map) {
      final v = LanApiClient.vendaCompletaDeMap(
        Map<String, dynamic>.from(item),
      );
      _sincronizarEntregaNoCache(v);
      _cacheItensDaVenda(v);
      notifyListeners();
    } else {
      await hidratarEntregas(limit: 500);
    }
  }

  /// Baixa do motorista: nao exige hub online (timeout curto no client).
  Future<Venda?> baixarEntregaMotoristaRemoto({
    required int vendaId,
    required String recebidoPor,
    required String usuarioLogin,
    String fotoPathLocal = '',
    String fotoPathServidor = '',
    String statusAnterior = '',
  }) async {
    final m = await _client.baixarEntregaMotorista(
      vendaId: vendaId,
      recebidoPor: recebidoPor,
      usuarioLogin: usuarioLogin,
      fotoPathLocal: fotoPathLocal,
      fotoPathServidor: fotoPathServidor,
      statusAnterior: statusAnterior,
    );
    final item = m['item'];
    if (item is Map) {
      final v = LanApiClient.vendaCompletaDeMap(
        Map<String, dynamic>.from(item),
      );
      incorporarEntregaDaApi(v);
      return v;
    }
    return null;
  }

  Future<Venda?> registrarNaoEntregueMotoristaRemoto({
    required int vendaId,
    required String motivoCodigo,
    String motivoDetalhe = '',
    required String usuarioLogin,
    String statusAnterior = '',
    bool retornouParaLoja = false,
  }) async {
    final m = await _client.registrarNaoEntregueMotorista(
      vendaId: vendaId,
      motivoCodigo: motivoCodigo,
      motivoDetalhe: motivoDetalhe,
      usuarioLogin: usuarioLogin,
      statusAnterior: statusAnterior,
      retornouParaLoja: retornouParaLoja,
    );
    final item = m['item'];
    if (item is Map) {
      final v = LanApiClient.vendaCompletaDeMap(
        Map<String, dynamic>.from(item),
      );
      incorporarEntregaDaApi(v);
      return v;
    }
    return null;
  }

  Future<void> registrarOcorrenciaEntregaRemoto({
    required int vendaId,
    required String status,
    String motivo = '',
    String usuario = '',
  }) async {
    _exigirServidorOnline();
    await _client.registrarOcorrenciaEntrega(
      vendaId,
      status: status,
      motivo: motivo,
      usuario: usuario,
    );
  }

  Future<void> registrarHistoricoStatusEntregaRemoto({
    required int vendaId,
    required String statusAnterior,
    required String statusNovo,
    String motivo = '',
    String usuario = '',
  }) async {
    _exigirServidorOnline();
    await _client.registrarHistoricoStatusEntrega(
      vendaId,
      statusAnterior: statusAnterior,
      statusNovo: statusNovo,
      motivo: motivo,
      usuario: usuario,
    );
  }

  Future<void> atualizarStatusEntregaRemoto(
    int vendaId,
    String statusEntrega, {
    String? complementoEntregaJson,
    bool retornouParaLoja = false,
  }) async {
    _exigirServidorOnline();
    await _client.atualizarStatusEntrega(
      vendaId,
      statusEntrega,
      complementoEntregaJson: complementoEntregaJson,
      retornouParaLoja: retornouParaLoja,
    );
    await hidratarEntregas(limit: 500);
  }

  Future<void> atualizarMotoristaEntregaRemoto(
    int vendaId,
    String motorista,
  ) async {
    _exigirServidorOnline();
    await _client.atualizarCamposEntrega(vendaId, {
      'motoristaEntrega': motorista.trim(),
    });
    await hidratarEntregas(limit: 500);
  }

  Future<int> atualizarMotoristaEntregaEmLoteRemoto(
    Set<int> ids,
    String motorista,
  ) async {
    _exigirServidorOnline();
    var n = 0;
    final nome = motorista.trim();
    for (final id in ids) {
      await _client.atualizarCamposEntrega(id, {'motoristaEntrega': nome});
      n++;
    }
    await hidratarEntregas(limit: 500);
    return n;
  }

  Future<void> atualizarDataEntregaMarcadaRemoto(
    int vendaId,
    DateTime? novaData,
  ) async {
    _exigirServidorOnline();
    await _client.atualizarCamposEntrega(vendaId, {
      'dataEntregaMarcada': novaData?.toUtc().toIso8601String(),
    });
    await hidratarEntregas(limit: 500);
  }

  Future<void> atualizarPrioridadeEntregaRemoto(
    int vendaId,
    String novaPrioridade,
  ) async {
    _exigirServidorOnline();
    await _client.atualizarCamposEntrega(vendaId, {
      'prioridadeEntrega': novaPrioridade.trim().isEmpty
          ? 'normal'
          : novaPrioridade.trim(),
    });
    await hidratarEntregas(limit: 500);
  }

  Future<void> liberarSaidaCarretoRemoto({
    required int vendaId,
    String usuario = '',
    bool incluirGrupo = true,
  }) async {
    _exigirServidorOnline();
    await _client.liberarSaidaCarreto(
      vendaId: vendaId,
      usuario: usuario,
      incluirGrupo: incluirGrupo,
    );
    await hidratarEntregas(limit: 500);
  }

  Future<void> atualizarChecklistCargaEntregaRemoto(
    int vendaId, {
    bool? separado,
    bool? carregado,
    bool? saiu,
    String? lojaOrigemMercadoria,
    Map<int, String>? origemPorItem,
  }) async {
    _exigirServidorOnline();
    final campos = <String, dynamic>{};
    if (separado != null) campos['cargaSeparada'] = separado;
    if (carregado != null) campos['cargaCarregada'] = carregado;
    if (saiu != null) campos['cargaSaiu'] = saiu;
    if (lojaOrigemMercadoria != null) {
      campos['lojaOrigemMercadoria'] = lojaOrigemMercadoria;
    }
    if (origemPorItem != null && origemPorItem.isNotEmpty) {
      campos['lojaOrigemItens'] =
          LojaOrigemMercadoria.mapOrigemItensParaJson(origemPorItem);
    }
    if (campos.isEmpty) return;
    await _client.atualizarCamposEntrega(vendaId, campos);
    await hidratarEntregas(limit: 500);
  }

  Future<void> atualizarOrigemMercadoriaRemoto(
    int vendaId, {
    String? lojaOrigemMercadoria,
    Map<int, String>? origemPorItem,
  }) async {
    _exigirServidorOnline();
    final campos = <String, dynamic>{};
    if (lojaOrigemMercadoria != null) {
      campos['lojaOrigemMercadoria'] = lojaOrigemMercadoria;
    }
    if (origemPorItem != null && origemPorItem.isNotEmpty) {
      campos['lojaOrigemItens'] =
          LojaOrigemMercadoria.mapOrigemItensParaJson(origemPorItem);
    }
    if (campos.isEmpty) return;
    await _client.atualizarCamposEntrega(vendaId, campos);
    await hidratarEntregas(limit: 500);
  }

  void atualizarBuscarNaLoja(
    int vendaId, {
    required String acao,
    required List<int> itemIds,
    required String usuario,
    bool permitirVendaSemEstoque = true,
    Map<int, int>? quantidadePorItem,
  }) {
    throw StateError(
      'Terminal leve: use atualizarBuscarNaLojaRemoto (async).',
    );
  }

  Future<void> atualizarBuscarNaLojaRemoto({
    required int vendaId,
    required String acao,
    required List<int> itemIds,
    String usuario = '',
    Map<int, int>? quantidadePorItem,
  }) async {
    _exigirServidorOnline();
    await _client.atualizarBuscarNaLoja(
      vendaId: vendaId,
      acao: acao,
      itemIds: itemIds,
      usuario: usuario,
      quantidadePorItem: quantidadePorItem,
    );
    await hidratarEntregas(limit: 500);
  }

  Future<void> definirGrupoEntregaLogisticaRemoto(
    Set<int> ids, {
    String motoristaEntrega = '',
  }) async {
    if (ids.length < 2) return;
    _exigirServidorOnline();
    await _client.definirGrupoEntrega(
      ids: ids.toList(),
      motoristaEntrega: motoristaEntrega,
    );
    await hidratarEntregas(limit: 500);
  }

  List<Venda> _pendenciasFiscais = [];
  List<Venda> _pendenciasSefaz = [];
  int _metaNfcePendenteEmissao = 0;
  int _metaNfceAguardandoSefaz = 0;
  int _metaNfeProcessando = 0;
  int _metaNfeRejeitadas = 0;

  List<Venda> listarComNfcePendenteEmissao() =>
      List.unmodifiable(_pendenciasFiscais);

  List<Venda> listarComNfcePendenteFocus({int limite = 80}) {
    final lista = List<Venda>.from(_pendenciasSefaz);
    if (limite > 0 && lista.length > limite) {
      return List.unmodifiable(lista.sublist(0, limite));
    }
    return List.unmodifiable(lista);
  }

  int get metaNfcePendenteEmissao => _metaNfcePendenteEmissao;
  int get metaNfceAguardandoSefaz => _metaNfceAguardandoSefaz;
  int get metaNfeProcessando => _metaNfeProcessando;
  int get metaNfeRejeitadas => _metaNfeRejeitadas;
  int get metaPendenciasFiscaisTotal =>
      _metaNfcePendenteEmissao +
      _metaNfceAguardandoSefaz +
      _metaNfeProcessando +
      _metaNfeRejeitadas;

  Future<void> hidratarPendenciasFiscais() async {
    _exigirServidorOnline();
    final m = await _client.listarPendenciasFiscaisMap();
    final emissaoRaw = m['pendentesEmissao'] ?? m['items'];
    final sefazRaw = m['pendentesSefaz'];
    final emissao = _clientVendasDeLista(emissaoRaw);
    final sefaz = _clientVendasDeLista(sefazRaw);
    _pendenciasFiscais = emissao;
    _pendenciasSefaz = sefaz;
    final meta = m['meta'];
    if (meta is Map) {
      _metaNfcePendenteEmissao =
          (meta['nfcePendenteEmissao'] as num?)?.toInt() ?? emissao.length;
      _metaNfceAguardandoSefaz =
          (meta['nfceAguardandoSefaz'] as num?)?.toInt() ?? sefaz.length;
      _metaNfeProcessando = (meta['nfeProcessando'] as num?)?.toInt() ?? 0;
      _metaNfeRejeitadas = (meta['nfeRejeitadas'] as num?)?.toInt() ?? 0;
    } else {
      _metaNfcePendenteEmissao = emissao.length;
      _metaNfceAguardandoSefaz = sefaz.length;
      _metaNfeProcessando = 0;
      _metaNfeRejeitadas = 0;
    }
    for (final v in [...emissao, ...sefaz]) {
      _porId[v.id] = v;
    }
    notifyListeners();
  }

  List<Venda> _clientVendasDeLista(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => LanApiClient.vendaCompletaDeMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> reconsultarNfceRemoto(int vendaId) async {
    _exigirServidorOnline();
    final m = await _client.reconsultarNfce(vendaId);
    await hidratarPendenciasFiscais();
    return m;
  }

  Future<Map<String, dynamic>> reconsultarTodasNfceRemoto() async {
    _exigirServidorOnline();
    final m = await _client.reconsultarTodasNfce();
    await hidratarPendenciasFiscais();
    return m;
  }

  Venda? obterPorId(int id) => _porId[id];

  List<Venda> listarOrcamentosPendentes({
    DateTime? desde,
    DateTime? ate,
    int? limit,
  }) {
    if (_offline) return const [];
    var lista = _orcamentos
        .where((v) => v.status == 'orcamento' && !v.cancelada)
        .toList();
    if (desde != null) {
      final ini = DateTime(desde.year, desde.month, desde.day).toUtc();
      lista = lista.where((v) => !v.data.isBefore(ini)).toList();
    }
    if (ate != null) {
      final fim = DateTime(ate.year, ate.month, ate.day, 23, 59, 59).toUtc();
      lista = lista.where((v) => !v.data.isAfter(fim)).toList();
    }
    if (limit != null && limit > 0 && lista.length > limit) {
      lista = lista.sublist(0, limit);
    }
    return lista;
  }

  Venda? buscarOrcamentoPendentePorNumero(int numero) {
    if (_offline) return null;
    for (final v in _orcamentos) {
      if (v.status != 'orcamento' || v.cancelada) continue;
      if (v.numeroOrcamento == numero) return v;
    }
    return null;
  }

  Future<Venda?> buscarOrcamentoPendentePorNumeroRemoto(int numero) async {
    _exigirServidorOnline();
    final v = await _client.buscarOrcamentoPorNumero(numero);
    if (v != null) {
      _porId[v.id] = v;
      final i = _orcamentos.indexWhere((e) => e.id == v.id);
      if (v.status == 'orcamento' && !v.cancelada) {
        if (i >= 0) {
          _orcamentos[i] = v;
        } else {
          _orcamentos.insert(0, v);
        }
      } else if (i >= 0) {
        _orcamentos.removeAt(i);
      }
      notifyListeners();
    }
    return v;
  }

  List<ItemVenda> listarItensPorVenda(int vendaId) {
    return List.unmodifiable(_itens[vendaId] ?? const []);
  }

  Future<List<ItemVenda>> carregarItensRemoto(int vendaId) async {
    _exigirServidorOnline();
    var itens = await _client.listarItensVenda(vendaId);
    // Se /itens veio vazio (query desalinhada no servidor), tenta venda completa
    // e nao apaga cache ja hidratado da listagem de orcamentos.
    if (itens.isEmpty) {
      final v = await _client.obterVenda(vendaId);
      if (v != null) {
        _porId[vendaId] = v;
        _cacheItensDaVenda(v);
        itens = List<ItemVenda>.from(_itens[vendaId] ?? const []);
      }
    }
    if (itens.isNotEmpty) {
      _itens[vendaId] = itens;
    }
    notifyListeners();
    return listarItensPorVenda(vendaId);
  }

  Future<void> revincularItensAoProduto({
    required int vendaId,
    required Map<int, int> itemIdParaProdutoId,
  }) async {
    if (itemIdParaProdutoId.isEmpty) return;
    _exigirServidorOnline();
    await _client.revincularItensProduto(
      vendaId,
      vinculos: itemIdParaProdutoId.entries
          .map((e) => {'itemId': e.key, 'produtoId': e.value})
          .toList(),
    );
    await carregarItensRemoto(vendaId);
  }

  Future<int> registrarOrcamentoRemoto(
    List<ItemVendaInput> itensInput, {
    required DadosPagamentoOrcamento pagamento,
    required DadosEntregaOrcamento entrega,
    int? clienteId,
    int? vendedorId,
    double descontoEmReais = 0,
    bool permitirVendaSemEstoque = false,
    String? uuidLocal,
  }) async {
    _exigirServidorOnline();
    final body = montarBodyOrcamentoApi(
      itens: itensInput
          .map(
            (i) => {
              'produtoId': i.produtoId,
              'quantidade': i.quantidade,
              'precoUnitario': i.precoUnitario,
              'precoTipo': i.precoTipo,
              'tipoEntregaItem': i.tipoEntregaItem,
              'promocaoId': i.promocaoId,
              'promocaoNomeSnapshot': i.promocaoNomeSnapshot,
              'precoUnitarioManual': i.precoUnitarioManual,
            },
          )
          .toList(),
      pagamento: pagamento,
      entrega: {
        'tipoEntrega': entrega.tipoEntrega,
        'valorFrete': entrega.valorFrete,
        'enderecoEntrega': entrega.enderecoEntrega,
        'observacaoEntrega': entrega.observacaoEntrega,
        'prioridadeEntrega': entrega.prioridadeEntrega,
        'janelaEntrega': entrega.janelaEntrega,
        'dataEntregaMarcada': entrega.dataEntregaMarcada
            ?.toUtc()
            .toIso8601String(),
      },
      clienteId: clienteId,
      vendedorId: vendedorId,
      descontoEmReais: descontoEmReais,
      permitirVendaSemEstoque: permitirVendaSemEstoque,
      uuidLocal: uuidLocal,
    );
    final id = await _client.criarOrcamento(body);
    final v = await _client.obterVenda(id);
    if (v != null) {
      _porId[id] = v;
      _orcamentos.insert(0, v);
    }
    await carregarItensRemoto(id);
    notifyListeners();
    return id;
  }

  /// Compat: PDV sync chama isto — no terminal redireciona para remoto.
  int registrarOrcamento(
    List<ItemVendaInput> itensInput, {
    required DadosPagamentoOrcamento pagamento,
    required DadosEntregaOrcamento entrega,
    int? clienteId,
    int? vendedorId,
    double descontoEmReais = 0,
    bool permitirVendaSemEstoque = false,
    String? uuidLocal,
  }) {
    throw StateError(
      'Terminal leve: use registrarOrcamentoRemoto (async) no PDV.',
    );
  }

  void atualizarOrcamento(
    int vendaId,
    List<ItemVendaInput> itensInput, {
    required DadosPagamentoOrcamento pagamento,
    required DadosEntregaOrcamento entrega,
    int? clienteId,
    int? vendedorId,
    double descontoEmReais = 0,
    bool permitirVendaSemEstoque = false,
  }) {
    throw StateError(
      'Terminal leve: use atualizarOrcamentoRemoto (async) no PDV.',
    );
  }

  Future<void> atualizarOrcamentoRemoto(
    int vendaId,
    List<ItemVendaInput> itensInput, {
    required DadosPagamentoOrcamento pagamento,
    required DadosEntregaOrcamento entrega,
    int? clienteId,
    int? vendedorId,
    double descontoEmReais = 0,
    bool permitirVendaSemEstoque = false,
  }) async {
    _exigirServidorOnline();
    final body = montarBodyOrcamentoApi(
      itens: itensInput
          .map(
            (i) => {
              'produtoId': i.produtoId,
              'quantidade': i.quantidade,
              'precoUnitario': i.precoUnitario,
              'precoTipo': i.precoTipo,
              'tipoEntregaItem': i.tipoEntregaItem,
              'promocaoId': i.promocaoId,
              'promocaoNomeSnapshot': i.promocaoNomeSnapshot,
              'precoUnitarioManual': i.precoUnitarioManual,
            },
          )
          .toList(),
      pagamento: pagamento,
      entrega: {
        'tipoEntrega': entrega.tipoEntrega,
        'valorFrete': entrega.valorFrete,
        'enderecoEntrega': entrega.enderecoEntrega,
        'observacaoEntrega': entrega.observacaoEntrega,
        'prioridadeEntrega': entrega.prioridadeEntrega,
        'janelaEntrega': entrega.janelaEntrega,
        'dataEntregaMarcada': entrega.dataEntregaMarcada
            ?.toUtc()
            .toIso8601String(),
      },
      clienteId: clienteId,
      vendedorId: vendedorId,
      descontoEmReais: descontoEmReais,
      permitirVendaSemEstoque: permitirVendaSemEstoque,
    );
    await _client.atualizarOrcamento(vendaId, body);
    final v = await _client.obterVenda(vendaId);
    if (v != null) {
      _porId[vendaId] = v;
      final i = _orcamentos.indexWhere((e) => e.id == vendaId);
      if (i >= 0) {
        _orcamentos[i] = v;
      }
    }
    await carregarItensRemoto(vendaId);
    notifyListeners();
  }

  Future<void> converterOrcamentoParaVendaRemoto(
    int vendaId, {
    bool permitirVendaSemEstoque = true,
    double valorRecebidoCaixa = 0,
    double valorTrocoCaixa = 0,
  }) async {
    _exigirServidorOnline();
    await _client.finalizarVenda(
      vendaId,
      permitirVendaSemEstoque: permitirVendaSemEstoque,
      terminalId: await _terminalIdCaixa(),
      valorRecebidoCaixa: valorRecebidoCaixa,
      valorTrocoCaixa: valorTrocoCaixa,
    );
    _orcamentos.removeWhere((v) => v.id == vendaId);
    final v = await _client.obterVenda(vendaId);
    if (v != null) {
      _porId[vendaId] = v;
      _cacheItensDaVenda(v);
      if (v.status == 'finalizada' && !v.cancelada) {
        final i = _vendasFinalizadas.indexWhere((e) => e.id == vendaId);
        if (i >= 0) {
          _vendasFinalizadas[i] = v;
        } else {
          _vendasFinalizadas.insert(0, v);
        }
      }
    }
    notifyListeners();
  }

  void converterOrcamentoParaVenda(
    int vendaId, {
    bool permitirVendaSemEstoque = true,
  }) {
    throw StateError('Terminal leve: use converterOrcamentoParaVendaRemoto.');
  }

  Future<void> _atualizarCacheAposMutacaoOrcamento(int vendaId) async {
    final v = await _client.obterVenda(vendaId);
    if (v != null) {
      _porId[vendaId] = v;
      final i = _orcamentos.indexWhere((e) => e.id == vendaId);
      if (v.status == 'orcamento' && !v.cancelada) {
        if (i >= 0) {
          _orcamentos[i] = v;
        } else {
          _orcamentos.insert(0, v);
        }
      } else if (i >= 0) {
        _orcamentos.removeAt(i);
      }
    }
    await carregarItensRemoto(vendaId);
    notifyListeners();
  }

  Future<void> cancelarVendaRemoto(
    int vendaId, {
    String motivo = '',
    String canceladaPor = '',
  }) async {
    _exigirServidorOnline();
    await _client.cancelarVenda(
      vendaId,
      motivo: motivo,
      canceladaPor: canceladaPor,
    );
    final v = await _client.obterVenda(vendaId);
    if (v != null) {
      _aplicarVendaCanceladaNoCache(v);
    }
    notifyListeners();
  }

  /// Cancelamento com NFC-e/NF-e autorizada via API (SEFAZ no PC1 + ERP).
  Future<Map<String, dynamic>> cancelarVendaFiscalRemoto(
    int vendaId, {
    required String justificativa,
    String motivo = '',
    String canceladaPor = '',
  }) async {
    final just = justificativa.trim();
    if (just.length < 15) {
      throw LanApiException(
        'Justificativa fiscal deve ter no minimo 15 caracteres.',
      );
    }
    if (just.length > 255) {
      throw LanApiException(
        'Justificativa fiscal deve ter no maximo 255 caracteres.',
      );
    }
    _exigirServidorOnline();
    final m = await _client.cancelarVendaFiscal(
      vendaId,
      justificativa: just,
      motivo: motivo,
      canceladaPor: canceladaPor,
    );
    if (m['ok'] != true) {
      throw LanApiException(
        (m['error'] ?? m['mensagem'] ?? 'Falha no cancelamento fiscal.')
            .toString(),
      );
    }
    Venda? v;
    final itemRaw = m['item'];
    if (itemRaw is Map) {
      try {
        v = LanApiClient.vendaCompletaDeMap(
          Map<String, dynamic>.from(itemRaw),
        );
      } catch (_) {
        v = null;
      }
    }
    v ??= await _client.obterVenda(vendaId);
    if (v != null) {
      _aplicarVendaCanceladaNoCache(v);
    }
    notifyListeners();
    return m;
  }

  Future<void> vincularClienteVendaFinalizadaRemoto(
    int vendaId,
    int clienteId,
  ) async {
    _exigirServidorOnline();
    await _client.vincularClienteVendaFinalizada(vendaId, clienteId);
    final v = await _client.obterVenda(vendaId);
    if (v != null) {
      _porId[vendaId] = v;
      final i = _vendasFinalizadas.indexWhere((e) => e.id == vendaId);
      if (i >= 0) {
        _vendasFinalizadas[i] = v;
      } else {
        _vendasFinalizadas.insert(0, v);
      }
    }
    notifyListeners();
  }

  Future<int> registrarOrcamentoFreteRetiradaFuturaRemoto({
    required int vendaMaeId,
    required double valorFreteCobrado,
    required DadosPagamentoOrcamento pagamento,
    required String enderecoEntrega,
    required String observacaoEntrega,
    required String prioridadeEntrega,
    required String janelaEntrega,
    required DateTime dataEntregaMarcada,
    int? vendedorId,
  }) async {
    _exigirServidorOnline();
    final m = await _client.registrarOrcamentoFreteRetiradaFutura(
      vendaMaeId: vendaMaeId,
      valorFreteCobrado: valorFreteCobrado,
      pagamento: pagamento,
      enderecoEntrega: enderecoEntrega,
      observacaoEntrega: observacaoEntrega,
      prioridadeEntrega: prioridadeEntrega,
      janelaEntrega: janelaEntrega,
      dataEntregaMarcada: dataEntregaMarcada,
      vendedorId: vendedorId,
    );
    final novoId = (m['id'] as num?)?.toInt() ?? 0;
    if (novoId > 0) {
      await _atualizarCacheAposMutacaoOrcamento(novoId);
    }
    final mae = await _client.obterVenda(vendaMaeId);
    if (mae != null) {
      _porId[vendaMaeId] = mae;
      final i = _vendasFinalizadas.indexWhere((e) => e.id == vendaMaeId);
      if (i >= 0) _vendasFinalizadas[i] = mae;
    }
    notifyListeners();
    return novoId;
  }

  Future<int> registrarDevolucaoOuTrocaRemoto({
    required int vendaOrigemId,
    required String tipo,
    required String motivo,
    required String observacaoFinanceira,
    required String registradoPor,
    required List<LinhaDevolucaoEntradaInput> entradas,
    required List<LinhaTrocaSaidaInput> saidasTroca,
    bool permitirVendaSemEstoque = true,
  }) async {
    _exigirServidorOnline();
    final m = await _client.registrarDevolucaoOuTroca(
      vendaOrigemId: vendaOrigemId,
      tipo: tipo,
      motivo: motivo,
      observacaoFinanceira: observacaoFinanceira,
      registradoPor: registradoPor,
      entradas: entradas
          .map(
            (e) => {
              'itemVendaId': e.itemVendaId,
              'quantidade': e.quantidade,
            },
          )
          .toList(),
      saidasTroca: saidasTroca
          .map(
            (s) => {
              'produtoId': s.produtoId,
              'quantidade': s.quantidade,
              'precoUnitario': s.precoUnitario,
              'precoTipo': s.precoTipo,
              'precoCustoUnitario': s.precoCustoUnitario,
            },
          )
          .toList(),
      permitirVendaSemEstoque: permitirVendaSemEstoque,
    );
    final registroId = (m['registroId'] as num?)?.toInt() ?? 0;
    final v = await _client.obterVenda(vendaOrigemId);
    if (v != null) {
      _porId[vendaOrigemId] = v;
      final i = _vendasFinalizadas.indexWhere((e) => e.id == vendaOrigemId);
      if (i >= 0) {
        _vendasFinalizadas[i] = v;
      }
    }
    await carregarItensRemoto(vendaOrigemId);
    notifyListeners();
    return registroId;
  }

  Future<({int orcamentoId, int numeroOrcamento, bool reutilizado})>
      registrarOrcamentoComplementoTrocaRemoto({
    required int vendaOrigemId,
    required int registroDevolucaoId,
    required double valor,
    String formaPagamento = 'dinheiro',
    int quantidadeParcelas = 1,
  }) async {
    _exigirServidorOnline();
    final m = await _client.registrarOrcamentoComplementoTroca(
      vendaOrigemId: vendaOrigemId,
      registroId: registroDevolucaoId,
      valor: valor,
      formaPagamento: formaPagamento,
      quantidadeParcelas: quantidadeParcelas,
    );
    final orcamentoId = (m['orcamentoId'] as num?)?.toInt() ?? 0;
    if (orcamentoId > 0) {
      await _atualizarCacheAposMutacaoOrcamento(orcamentoId);
    }
    return (
      orcamentoId: orcamentoId,
      numeroOrcamento: (m['numeroOrcamento'] as num?)?.toInt() ?? 0,
      reutilizado: m['reutilizado'] == true,
    );
  }

  Future<void> vincularClienteNoOrcamentoRemoto(
    int vendaId,
    int? clienteId,
  ) async {
    _exigirServidorOnline();
    await _client.vincularClienteOrcamento(vendaId, clienteId);
    await _atualizarCacheAposMutacaoOrcamento(vendaId);
  }

  Future<void> vincularVendedorNoOrcamentoRemoto(
    int vendaId,
    int vendedorId,
  ) async {
    _exigirServidorOnline();
    await _client.vincularVendedorOrcamento(vendaId, vendedorId);
    await _atualizarCacheAposMutacaoOrcamento(vendaId);
  }

  Future<String> _terminalIdCaixa() async {
    try {
      return await CaixaSessaoRepository().obterTerminalId();
    } catch (_) {
      return '';
    }
  }

  Future<void> aplicarDescontoNoOrcamentoRemoto(
    int vendaId,
    double valor, {
    String? gerenteLogin,
    String? gerenteSenha,
    bool exigeGerente = false,
  }) async {
    _exigirServidorOnline();
    await _client.aplicarDescontoOrcamento(
      vendaId,
      valor,
      terminalId: await _terminalIdCaixa(),
      gerenteLogin: gerenteLogin,
      gerenteSenha: gerenteSenha,
      exigeGerente: exigeGerente,
    );
    await _atualizarCacheAposMutacaoOrcamento(vendaId);
  }

  Future<void> adicionarItemAoOrcamentoRemoto(
    int vendaId,
    ItemVendaInput input, {
    bool permitirVendaSemEstoque = false,
  }) async {
    _exigirServidorOnline();
    await _client.adicionarItemOrcamento(
      vendaId,
      {
        'produtoId': input.produtoId,
        'quantidade': input.quantidade,
        'precoUnitario': input.precoUnitario,
        'precoTipo': input.precoTipo,
        'tipoEntregaItem': input.tipoEntregaItem,
        'promocaoId': input.promocaoId,
        'promocaoNomeSnapshot': input.promocaoNomeSnapshot,
        'precoUnitarioManual': input.precoUnitarioManual,
      },
      permitirVendaSemEstoque: permitirVendaSemEstoque,
      terminalId: await _terminalIdCaixa(),
    );
    await _atualizarCacheAposMutacaoOrcamento(vendaId);
  }

  Future<void> atualizarQuantidadeItemOrcamentoRemoto(
    int vendaId,
    int itemId,
    int quantidade, {
    bool permitirVendaSemEstoque = false,
  }) async {
    _exigirServidorOnline();
    await _client.atualizarQuantidadeItemOrcamento(
      vendaId,
      itemId,
      quantidade,
      permitirVendaSemEstoque: permitirVendaSemEstoque,
      terminalId: await _terminalIdCaixa(),
    );
    await _atualizarCacheAposMutacaoOrcamento(vendaId);
  }

  Future<void> atualizarTipoEntregaItemOrcamentoRemoto(
    int vendaId,
    int itemId,
    String tipoEntregaItem,
  ) async {
    _exigirServidorOnline();
    await _client.atualizarTipoEntregaItemOrcamento(
      vendaId,
      itemId,
      tipoEntregaItem,
      terminalId: await _terminalIdCaixa(),
    );
    await _atualizarCacheAposMutacaoOrcamento(vendaId);
  }

  Future<void> removerItemOrcamentoRemoto(
    int vendaId,
    int itemId, {
    String? gerenteLogin,
    String? gerenteSenha,
  }) async {
    _exigirServidorOnline();
    await _client.removerItemOrcamento(
      vendaId,
      itemId,
      terminalId: await _terminalIdCaixa(),
      gerenteLogin: gerenteLogin,
      gerenteSenha: gerenteSenha,
    );
    await _atualizarCacheAposMutacaoOrcamento(vendaId);
  }

  Future<void> alterarPagamentoOrcamentoRemoto(
    int vendaId,
    DadosPagamentoOrcamento pagamento, {
    String? gerenteLogin,
    String? gerenteSenha,
  }) async {
    _exigirServidorOnline();
    await _client.alterarPagamentoOrcamento(
      vendaId,
      pagamento,
      terminalId: await _terminalIdCaixa(),
      gerenteLogin: gerenteLogin,
      gerenteSenha: gerenteSenha,
    );
    await _atualizarCacheAposMutacaoOrcamento(vendaId);
  }

  Future<void> substituirPagamentosMistoOrcamentoRemoto(
    int vendaId,
    List<PagamentoOrcamentoLinha> linhas,
  ) async {
    _exigirServidorOnline();
    await _client.substituirPagamentosMistoOrcamento(
      vendaId,
      linhas,
      terminalId: await _terminalIdCaixa(),
    );
    await _atualizarCacheAposMutacaoOrcamento(vendaId);
  }

  Future<int> registrarRecebimentoFifoRemoto({
    required int clienteId,
    required double valorRecebido,
    required String formaPagamento,
    String observacao = '',
  }) async {
    _exigirServidorOnline();
    final m = await _client.receberTitulosFifo(
      clienteId: clienteId,
      valorRecebido: valorRecebido,
      formaPagamento: formaPagamento,
      observacao: observacao,
    );
    _cacheRecebimentoPayload(m);
    await hidratarTitulos();
    return (m['id'] as num?)?.toInt() ?? 0;
  }

  ValidacaoLimiteCredito validarLimiteCredito({
    required int clienteId,
    required double valorFiadoOperacao,
    int? ignorarVendaId,
  }) {
    if (clienteId <= 0 || valorFiadoOperacao <= 0.001) {
      return ValidacaoLimiteCredito.semFiado();
    }
    // Preferir [validarLimiteCreditoRemoto] no terminal (fonte PC1).
    // Fallback no cache: respeita bloqueio/limite do cliente hidratado.
    final cliente = resolverCliente?.call(clienteId);
    if (cliente == null) {
      return const ValidacaoLimiteCredito(
        permitido: false,
        mensagem:
            'Cliente nao encontrado no cache. Aguarde sincronizacao ou use validacao remota.',
      );
    }
    if (cliente.bloqueadoFiado) {
      final motivo = cliente.motivoBloqueio.trim();
      return ValidacaoLimiteCredito(
        permitido: false,
        mensagem: motivo.isEmpty
            ? 'Cliente com fiado bloqueado no cadastro.'
            : 'Cliente com fiado bloqueado: $motivo',
        nomeCliente: cliente.nomeRazao,
      );
    }
    if (cliente.limiteCredito <= 0) {
      return ValidacaoLimiteCredito.semLimiteConfigurado();
    }
    final saldo = exposicaoFiadoCliente(
      clienteId,
      ignorarVendaId: ignorarVendaId,
    );
    final disponivel =
        (cliente.limiteCredito - saldo).clamp(0, double.infinity).toDouble();
    final apos = saldo + valorFiadoOperacao;
    if (apos <= cliente.limiteCredito + 0.02) {
      return ValidacaoLimiteCredito(
        permitido: true,
        saldoEmAberto: saldo,
        limite: cliente.limiteCredito,
        valorFiadoOperacao: valorFiadoOperacao,
        saldoAposOperacao: apos,
        nomeCliente: cliente.nomeRazao,
      );
    }
    return ValidacaoLimiteCredito(
      permitido: false,
      mensagem:
          'Limite de credito excedido. Disponivel '
          '${LimiteCreditoHelper.formatarMoedaBr(disponivel)} '
          '(limite ${LimiteCreditoHelper.formatarMoedaBr(cliente.limiteCredito)}).',
      saldoEmAberto: saldo,
      limite: cliente.limiteCredito,
      valorFiadoOperacao: valorFiadoOperacao,
      saldoAposOperacao: apos,
      nomeCliente: cliente.nomeRazao,
    );
  }

  Future<ValidacaoLimiteCredito> validarLimiteCreditoRemoto({
    required int clienteId,
    required double valorFiadoOperacao,
    int? ignorarVendaId,
  }) async {
    _exigirServidorOnline();
    final m = await _client.validarLimiteCredito(
      clienteId: clienteId,
      valorFiadoOperacao: valorFiadoOperacao,
      ignorarVendaId: ignorarVendaId,
    );
    return ValidacaoLimiteCredito(
      permitido: m['permitido'] == true,
      mensagem: (m['mensagem'] ?? '').toString().trim().isEmpty
          ? null
          : (m['mensagem'] ?? '').toString(),
      saldoEmAberto: (m['saldoEmAberto'] as num?)?.toDouble() ?? 0,
      limite: (m['limite'] as num?)?.toDouble() ?? 0,
      valorFiadoOperacao:
          (m['valorFiadoOperacao'] as num?)?.toDouble() ?? valorFiadoOperacao,
      saldoAposOperacao: (m['saldoAposOperacao'] as num?)?.toDouble() ?? 0,
      nomeCliente: (m['nomeCliente'] ?? '').toString(),
    );
  }

  /// Saldo em titulos abertos (cache hidratado). Use Remoto para forcar refresh.
  double saldoFiadoEmAbertoCliente(int clienteId, {int? ignorarVendaId}) {
    if (clienteId <= 0) return 0;
    var total = 0.0;
    for (final l in _titulosAbertos) {
      final t = l.titulo;
      if (t.cliente.targetId != clienteId) continue;
      if (ignorarVendaId != null && t.venda.targetId == ignorarVendaId) {
        continue;
      }
      if (!t.emAberto) continue;
      total += t.saldo;
    }
    return total;
  }

  /// Compras finalizadas do cliente (cache local / janela de relatorio).
  List<Venda> listarComprasFinalizadasPorCliente(
    int clienteId, {
    DateTime? inicio,
    DateTime? fim,
  }) {
    if (clienteId <= 0) return const [];
    final inicioUtc = inicio?.toUtc();
    final fimUtc = fim?.toUtc();
    final mapa = <int, Venda>{};
    void considerar(Iterable<Venda> origem) {
      for (final v in origem) {
        if (v.status != 'finalizada' || v.cancelada) continue;
        if (v.cliente.targetId != clienteId) continue;
        final d = v.data.toUtc();
        if (inicioUtc != null && d.isBefore(inicioUtc)) continue;
        if (fimUtc != null && d.isAfter(fimUtc)) continue;
        mapa[v.id] = v;
      }
    }

    considerar(_vendasFinalizadas);
    considerar(_vendasRelatorio.values);
    considerar(_porId.values);
    final cached = _comprasPorCliente[clienteId];
    if (cached != null) considerar(cached);
    final out = mapa.values.toList()
      ..sort((a, b) => b.data.compareTo(a.data));
    return out;
  }

  final Map<int, List<Venda>> _comprasPorCliente = {};

  /// Baixa compras do cliente no PC servidor (aba Relacionamento).
  Future<List<Venda>> listarComprasFinalizadasPorClienteRemoto(
    int clienteId, {
    DateTime? inicio,
    DateTime? fim,
    int limit = 200,
  }) async {
    if (clienteId <= 0) return const [];
    _exigirServidorOnline();
    final items = await _client.listarVendas(
      status: 'finalizada',
      clienteId: clienteId,
      desde: inicio,
      ate: fim,
      limit: limit,
    );
    for (final v in items) {
      _porId[v.id] = v;
      _cacheItensDaVenda(v);
    }
    _comprasPorCliente[clienteId] = List<Venda>.from(items);
    notifyListeners();
    return listarComprasFinalizadasPorCliente(
      clienteId,
      inicio: inicio,
      fim: fim,
    );
  }

  Future<double> saldoFiadoEmAbertoClienteRemoto(
    int clienteId, {
    int? ignorarVendaId,
    void Function({
      double? limiteCredito,
      bool? bloqueadoFiado,
      String? motivoBloqueio,
    })? onResumoCredito,
  }) async {
    _exigirServidorOnline();
    if (ignorarVendaId != null) {
      await hidratarTitulos();
      return saldoFiadoEmAbertoCliente(
        clienteId,
        ignorarVendaId: ignorarVendaId,
      );
    }
    final m = await _client.saldoFiadoCliente(clienteId);
    onResumoCredito?.call(
      limiteCredito: (m['limiteCredito'] as num?)?.toDouble(),
      bloqueadoFiado: m['bloqueadoFiado'] as bool?,
      motivoBloqueio: (m['motivoBloqueio'] ?? '').toString(),
    );
    return (m['saldo'] as num?)?.toDouble() ?? 0;
  }

  double fiadoPendenteEmOrcamentosCliente(
    int clienteId, {
    int? ignorarVendaId,
  }) {
    if (clienteId <= 0) return 0;
    var total = 0.0;
    for (final v in _orcamentos) {
      if (v.cliente.targetId != clienteId) continue;
      if (ignorarVendaId != null && v.id == ignorarVendaId) continue;
      if (v.cancelada || v.status != 'orcamento') continue;
      total += LimiteCreditoHelper.valorFiadoNaVenda(v);
    }
    return total;
  }

  double exposicaoFiadoCliente(int clienteId, {int? ignorarVendaId}) {
    return saldoFiadoEmAbertoCliente(clienteId, ignorarVendaId: ignorarVendaId) +
        fiadoPendenteEmOrcamentosCliente(
          clienteId,
          ignorarVendaId: ignorarVendaId,
        );
  }

  List<Venda> listarUltimasVendasFinalizadas({
    int limit = 50,
    DateTime? desde,
    DateTime? ate,
    dynamic ordenacao,
  }) {
    final base = <Venda>[
      ..._vendasFinalizadas.where(
        (v) => v.status == 'finalizada' && !v.cancelada,
      ),
      ..._vendasRelatorio.values.where(
        (v) => v.status == 'finalizada' && !v.cancelada,
      ),
    ];
    // dedupe by id
    final porId = <int, Venda>{};
    for (final v in base) {
      porId[v.id] = v;
    }
    var lista = porId.values.toList();
    if (desde != null) {
      lista = lista.where((v) => !v.data.isBefore(desde)).toList();
    }
    if (ate != null) {
      lista = lista.where((v) => !v.data.isAfter(ate)).toList();
    }
    final modo = ordenacao is UltimasVendasFinalizadasOrdenacao
        ? ordenacao
        : UltimasVendasFinalizadasOrdenacao.fromChave('$ordenacao') ??
            UltimasVendasFinalizadasOrdenacao.padrao;
    switch (modo) {
      case UltimasVendasFinalizadasOrdenacao.porControle:
        lista.sort((a, b) {
          final na = a.numeroControle > 0
              ? a.numeroControle
              : (a.numeroOrcamento > 0 ? a.numeroOrcamento : a.id);
          final nb = b.numeroControle > 0
              ? b.numeroControle
              : (b.numeroOrcamento > 0 ? b.numeroOrcamento : b.id);
          final cmp = nb.compareTo(na);
          if (cmp != 0) return cmp;
          return b.id.compareTo(a.id);
        });
      case UltimasVendasFinalizadasOrdenacao.porFinalizacao:
        lista.sort((a, b) {
          final cmp = VendaFinalizacaoCaixaHelper.momentoFinalizacao(b)
              .compareTo(VendaFinalizacaoCaixaHelper.momentoFinalizacao(a));
          if (cmp != 0) return cmp;
          return b.id.compareTo(a.id);
        });
    }
    if (lista.length > limit && limit > 0) lista = lista.sublist(0, limit);
    return lista;
  }

  int contarVendasFinalizadasPorVendedor(int vendedorId) {
    if (vendedorId <= 0) return 0;
    var n = 0;
    for (final v in _vendasFinalizadas) {
      if (!v.cancelada &&
          v.status == 'finalizada' &&
          v.vendedor.targetId == vendedorId) {
        n++;
      }
    }
    for (final v in _vendasRelatorio.values) {
      if (v.cancelada || v.status != 'finalizada') continue;
      if (v.vendedor.targetId != vendedorId) continue;
      if (_vendasFinalizadas.any((e) => e.id == v.id)) continue;
      n++;
    }
    return n;
  }

  Venda? buscarVendaFinalizadaPorNumeroOuId(int numeroOuId) {
    if (numeroOuId <= 0) return null;
    for (final v in listarUltimasVendasFinalizadas(limit: 0)) {
      if (v.numeroControle == numeroOuId ||
          v.numeroOrcamento == numeroOuId ||
          v.id == numeroOuId) {
        return v;
      }
    }
    final cached = _porId[numeroOuId];
    if (cached != null &&
        cached.status == 'finalizada' &&
        !cached.cancelada) {
      return cached;
    }
    return null;
  }

  /// Cache local e, se faltar, GET /api/vendas (numero ou id).
  Future<Venda?> buscarVendaFinalizadaPorNumeroOuIdRemoto(
    int numeroOuId,
  ) async {
    if (numeroOuId <= 0) return null;
    final local = buscarVendaFinalizadaPorNumeroOuId(numeroOuId);
    if (local != null) return local;
    _exigirServidorOnline();
    final porId = await _client.obterVenda(numeroOuId);
    if (porId != null &&
        porId.status == 'finalizada' &&
        !porId.cancelada) {
      _porId[porId.id] = porId;
      _cacheItensDaVenda(porId);
      return porId;
    }
    final lista = await _client.listarVendas(
      status: 'finalizada',
      busca: '$numeroOuId',
      limit: 20,
      filtroCancelamento: 'ativas',
    );
    for (final v in lista) {
      _porId[v.id] = v;
      if (v.numeroOrcamento == numeroOuId || v.id == numeroOuId) {
        if (v.status == 'finalizada' && !v.cancelada) {
          _cacheItensDaVenda(v);
          return v;
        }
      }
    }
    return null;
  }

  DateTime? dataUltimaVendaFinalizada() {
    final lista = listarUltimasVendasFinalizadas(limit: 1);
    return lista.isEmpty ? null : lista.first.data;
  }

  List<RegistroDevolucao> listarRegistrosDevolucaoPorPeriodo(
    PeriodoFiltro periodo,
  ) {
    final ini = periodo.inicio.toUtc();
    final fim = periodo.fim.toUtc();
    final lista = _devolucoes.where((r) {
      final d = r.data.toUtc();
      return !d.isBefore(ini) && !d.isAfter(fim);
    }).toList();
    lista.sort((a, b) => b.data.compareTo(a.data));
    return lista;
  }

  double valorReferenciaEntradaRegistro(RegistroDevolucao r) {
    var s = 0.0;
    for (final l in r.linhasEntrada) {
      s += l.quantidade * l.precoUnitarioReferencia;
    }
    return s;
  }

  double valorSaidaTrocaRegistro(RegistroDevolucao r) {
    var s = 0.0;
    for (final l in r.linhasSaidaTroca) {
      s += l.quantidade * l.precoUnitario;
    }
    return s;
  }

  /// Valor de referencia ja devolvido (preco original da linha) para exibicao.
  double valorReferenciaDevolvidoAcumuladoVenda(int vendaId) {
    var s = 0.0;
    for (final it in listarItensPorVenda(vendaId)) {
      if (it.quantidadeDevolvida <= 0) continue;
      s += it.quantidadeDevolvida * it.precoUnitario;
    }
    return s;
  }

  double valorSaidaTrocaAcumuladoVenda(int vendaId) {
    var s = 0.0;
    for (final r in listarRegistrosDevolucaoPorVenda(vendaId)) {
      if (r.tipo != 'troca') continue;
      s += valorSaidaTrocaRegistro(r);
    }
    return s;
  }

  ({bool tem, double valorDevolvido, double valorTroca})
      resumoDevolucaoTrocaListagem(int vendaId) {
    final v = _porId[vendaId];
    final viaApi = v == null ? null : LanApiClient.devolucaoListagem[v];
    if (viaApi != null) {
      return (
        tem: viaApi.dev > 0.005 || viaApi.troca > 0.005,
        valorDevolvido: viaApi.dev,
        valorTroca: viaApi.troca,
      );
    }
    final dev = valorReferenciaDevolvidoAcumuladoVenda(vendaId);
    final troca = valorSaidaTrocaAcumuladoVenda(vendaId);
    return (
      tem: dev > 0.005 || troca > 0.005,
      valorDevolvido: dev,
      valorTroca: troca,
    );
  }

  List<RegistroDevolucao> listarRegistrosDevolucaoPorVenda(int vendaId) {
    final lista =
        _devolucoes.where((r) => r.vendaOrigem.targetId == vendaId).toList();
    lista.sort((a, b) => b.data.compareTo(a.data));
    return lista;
  }

  /// Ranking aproximado a partir do cache local do terminal (sem ObjectBox).
  List<int> listarProdutoIdsMaisVendidos({
    int dias = 30,
    int limite = 50,
  }) {
    if (limite <= 0) return const [];
    final fim = DateTime.now().toUtc();
    final inicio = fim.subtract(Duration(days: dias));
    final qtdPorProduto = <int, int>{};
    for (final v in _porId.values) {
      if (v.cancelada || v.status != 'finalizada') continue;
      final d = v.data.toUtc();
      if (d.isBefore(inicio) || d.isAfter(fim)) continue;
      for (final item in listarItensPorVenda(v.id)) {
        final pid = item.produto.targetId;
        if (pid <= 0) continue;
        final q = item.quantidade - item.quantidadeDevolvida;
        if (q <= 0) continue;
        qtdPorProduto[pid] = (qtdPorProduto[pid] ?? 0) + q;
      }
    }
    final ordenado = qtdPorProduto.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ordenado.take(limite).map((e) => e.key).toList();
  }

  double impactoFaturamentoRegistro(RegistroDevolucao r) =>
      _impactoFaturamentoPorRegistro[r.id] ??
      (r.tipo == 'troca'
          ? valorSaidaTrocaRegistro(r) - valorReferenciaEntradaRegistro(r)
          : -valorReferenciaEntradaRegistro(r));

  double impactoLucroRegistro(RegistroDevolucao r) =>
      _impactoLucroPorRegistro[r.id] ?? 0;

  List<DeltaProdutoDevolucao> listarDeltasProdutosDevolucaoPeriodo(
    PeriodoFiltro periodo,
  ) {
    final out = <DeltaProdutoDevolucao>[];
    for (final r in listarRegistrosDevolucaoPorPeriodo(periodo)) {
      for (final l in r.linhasEntrada) {
        final nome = l.nomeProdutoSnapshot.trim();
        out.add(
          DeltaProdutoDevolucao(
            chaveAgg: l.produto.targetId > 0
                ? 'id:${l.produto.targetId}'
                : 'nome:$nome',
            nomeExibicao: nome.isEmpty ? 'Produto' : nome,
            produtoId: l.produto.targetId,
            deltaQuantidade: -l.quantidade,
            deltaValor: -(l.quantidade * l.precoUnitarioReferencia),
          ),
        );
      }
      for (final l in r.linhasSaidaTroca) {
        final nome = l.nomeProdutoSnapshot.trim();
        out.add(
          DeltaProdutoDevolucao(
            chaveAgg: l.produto.targetId > 0
                ? 'id:${l.produto.targetId}'
                : 'nome:$nome',
            nomeExibicao: nome.isEmpty ? 'Produto' : nome,
            produtoId: l.produto.targetId,
            deltaQuantidade: l.quantidade,
            deltaValor: l.quantidade * l.precoUnitario,
          ),
        );
      }
    }
    return out;
  }

  List<HistoricoEntrega> listarHistoricoEntregaGlobal({
    DateTime? inicio,
    DateTime? fim,
    String termoBusca = '',
  }) {
    var lista = List<HistoricoEntrega>.from(_historicoEntregas);
    if (inicio != null) {
      final ini = DateTime(inicio.year, inicio.month, inicio.day);
      lista = lista
          .where((h) => !h.dataHora.toLocal().isBefore(ini))
          .toList();
    }
    if (fim != null) {
      final f = DateTime(fim.year, fim.month, fim.day, 23, 59, 59, 999);
      lista = lista.where((h) => !h.dataHora.toLocal().isAfter(f)).toList();
    }
    final termo = termoBusca.trim().toLowerCase();
    if (termo.isNotEmpty) {
      lista = lista.where((h) {
        final vendaId = _vendaPorHistoricoEntrega[h.id] ?? 0;
        final venda = _vendasRelatorio[vendaId];
        final numero = venda == null
            ? ''
            : '${venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id}';
        return numero.contains(termo) ||
            h.usuario.toLowerCase().contains(termo) ||
            h.statusNovo.toLowerCase().contains(termo);
      }).toList();
    }
    lista.sort((a, b) => b.dataHora.compareTo(a.dataHora));
    return lista;
  }

  List<HistoricoEntrega> listarHistoricoEntrega(int vendaId) =>
      _historicoEntregas
          .where((h) => (_vendaPorHistoricoEntrega[h.id] ?? 0) == vendaId)
          .toList()
        ..sort((a, b) => a.dataHora.compareTo(b.dataHora));

  Future<List<HistoricoEntrega>> listarHistoricoEntregaRemoto(int vendaId) async {
    _exigirServidorOnline();
    final brutos = await _client.listarHistoricoEntregaPorVenda(vendaId);
    final out = <HistoricoEntrega>[];
    for (final m in brutos) {
      final h = SyncEntityCodecExtras.historicoEntregaDeMap(m);
      final vid = (m['vendaId'] as num?)?.toInt() ?? vendaId;
      h.venda.targetId = vid;
      final venda = _porId[vid] ?? _vendasRelatorio[vid];
      if (venda != null) h.venda.target = venda;
      out.add(h);
      _vendaPorHistoricoEntrega[h.id] = vid;
      final i = _historicoEntregas.indexWhere((x) => x.id == h.id);
      if (i >= 0) {
        _historicoEntregas[i] = h;
      } else {
        _historicoEntregas.add(h);
      }
    }
    out.sort((a, b) => a.dataHora.compareTo(b.dataHora));
    return out;
  }

  void vincularClienteNoOrcamento(int vendaId, int? clienteId) {
    throw StateError(
      'Terminal leve: use vincularClienteNoOrcamentoRemoto (async).',
    );
  }

  void vincularVendedorNoOrcamento(int vendaId, int vendedorId) {
    throw StateError(
      'Terminal leve: use vincularVendedorNoOrcamentoRemoto (async).',
    );
  }

  void aplicarDescontoNoOrcamento(int vendaId, double valor) {
    throw StateError(
      'Terminal leve: use aplicarDescontoNoOrcamentoRemoto (async).',
    );
  }

  void removerItemOrcamento(int vendaId, int itemId) {
    throw StateError('Terminal leve: use removerItemOrcamentoRemoto (async).');
  }

  void adicionarItemAoOrcamento(
    int vendaId,
    ItemVendaInput input, {
    bool permitirVendaSemEstoque = false,
  }) {
    throw StateError(
      'Terminal leve: use adicionarItemAoOrcamentoRemoto (async).',
    );
  }

  void atualizarQuantidadeItemOrcamento(
    int vendaId,
    int itemId,
    int qtd, {
    bool permitirVendaSemEstoque = false,
  }) {
    throw StateError(
      'Terminal leve: use atualizarQuantidadeItemOrcamentoRemoto (async).',
    );
  }

  void atualizarTipoEntregaItemOrcamento(
    int vendaId,
    int itemId,
    String tipoEntregaItem,
  ) {
    throw StateError(
      'Terminal leve: use atualizarTipoEntregaItemOrcamentoRemoto (async).',
    );
  }

  void alterarPagamentoOrcamento(int vendaId, dynamic resultado) {
    throw StateError(
      'Terminal leve: use alterarPagamentoOrcamentoRemoto (async).',
    );
  }

  void substituirPagamentosMistoOrcamento(int vendaId, List linhas) {
    throw StateError(
      'Terminal leve: use substituirPagamentosMistoOrcamentoRemoto (async).',
    );
  }
  void registrarBaixaEstoqueCupomNaoFiscal(
    int vendaId, {
    bool permitirVendaSemEstoque = true,
  }) {
    // No-op no terminal: a baixa fisica ocorre no PC servidor em
    // POST /api/vendas/<id>/finalizar (converterOrcamentoParaVenda).
  }

  void reprocessarBaixaEstoqueDocumentoVenda(
    int vendaId, {
    bool permitirVendaSemEstoque = true,
  }) {
    throw StateError(
      'Terminal leve: use reprocessarBaixaEstoqueDocumentoVendaRemoto.',
    );
  }

  Future<void> reprocessarBaixaEstoqueDocumentoVendaRemoto(
    int vendaId, {
    bool permitirVendaSemEstoque = true,
  }) async {
    _exigirServidorOnline();
    await _client.reprocessarBaixaEstoque(
      vendaId: vendaId,
      permitirVendaSemEstoque: permitirVendaSemEstoque,
    );
  }
  void corrigirFinalizadaEmCopiadaDaDataOrcamento() {}
  dynamic obterNfe55AutorizadaPorVenda(int vendaId) {
    final v = _porId[vendaId];
    if (v == null || !v.nfe55Autorizada) return null;
    return NfeVendaSync.registroFromVenda(v);
  }

  void registrarNfeEmissaoEmAndamento({
    required int vendaId,
    required String deviceId,
    required String referencia,
  }) {}

  void liberarNfeEmissaoEmAndamento(int vendaId) {}

  List<Venda> listarVendasComDadosNfe55({int limit = 200}) {
    final lista = _porId.values
        .where((v) => v.nfeReferenciaFocus.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => b.data.compareTo(a.data));
    if (limit > 0 && lista.length > limit) {
      return lista.sublist(0, limit);
    }
    return lista;
  }

  TotaisMeiosPagamentoCaixa totaisMeiosPagamentoVendasFinalizadas({
    DateTime? inicio,
    DateTime? fim,
  }) {
    // Terminal: use leitura parcial remota no Caixa. Stub seguro (nao crasha).
    return const TotaisMeiosPagamentoCaixa(
      dinheiro: 0,
      pix: 0,
      debito: 0,
      credito: 0,
      vale: 0,
    );
  }

  ResumoVendasCaixaPeriodo resumoVendasFinalizadasNoPeriodo({
    DateTime? inicio,
    DateTime? fim,
  }) {
    return const ResumoVendasCaixaPeriodo(
      totalVendas: 0,
      quantidadeVendas: 0,
    );
  }
}

class _TitulosApi {
  _TitulosApi(this._parent);
  final VendaApiRepository _parent;

  void migrarTitulosLegadoSeNecessario() {}

  TituloReceber? obterPorId(int id) {
    final cached = _parent._titulosPorId[id];
    if (cached != null) return cached;
    for (final l in _parent._titulosAbertos) {
      if (l.titulo.id == id) return l.titulo;
    }
    for (final lista in _parent._titulosQuitadosPorCliente.values) {
      for (final t in lista) {
        if (t.id == id) return t;
      }
    }
    return null;
  }

  List<TituloReceberResumoLinha> listarTodosAbertos({
    bool somenteVencidos = false,
  }) {
    final base = List<TituloReceberResumoLinha>.from(_parent._titulosAbertos);
    if (!somenteVencidos) return List.unmodifiable(base);
    return base.where((l) => l.diasAtraso > 0).toList(growable: false);
  }

  List<TituloReceber> listarAbertosPorCliente(int clienteId) => _parent
      ._titulosAbertos
      .where((l) => l.titulo.cliente.targetId == clienteId)
      .map((l) => l.titulo)
      .toList(growable: false);

  List<TituloReceber> listarQuitadosPorCliente(
    int clienteId, {
    int limite = 30,
  }) {
    final cached = _parent._titulosQuitadosPorCliente[clienteId];
    if (cached == null) return const [];
    if (cached.length <= limite) return List.unmodifiable(cached);
    return cached.take(limite).toList(growable: false);
  }
}

class _RecebimentosApi {
  _RecebimentosApi(this._parent);
  final VendaApiRepository _parent;

  List listarNoPeriodo({DateTime? inicio, DateTime? fim}) => const [];

  RecebimentoFiado? obterPorId(int id) => _parent._recebimentosPorId[id];

  List<RecebimentoFiado> listarPorCliente(int clienteId) =>
      List.unmodifiable(_parent._recebimentosPorCliente[clienteId] ?? const []);

  Future<int> registrarRecebimentoTitulo({
    required int tituloId,
    required double valorRecebido,
    required String formaPagamento,
    String observacao = '',
  }) =>
      _parent.registrarRecebimentoTituloRemoto(
        tituloId: tituloId,
        valorRecebido: valorRecebido,
        formaPagamento: formaPagamento,
        observacao: observacao,
      );

  Future<int> registrarRecebimentoFifo({
    required int clienteId,
    required double valorRecebido,
    required String formaPagamento,
  }) =>
      _parent.registrarRecebimentoFifoRemoto(
        clienteId: clienteId,
        valorRecebido: valorRecebido,
        formaPagamento: formaPagamento,
      );
}

/// Adapta `resolverVendedor` ao contrato `obterPorId` de [VendaRelacaoSafe].
class _VendedorResolverAdapter {
  _VendedorResolverAdapter(this._resolver);
  final Vendedor? Function(int id) _resolver;
  Vendedor? obterPorId(int id) => _resolver(id);
}
