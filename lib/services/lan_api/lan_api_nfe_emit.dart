import '../../config/focus_nfe_runtime.dart';
import '../../data/nfe_inutilizacao_store.dart';
import '../../data/nfe_saida_fiscal_store.dart';
import '../../data/sync/sync_cursor_storage.dart';
import '../../data/sync/sync_entity_codec.dart';
import '../../domain/fiscal/endereco_fiscal_ibge_resolver.dart';
import '../../domain/fiscal/fiscal_emissao_lock.dart';
import '../../domain/fiscal/nfe_cce_reconciliacao.dart';
import '../../domain/fiscal/nfe_carta_correcao_registro.dart';
import '../../domain/fiscal/nfe_painel_resumo.dart';
import '../../domain/fiscal/nfe_pendencias_service.dart';
import '../../domain/fiscal/nfe_referencia_resolver.dart';
import '../../domain/fiscal/nfe_registro_focus_merge.dart';
import '../../domain/fiscal/nfe_venda_sync.dart';
import '../../domain/fiscal/venda_documento_fiscal_mutex.dart';
import '../../model/cliente.dart';
import '../../services/focus_nfe_reconsulta_helper.dart';
import '../../services/focus_nfe_service.dart';
import '../../services/venda_fiscal_service.dart';
import 'lan_api_deps.dart';

FocusNfeDadosLogistica _logisticaDeMap(Map<String, dynamic>? raw) {
  if (raw == null) return const FocusNfeDadosLogistica();
  return FocusNfeDadosLogistica(
    modalidadeFrete: (raw['modalidadeFrete'] as num?)?.toInt() ?? 0,
    placaVeiculo: (raw['placaVeiculo'] ?? '').toString(),
    volumes: (raw['volumes'] as num?)?.toInt() ?? 1,
    pesoBrutoKg: (raw['pesoBrutoKg'] as num?)?.toDouble() ?? 0,
    especieVolumes: (raw['especieVolumes'] ?? 'VOLUMES').toString(),
  );
}

FocusNfeDestinatarioNfe? _destinatarioDeMap(Map<String, dynamic>? raw) {
  if (raw == null) return null;
  final ibge = (raw['codigoMunicipioIbge'] ?? '').toString().replaceAll(
        RegExp(r'\D'),
        '',
      );
  if (ibge.length != 7) return null;
  final nome = (raw['nome'] ?? '').toString().trim();
  final documento =
      (raw['documento'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
  if (nome.isEmpty || documento.isEmpty) return null;
  return FocusNfeDestinatarioNfe(
    nome: nome,
    documento: documento,
    inscricaoEstadual:
        (raw['inscricaoEstadual'] ?? '').toString().replaceAll(RegExp(r'\D'), ''),
    indicadorInscricaoEstadual:
        (raw['indicadorInscricaoEstadual'] ?? '9').toString(),
    logradouro: (raw['logradouro'] ?? '').toString(),
    numero: (raw['numero'] ?? 'S/N').toString(),
    bairro: (raw['bairro'] ?? '').toString(),
    municipio: (raw['municipio'] ?? '').toString(),
    codigoMunicipioIbge: ibge,
    uf: (raw['uf'] ?? '').toString().toUpperCase(),
    cep: (raw['cep'] ?? '').toString().replaceAll(RegExp(r'\D'), ''),
    telefone: (raw['telefone'] ?? '').toString().replaceAll(RegExp(r'\D'), ''),
    email: (raw['email'] ?? '').toString(),
    complemento: (raw['complemento'] ?? '').toString(),
  );
}

Future<FocusNfeDestinatarioNfe?> _resolverDestinatarioDoCliente(
  Cliente cliente,
) async {
  final ibge = await EnderecoFiscalIbgeResolver.resolverParaCliente(cliente);
  if (!ibge.sucesso || ibge.endereco == null) {
    throw FocusNfeValidacaoException(
      ibge.mensagem.isNotEmpty
          ? ibge.mensagem
          : 'Nao foi possivel resolver o IBGE do destinatario.',
    );
  }
  return FocusNfeDestinatarioNfe.fromCliente(
    cliente,
    codigoMunicipioIbge: ibge.codigoIbge,
    enderecoOverride: ibge.endereco,
  );
}

/// Emissao NF-e 55 headless no processo do PC servidor (sem UI).
Future<Map<String, dynamic>> lanApiEmitirNfe({
  required LanApiDeps d,
  required int vendaId,
  Map<String, dynamic>? destinatarioJson,
  Map<String, dynamic>? logisticaJson,
  bool permitirVendaSemEstoque = true,
}) async {
  final vendaRepo = d.vendaRepository;
  var venda = vendaRepo.obterPorId(vendaId);
  if (venda == null) {
    return {'ok': false, 'error': 'Venda $vendaId nao encontrada.', 'status': 404};
  }

  final bloqueio = VendaDocumentoFiscalMutex.mensagemBloqueioNovaNfe55(venda);
  if (bloqueio != null) {
    return {'ok': false, 'error': bloqueio, 'status': 409};
  }

  final focus = FocusNfeService(config: criarFocusNfeConfigPadrao());
  try {
    focus.validarConfiguracao();
  } catch (e) {
    return {'ok': false, 'error': '$e', 'status': 400};
  }

  final deviceId = await SyncCursorStorage().obterOuCriarDeviceId();
  if (FiscalEmissaoLock.nfeBloqueadaPorOutroDispositivo(venda, deviceId)) {
    return {
      'ok': false,
      'error':
          'Outro PC esta emitindo NF-e desta venda. Aguarde e tente novamente.',
      'status': 409,
    };
  }

  FocusNfeDestinatarioNfe? destinatario = _destinatarioDeMap(destinatarioJson);
  if (destinatario == null) {
    Cliente? cliente;
    if (venda.cliente.targetId > 0) {
      cliente = d.clienteRepository.obterPorId(venda.cliente.targetId);
    }
    if (cliente == null) {
      return {
        'ok': false,
        'error': 'Venda sem cliente vinculado para NF-e.',
        'status': 400,
      };
    }
    try {
      destinatario = await _resolverDestinatarioDoCliente(cliente);
    } on FocusNfeValidacaoException catch (e) {
      return {'ok': false, 'error': e.message, 'status': 400};
    } catch (e) {
      return {'ok': false, 'error': '$e', 'status': 400};
    }
  }
  if (destinatario == null) {
    return {
      'ok': false,
      'error': 'Destinatario incompleto para NF-e.',
      'status': 400,
    };
  }

  final store = NfeSaidaFiscalStore(d.objectBox.storeDirectoryPath);
  final historicoVenda = store
      .listar()
      .where((r) => r.vendaId == vendaId)
      .toList()
    ..sort((a, b) => b.emitidaEm.compareTo(a.emitidaEm));
  final referencia = NfeReferenciaResolver.proximaParaEmissao(
    venda: venda,
    ultimaLocal: historicoVenda.isNotEmpty ? historicoVenda.first : null,
    historicoVenda: historicoVenda,
  );

  vendaRepo.registrarNfeEmissaoEmAndamento(
    vendaId: venda.id,
    deviceId: deviceId,
    referencia: referencia,
  );

  final logistica = _logisticaDeMap(logisticaJson);
  FocusNfeEmissaoResultado resultado;
  try {
    venda = vendaRepo.obterPorId(vendaId) ?? venda;
    resultado = await focus.emitirNfe(
      venda,
      destinatario: destinatario,
      logistica: logistica,
      referencia: referencia,
    );
    if (!resultado.autorizada && !resultado.processando) {
      resultado = await FocusNfeReconsultaHelper.recuperarSePossivel(
        original: resultado,
        reconsultar: () => focus.consultarNfe(referencia),
      );
      if (FocusNfeService.pareceFalhaComunicacao(resultado) &&
          !resultado.autorizada &&
          !resultado.processando) {
        resultado =
            FocusNfeReconsultaHelper.comoProcessandoAposFalhaComunicacao(
          referencia: referencia,
        );
      }
    }
  } on FocusNfeValidacaoException catch (e) {
    vendaRepo.liberarNfeEmissaoEmAndamento(vendaId);
    return {'ok': false, 'error': e.message, 'status': 400};
  } on FocusNfeConfigIncompletaException catch (e) {
    vendaRepo.liberarNfeEmissaoEmAndamento(vendaId);
    return {'ok': false, 'error': e.message, 'status': 400};
  } catch (e) {
    vendaRepo.liberarNfeEmissaoEmAndamento(vendaId);
    return {'ok': false, 'error': 'Erro ao emitir NF-e: $e', 'status': 502};
  }

  final clienteNome = destinatario.nome;
  final registro = NfeSaidaFiscalRegistro(
    id: '${DateTime.now().millisecondsSinceEpoch}',
    vendaId: vendaId,
    numeroOrcamento:
        venda.numeroOrcamento > 0 ? venda.numeroOrcamento : vendaId,
    clienteNome: clienteNome,
    referenciaFocus: resultado.referencia.isNotEmpty
        ? resultado.referencia
        : referencia,
    statusFocus: resultado.statusFocus,
    emitidaEm: DateTime.now(),
    statusSefaz: resultado.statusSefaz,
    chaveNfe: resultado.chaveNfe,
    numero: resultado.numero,
    serie: resultado.serie,
    protocolo: resultado.protocolo,
    urlDanfe: resultado.urlDanfe,
    urlXml: resultado.urlXml,
    urlXmlEventoCancelamento: resultado.urlXmlCancelamento,
    mensagemSefaz: resultado.mensagem,
    modalidadeFrete: logistica.modalidadeFrete,
    placaVeiculo: logistica.placaVeiculo,
    volumes: logistica.volumes,
    pesoBrutoKg: logistica.pesoBrutoKg,
    valorTotal: venda.total,
  );

  if (resultado.autorizada || resultado.processando) {
    try {
      store.gravar(registro);
      NfeVendaSync.aplicarRegistroNoRepositorio(
        vendaRepository: vendaRepo,
        registro: registro,
      );
      // Baixa de estoque so na autorizacao (aplicarRegistro ja trata).
      if (resultado.autorizada && permitirVendaSemEstoque) {
        // noop: registrarNfe55SituacaoComBaixaEstoque ja aplicado.
      }
      d.notificar('venda');
      d.notificar('produto');
      d.notificar('nfe_saida');
      d.notificar('fiscal', ids: [vendaId]);
      return {
        'ok': true,
        'autorizada': resultado.autorizada,
        'processando': resultado.processando,
        'chaveNfe': resultado.chaveNfe,
        'numero': resultado.numero,
        'serie': resultado.serie,
        'protocolo': resultado.protocolo,
        'urlDanfe': resultado.urlDanfe,
        'urlXml': resultado.urlXml,
        'referencia': registro.referenciaFocus,
        'statusFocus': resultado.statusFocus,
        'registro': registro.toJson(),
      };
    } catch (e) {
      return {
        'ok': false,
        'error': 'NF-e processada, mas falhou ao gravar: $e',
        'status': 500,
        'autorizada': resultado.autorizada,
        'chaveNfe': resultado.chaveNfe,
      };
    }
  }

  vendaRepo.liberarNfeEmissaoEmAndamento(vendaId);
  try {
    store.gravar(registro);
    NfeVendaSync.aplicarRegistroNoRepositorio(
      vendaRepository: vendaRepo,
      registro: registro,
    );
    d.notificar('venda');
  } catch (_) {}

  return {
    'ok': false,
    'error': resultado.mensagem.isNotEmpty
        ? resultado.mensagem
        : 'NF-e nao autorizada.',
    'status': 400,
    'statusFocus': resultado.statusFocus,
    'registro': registro.toJson(),
  };
}

/// Historico unificado + KPIs + pendencias do painel NF-e 55.
Map<String, dynamic> lanApiListarNfeSaida(LanApiDeps d, {int limit = 300}) {
  final store = NfeSaidaFiscalStore(d.objectBox.storeDirectoryPath);
  final inut = NfeInutilizacaoStore(d.objectBox.storeDirectoryPath);
  final lista = NfeVendaSync.listarHistoricoUnificado(
    store: store,
    vendaRepository: d.vendaRepository,
    limiteVendas: limit,
  );
  final semNfe = NfePendenciasService.listarVendasSemNfeAutorizada(
    vendaRepository: d.vendaRepository,
    nfeStore: store,
  );
  final processando = NfePendenciasService.listarProcessando(
    store,
    vendaRepository: d.vendaRepository,
  );
  final rejeitadas = NfePendenciasService.listarRejeitadasRecentes(
    store,
    vendaRepository: d.vendaRepository,
  );
  final comAuth = NfePendenciasService.idsVendasComNfeAutorizada(
    store,
    vendaRepository: d.vendaRepository,
  );
  final resumo = NfePainelResumoBuilder.calcular(
    historico: lista,
    vendasSemNfe: semNfe.length,
    inutilizacaoStore: inut,
    nfeStore: store,
    vendasComNfeAutorizada: comAuth,
  );
  return {
    'ok': true,
    'items': lista.map((e) => e.toJson()).toList(),
    'pendencias': {
      'vendasSemNfe': [
        for (final p in semNfe)
          {
            'venda': SyncEntityCodec.vendaParaMap(p.venda),
            'clienteNome': p.clienteNome,
            'ultimoStatusNfe': p.ultimoStatusNfe,
          },
      ],
      'processando': processando.map((e) => e.toJson()).toList(),
      'rejeitadas': rejeitadas.map((e) => e.toJson()).toList(),
    },
    'meta': {
      'totalRegistros': resumo.totalRegistros,
      'autorizadas': resumo.autorizadas,
      'processando': resumo.processando,
      'rejeitadas': resumo.rejeitadas,
      'canceladas': resumo.canceladas,
      'vendasSemNfeAutorizada': resumo.vendasSemNfeAutorizada,
      'totalCartasCorrecao': resumo.totalCartasCorrecao,
      'cartasCorrecaoProcessando': resumo.cartasCorrecaoProcessando,
      'lacunasNumeracaoSerie1': resumo.lacunasNumeracaoSerie1,
      'inutilizacoesRegistradas': resumo.inutilizacoesRegistradas,
    },
  };
}

NfeSaidaFiscalStore _nfeStore(LanApiDeps d) =>
    NfeSaidaFiscalStore(d.objectBox.storeDirectoryPath);

FocusNfeService _focusNfe() =>
    FocusNfeService(config: criarFocusNfeConfigPadrao());

Future<Map<String, dynamic>> lanApiReconsultarNfeSaida(
  LanApiDeps d, {
  required String referencia,
}) async {
  final ref = referencia.trim();
  if (ref.isEmpty) {
    return {'ok': false, 'error': 'referencia obrigatoria', 'status': 400};
  }
  final store = _nfeStore(d);
  final reg = store.obterPorReferencia(ref);
  if (reg == null) {
    return {'ok': false, 'error': 'registro nao encontrado', 'status': 404};
  }
  try {
    final focus = _focusNfe();
    final r = await focus.consultarNfe(ref);
    var atualizado = mesclarRegistroComResultadoFocus(reg, r);
    atualizado = await reconsultarCartasCorrecaoPendentes(
      registro: atualizado,
      focusNfe: focus,
      storeDirectoryPath: d.objectBox.storeDirectoryPath,
    );
    store.gravar(atualizado);
    NfeVendaSync.aplicarRegistroNoRepositorio(
      vendaRepository: d.vendaRepository,
      registro: atualizado,
    );
    d.notificar('venda');
    d.notificar('produto');
    d.notificar('nfe_saida');
    return {
      'ok': true,
      'autorizada': atualizado.autorizada,
      'cancelada': atualizado.cancelada,
      'processando': atualizado.processando,
      'status': atualizado.rotuloStatus,
      'registro': atualizado.toJson(),
    };
  } catch (e) {
    return {'ok': false, 'error': '$e', 'status': 400};
  }
}

Future<Map<String, dynamic>> lanApiReconsultarNfeSaidaProcessando(
  LanApiDeps d,
) async {
  final store = _nfeStore(d);
  final fila = NfePendenciasService.listarProcessando(
    store,
    vendaRepository: d.vendaRepository,
  );
  var autorizadas = 0;
  final focus = _focusNfe();
  for (final reg in fila) {
    try {
      final r = await focus.consultarNfe(reg.referenciaFocus);
      var atualizado = mesclarRegistroComResultadoFocus(reg, r);
      atualizado = await reconsultarCartasCorrecaoPendentes(
        registro: atualizado,
        focusNfe: focus,
        storeDirectoryPath: d.objectBox.storeDirectoryPath,
      );
      store.gravar(atualizado);
      NfeVendaSync.aplicarRegistroNoRepositorio(
        vendaRepository: d.vendaRepository,
        registro: atualizado,
      );
      if (atualizado.autorizada) autorizadas++;
    } catch (_) {}
  }
  d.notificar('venda');
  d.notificar('produto');
  d.notificar('nfe_saida');
  return {
    'ok': true,
    'total': fila.length,
    'autorizadas': autorizadas,
  };
}

Future<Map<String, dynamic>> lanApiCancelarNfeSaida(
  LanApiDeps d, {
  required String referencia,
  required String justificativa,
}) async {
  final ref = referencia.trim();
  final just = justificativa.trim();
  if (ref.isEmpty) {
    return {'ok': false, 'error': 'referencia obrigatoria', 'status': 400};
  }
  if (just.length < 15) {
    return {
      'ok': false,
      'error': 'Justificativa deve ter ao menos 15 caracteres.',
      'status': 400,
    };
  }
  final store = _nfeStore(d);
  final reg = store.obterPorReferencia(ref);
  if (reg == null) {
    return {'ok': false, 'error': 'registro nao encontrado', 'status': 404};
  }
  try {
    final r = await _focusNfe().cancelarNfe(ref, justificativa: just);
    if (r.rejeitada && !r.cancelada) {
      return {
        'ok': false,
        'error': r.mensagem.isNotEmpty
            ? r.mensagem
            : 'Cancelamento nao aceito pela SEFAZ.',
        'status': 400,
        'statusFocus': r.statusFocus,
      };
    }
    final atualizado = mesclarRegistroComResultadoFocus(reg, r);
    store.gravar(atualizado);
    NfeVendaSync.aplicarRegistroNoRepositorio(
      vendaRepository: d.vendaRepository,
      registro: atualizado,
    );
    d.notificar('venda');
    d.notificar('nfe_saida');
    return {
      'ok': true,
      'cancelada': atualizado.cancelada,
      'status': atualizado.rotuloStatus,
      'registro': atualizado.toJson(),
      'mensagem': atualizado.cancelada
          ? 'NF-e cancelada na SEFAZ.'
          : 'Solicitacao enviada: ${atualizado.rotuloStatus}',
    };
  } catch (e) {
    return {'ok': false, 'error': '$e', 'status': 400};
  }
}

Future<Map<String, dynamic>> lanApiCartaCorrecaoNfeSaida(
  LanApiDeps d, {
  required String referencia,
  required String correcao,
}) async {
  final ref = referencia.trim();
  final texto = correcao.trim();
  if (ref.isEmpty) {
    return {'ok': false, 'error': 'referencia obrigatoria', 'status': 400};
  }
  if (texto.length < 15) {
    return {
      'ok': false,
      'error': 'Texto da CC-e deve ter ao menos 15 caracteres.',
      'status': 400,
    };
  }
  final store = _nfeStore(d);
  final reg = store.obterPorReferencia(ref);
  if (reg == null) {
    return {'ok': false, 'error': 'registro nao encontrado', 'status': 404};
  }
  try {
    final res = await _focusNfe().emitirCartaCorrecaoNfe(ref, correcao: texto);
    if (!res.sucesso) {
      return {
        'ok': false,
        'error': res.mensagem.isNotEmpty ? res.mensagem : 'Falha ao emitir CC-e.',
        'status': 400,
      };
    }
    final atualizado = reg.comNovaCartaCorrecao(
      NfeCartaCorrecaoRegistro(
        numeroSequencia: res.numeroSequencia > 0 ? res.numeroSequencia : 1,
        textoCorrecao: texto,
        urlPdf: res.urlPdf,
        urlXml: res.urlXml,
        protocolo: res.protocolo,
        statusFocus:
            res.statusFocus.isEmpty ? 'autorizado' : res.statusFocus,
      ),
    );
    store.gravar(atualizado);
    NfeVendaSync.aplicarRegistroNoRepositorio(
      vendaRepository: d.vendaRepository,
      registro: atualizado,
    );
    d.notificar('venda');
    d.notificar('nfe_saida');
    return {
      'ok': true,
      'processando': res.processando,
      'numeroSequencia': res.numeroSequencia,
      'mensagem': res.processando
          ? 'CC-e enviada — aguardando SEFAZ.'
          : (res.mensagem.isNotEmpty ? res.mensagem : 'CC-e registrada.'),
      'registro': atualizado.toJson(),
    };
  } catch (e) {
    return {'ok': false, 'error': '$e', 'status': 400};
  }
}

/// Cancela NFC-e/NF-e autorizada na SEFAZ (Focus no PC1) e em seguida a venda
/// no ObjectBox (estorno de estoque/fiado). Usado pelo Terminal Leve.
Future<Map<String, dynamic>> lanApiCancelarVendaFiscal(
  LanApiDeps d, {
  required int vendaId,
  required String justificativa,
  String motivo = '',
  String canceladaPor = '',
}) async {
  if (vendaId <= 0) {
    return {'ok': false, 'error': 'id invalido', 'status': 400};
  }
  final venda = d.vendaRepository.obterPorId(vendaId);
  if (venda == null) {
    return {'ok': false, 'error': 'venda nao encontrada', 'status': 404};
  }
  if (venda.cancelada) {
    return {'ok': false, 'error': 'Venda ja esta cancelada.', 'status': 400};
  }

  // Valida ERP antes da SEFAZ: evita NFC-e cancelada e venda ainda ativa.
  final bloqueioErp =
      d.vendaRepository.mensagemBloqueioCancelamentoVenda(vendaId);
  if (bloqueioErp != null) {
    return {'ok': false, 'error': bloqueioErp, 'mensagem': bloqueioErp, 'status': 400};
  }

  final fiscal = VendaFiscalService(
    vendaRepository: d.vendaRepository,
    clienteRepository: d.clienteRepository,
  );
  if (!fiscal.vendaExigeCancelamentoFiscal(venda)) {
    return {
      'ok': false,
      'error':
          'Venda sem NFC-e/NF-e autorizada. Use POST /api/vendas/$vendaId/cancelar.',
      'status': 400,
    };
  }

  final erroJust = VendaFiscalService.validarJustificativa(justificativa);
  if (erroJust.isNotEmpty) {
    return {'ok': false, 'error': erroJust, 'mensagem': erroJust, 'status': 400};
  }

  final fiscalRes = await fiscal.cancelarDocumentosFiscaisVenda(
    venda: venda,
    justificativa: justificativa,
  );
  if (!fiscalRes.sucesso) {
    d.notificar('venda');
    if (fiscalRes.nfeCancelada || fiscalRes.nfceCancelada) {
      d.notificar('nfe_saida');
    }
    return {
      'ok': false,
      'error': fiscalRes.mensagem.isNotEmpty
          ? fiscalRes.mensagem
          : 'SEFAZ nao aceitou o cancelamento fiscal.',
      'mensagem': fiscalRes.mensagem,
      'status': 400,
      'nfceCancelada': fiscalRes.nfceCancelada,
      'nfeCancelada': fiscalRes.nfeCancelada,
    };
  }

  final motivoFinal = [
    if (justificativa.trim().isNotEmpty) justificativa.trim(),
    if (motivo.trim().isNotEmpty) motivo.trim(),
  ].join(' | ');

  try {
    d.vendaRepository.cancelarVenda(
      vendaId,
      motivo: motivoFinal,
      canceladaPor: canceladaPor,
    );
  } catch (e) {
    d.notificar('venda');
    d.notificar('nfe_saida');
    return {
      'ok': false,
      'error': '$e',
      'mensagem':
          'Documento fiscal cancelado na SEFAZ, mas falhou ao cancelar a '
          'venda no ERP: $e',
      'status': 500,
      'nfceCancelada': fiscalRes.nfceCancelada,
      'nfeCancelada': fiscalRes.nfeCancelada,
      'fiscalOk': true,
    };
  }

  // produto (com ids) ja propagado por VendaRepository / SyncWriteTrigger.
  d.notificar('venda');
  d.notificar('produto');
  d.notificar('titulo_receber');
  d.notificar('nfe_saida');

  final item = d.vendaRepository.obterPorId(vendaId);
  final msgFiscal = fiscalRes.mensagem.isNotEmpty
      ? fiscalRes.mensagem
      : 'Documento fiscal cancelado na SEFAZ.';
  return {
    'ok': true,
    'mensagem': '$msgFiscal Venda cancelada no ERP.',
    'nfceCancelada': fiscalRes.nfceCancelada,
    'nfeCancelada': fiscalRes.nfeCancelada,
    'item': item == null ? null : SyncEntityCodec.vendaParaMap(item),
  };
}
