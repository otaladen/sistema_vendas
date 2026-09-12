import '../data/app_config_repository.dart';
import '../data/api/lan_api_client.dart';
import '../data/sync/sync_entity_codec_extras.dart';
import '../model/configuracao_terminal_local.dart';
import '../services/fiscal_config_store.dart';

/// Campos de [EmpresaConfig] que entram no payload `empresa_config` (servidor).
///
/// Demais campos (impressora, bobina, rede deste PC, etc.) ficam em
/// [ConfiguracaoTerminalLocal] / [SyncLocalConfig].
abstract final class ConfiguracaoEscopo {
  ConfiguracaoEscopo._();

  static const camposSincronizadosServidor = {
    'nomeLoja',
    'telefone',
    'endereco',
    'modeloPdf',
    'rodapeNota',
    'rodapeOrcamento',
    'limiteDivergenciaCaixa',
    'mostrarCampoDescontoCaixa',
    'exigirAutorizacaoSegundaViaCupom',
    'maxDescontoPercentualPdv',
    'permitirVendaSemEstoque',
    'layoutImpressaoJson',
    'margemMinimaPercentualPadrao',
    'regimeTributarioEmitente',
    'pdvBalcaoRapido',
    'pdvCheckoutDireto',
    'pdvPularDialogOrcamentoSalvo',
    'pdvExigirVendedor',
    'pdvBloqueioVendedor',
    'pdvBloqueioVendedorInatividadeMinutos',
    'pdvBloqueioVendedorAposOrcamento',
    'pdvExigirClienteRetiradaFutura',
    'caixaFiscalNaoBloqueante',
    'caixaLimiteOrcamentosPendentes',
    'umCaixaAbertoPorLoja',
    'auditoriaRetencaoDias',
    'podFotoRetencaoDias',
    'backupAutomaticoAtivo',
    'backupAutomaticoIntervaloMinutos',
    'backupRetencaoMaxCopias',
    'backupSegundoDestinoAtivo',
    'obraCalcTijoloProdutoId',
    'obraCalcCimentoProdutoId',
    'obraCalcAreiaProdutoId',
    'obraCalcPisoProdutoId',
    'obraCalcPerdaPadraoPct',
    'obraCalcPerdaRebocoPct',
    'obraCalcPerdaPisoPct',
    'obraCalcEspessuraRebocoMm',
    'obraCalcEspessuraContrapisoMm',
    'obraCalcM2PorCaixaPiso',
    'obraCalcGeminiParseAtivo',
    'obraCalcTemplatesJson',
    'obraCalcBritaProdutoId',
    'obraCalcTelhaProdutoId',
    'obraCalcFerroProdutoId',
    'obraCalcEspessuraLajeMm',
    'obraCalcPerdaLajePct',
    'obraCalcPerdaFundacaoPct',
    'obraCalcPerdaTelhadoPct',
    'obraCalcTelhasPorM2',
    'obraCalcInclinacaoTelhadoPct',
    'obraCalcUsarSubstitutoEstoqueZero',
  };
}

/// Facade: configuracao global da loja (servidor/sync) vs terminal local.
class ConfiguracoesService {
  ConfiguracoesService(
    this._repository, {
    this.lanApiClient,
  });

  static ConfiguracoesService? _instanciaGlobal;

  /// Instancia registrada em [main] — use em servicos fora da arvore de widgets.
  static ConfiguracoesService get global {
    final i = _instanciaGlobal;
    if (i == null) {
      throw StateError(
        'ConfiguracoesService nao inicializado. Chame ConfiguracoesService.registrar na abertura.',
      );
    }
    return i;
  }

  static ConfiguracoesService? get tryGlobal => _instanciaGlobal;

  /// Leitura de config no servidor/API quando [registrar] ja rodou no mesmo processo.
  static AppConfigRepository repositoryFallback() =>
      tryGlobal?.repository ?? AppConfigRepository();

  /// Cria o servico, registra como global e retorna a instancia.
  static ConfiguracoesService registrar(AppConfigRepository repository) {
    final s = ConfiguracoesService(repository);
    _instanciaGlobal = s;
    return s;
  }

  final AppConfigRepository _repository;

  /// Repositorio de persistencia (sync/backup interno).
  AppConfigRepository get repository => _repository;

  LanApiClient? lanApiClient;

  void vincularLanApiClient(LanApiClient? client) {
    lanApiClient = client;
  }

  /// Carrega prefs locais, fiscal e — quando possivel — global do servidor.
  Future<EmpresaConfig> inicializarNaAbertura({
    required bool terminalLeve,
  }) async {
    await FiscalConfigStore.carregar();
    var cfg = await carregarEfetiva();
    await FiscalConfigStore.aplicarRegimeEmpresa(cfg.regimeTributarioEmitente);
    if (terminalLeve) {
      final client = lanApiClient;
      if (client != null && client.configurado) {
        cfg = await carregarGlobalDoServidor();
      }
    }
    return cfg;
  }

  /// Config mesclada (global + local) — compativel com o restante do app.
  Future<EmpresaConfig> carregarEfetiva() =>
      _repository.carregarEmpresaConfig();

  /// Grava config mesclada (preserva campos locais ja presentes em [config]).
  Future<void> salvarEfetiva(
    EmpresaConfig config, {
    bool propagarRede = true,
  }) =>
      _repository.salvarEmpresaConfig(
        config,
        propagarRede: propagarRede,
      );

  Future<ConfiguracaoTerminalLocal> carregarTerminalLocal() async {
    final c = await carregarEfetiva();
    return ConfiguracaoTerminalLocal.fromEmpresaConfig(c);
  }

  /// Persiste apenas preferencias deste dispositivo (nao dispara sync de loja).
  Future<void> salvarTerminalLocal(ConfiguracaoTerminalLocal local) async {
    final atual = await carregarEfetiva();
    await _repository.salvarEmpresaConfig(
      local.aplicarEm(atual),
      propagarRede: false,
    );
  }

  /// Salva parametros da loja e propaga na rede quando [propagarRede] for true.
  Future<void> salvarGlobalLoja(
    EmpresaConfig global, {
    bool propagarRede = true,
  }) async {
    final local = await carregarTerminalLocal();
    await _repository.salvarEmpresaConfig(
      local.aplicarEm(global),
      propagarRede: propagarRede,
    );
  }

  /// Terminal leve: mescla config vinda da API com o que e local neste PC.
  Future<EmpresaConfig> carregarGlobalDoServidor({
    bool persistirCache = true,
  }) async {
    final localBase = await carregarEfetiva();
    final client = lanApiClient;
    if (client is! LanApiClient || !client.configurado) {
      return localBase;
    }
    try {
      final m = await client.obterEmpresaConfig();
      final raw = m['config'];
      if (raw is! Map) return localBase;
      final mesclado = SyncEntityCodecExtras.empresaConfigDeMap(
        localBase,
        Map<String, dynamic>.from(raw),
      );
      if (persistirCache) {
        await _repository.salvarEmpresaConfig(
          mesclado,
          propagarRede: false,
        );
      }
      return mesclado;
    } catch (_) {
      return localBase;
    }
  }

  /// Dados fiscais globais (Focus) — sempre do servidor de emissao / prefs locais do PC 1.
  Future<FiscalConfigDados> carregarFiscalGlobal() =>
      FiscalConfigStore.carregar();
}
