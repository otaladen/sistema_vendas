import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_config_repository.dart';
import '../data/api/lan_api_client.dart';
import '../data/sync/sync_entity_codec_extras.dart';
import 'configuracoes/obra_calculadora_config_section.dart';
import 'configuracoes/backup_configuracao_section.dart';
import 'configuracoes/backup_terminal_leve_section.dart';
import 'configuracoes/config_page_shell.dart';
import 'configuracoes/config_secao.dart';
import 'configuracoes/config_section_card.dart';
import '../data/objectbox.dart';
import '../data/sync/lan_sync_scheduler.dart';
import '../config/fiscal_config.dart';
import '../domain/pod_foto_retencao.dart';
import '../services/entrega_pod_retencao_service.dart';
import '../domain/fiscal/fiscal_regime_padrao.dart';
import '../services/fiscal_config_store.dart';
import '../services/gemini_config.dart';
import '../services/print_service.dart';
import 'widgets/rede_sincronizacao_card.dart';
import '../services/cupom_layout_preview_pdf.dart';
import '../services/cupom_pdf_layout.dart';
import 'config_impressora_page.dart';
import 'layout_impressao_page.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({
    super.key,
    required this.vendaRepository,
    required this.appConfigRepository,
    required this.printService,
    required this.produtoRepository,
    this.objectBox,
    this.lanSyncScheduler,
    this.secaoInicialId,
    this.terminalLeve = false,
    this.lanApiClient,
  });

  final dynamic vendaRepository;
  final ObjectBox? objectBox;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;
  final dynamic produtoRepository;
  final LanSyncScheduler? lanSyncScheduler;
  final String? secaoInicialId;

  /// Terminal Windows: sem banco local — backup/servidor ficam no PC 1.
  final bool terminalLeve;
  final dynamic lanApiClient;

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  final _nomeLojaController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _pastaPadraoPdfController = TextEditingController();
  final _rodapeNotaController = TextEditingController();
  final _rodapeOrcamentoController = TextEditingController();
  final _limiteDivergenciaCaixaController = TextEditingController();
  final _maxDescontoPercentualPdvController = TextEditingController();
  final _margemMinimaPadraoController = TextEditingController();
  final _geminiApiKeyController = TextEditingController();
  final _fiscalTokenController = TextEditingController();
  final _fiscalCnpjController = TextEditingController();
  final _fiscalIeController = TextEditingController();
  final _emailContadorController = TextEditingController();
  final _smtpHostController = TextEditingController();
  final _smtpPortController = TextEditingController(text: '587');
  final _smtpUserController = TextEditingController();
  final _smtpPasswordController = TextEditingController();
  final _smtpFromController = TextEditingController();
  bool _geminiChaveOculta = true;
  bool _fiscalTokenOculto = true;
  bool _smtpPasswordOculta = true;
  bool _smtpSsl = false;
  String _fiscalAmbiente = 'homologacao';
  int _fiscalRegime = FiscalRegimePadrao.regimeNormal;
  String _modeloPdf = 'cupom';
  String _impressoraPadrao = '';
  String _logoPath = '';
  bool _salvando = false;
  bool _prefsEmpresaAplicadas = false;
  DateTime _agoraSistema = DateTime.now();
  DateTime? _ultimaVendaFinalizada;
  bool _horarioInconsistente = false;
  String _diagnosticoHorario = '';
  bool _permitirVendaSemEstoque = true;
  int _podFotoRetencaoDias = 180;
  bool _pdvExigirVendedor = false;
  bool _pdvBloqueioVendedor = false;
  bool _pdvBloqueioVendedorAposOrcamento = false;
  bool _pdvBloqueioInatividadeAtivo = false;
  final _pdvBloqueioInatividadeMinutosController =
      TextEditingController(text: '5');
  bool _pdvBalcaoRapido = true;
  bool _pdvCheckoutDireto = true;
  bool _pdvPularDialogOrcamentoSalvo = true;
  bool _pdvExigirClienteRetiradaFutura = false;
  int _obraCalcTijoloProdutoId = 0;
  int _obraCalcCimentoProdutoId = 0;
  int _obraCalcAreiaProdutoId = 0;
  int _obraCalcPisoProdutoId = 0;
  double _obraCalcPerdaPadraoPct = 10;
  double _obraCalcPerdaRebocoPct = 15;
  double _obraCalcPerdaPisoPct = 10;
  double _obraCalcEspessuraRebocoMm = 20;
  double _obraCalcEspessuraContrapisoMm = 30;
  double _obraCalcM2PorCaixaPiso = 1.44;
  bool _obraCalcGeminiParseAtivo = false;
  String _obraCalcTemplatesJson = '[]';
  int _obraCalcBritaProdutoId = 0;
  int _obraCalcTelhaProdutoId = 0;
  int _obraCalcFerroProdutoId = 0;
  double _obraCalcEspessuraLajeMm = 100;
  double _obraCalcPerdaLajePct = 10;
  double _obraCalcPerdaFundacaoPct = 10;
  double _obraCalcPerdaTelhadoPct = 10;
  double _obraCalcTelhasPorM2 = 16;
  double _obraCalcInclinacaoTelhadoPct = 30;
  bool _obraCalcUsarSubstitutoEstoqueZero = true;
  bool _caixaFiscalNaoBloqueante = true;
  final _caixaLimiteOrcamentosController = TextEditingController(text: '120');
  bool _mostrarCampoDescontoCaixa = true;
  bool _exigirAutorizacaoSegundaViaCupom = true;
  bool _umCaixaAbertoPorLoja = true;
  int _indiceSecaoConfig = 0;

  @override
  void initState() {
    super.initState();
    final secao = widget.secaoInicialId?.trim();
    if (secao != null && secao.isNotEmpty) {
      _indiceSecaoConfig = ConfigSecoes.indiceDeId(secao);
    }
    _carregarConfig();
    _carregarChaveGemini();
    _carregarConfigFiscal();
    _carregarDiagnosticoHorario();
  }

  @override
  void dispose() {
    _nomeLojaController.dispose();
    _telefoneController.dispose();
    _enderecoController.dispose();
    _pastaPadraoPdfController.dispose();
    _rodapeNotaController.dispose();
    _rodapeOrcamentoController.dispose();
    _limiteDivergenciaCaixaController.dispose();
    _maxDescontoPercentualPdvController.dispose();
    _margemMinimaPadraoController.dispose();
    _geminiApiKeyController.dispose();
    _fiscalTokenController.dispose();
    _fiscalCnpjController.dispose();
    _fiscalIeController.dispose();
    _emailContadorController.dispose();
    _smtpHostController.dispose();
    _smtpPortController.dispose();
    _smtpUserController.dispose();
    _smtpPasswordController.dispose();
    _smtpFromController.dispose();
    _caixaLimiteOrcamentosController.dispose();
    _pdvBloqueioInatividadeMinutosController.dispose();
    super.dispose();
  }

  Future<void> _carregarConfigFiscal() async {
    if (widget.terminalLeve) {
      final client = widget.lanApiClient;
      if (client is LanApiClient && client.configurado) {
        try {
          final m = await client.obterEmpresaFiscal();
          final raw = m['fiscal'];
          if (raw is Map && mounted) {
            final f = Map<String, dynamic>.from(raw);
            setState(() {
              final tokenOk = f['tokenConfigurado'] == true;
              _fiscalTokenController.text = tokenOk ? '********' : '';
              _fiscalCnpjController.text =
                  (f['cnpjEmitente'] ?? '').toString();
              _fiscalIeController.text =
                  (f['inscricaoEstadualEmitente'] ?? '').toString();
              final amb = (f['ambiente'] ?? 'homologacao').toString();
              _fiscalAmbiente =
                  amb == 'producao' ? 'producao' : 'homologacao';
              final regime = (f['regimeTributarioEmitente'] as num?)?.toInt();
              if (regime != null && regime >= 1 && regime <= 3) {
                _fiscalRegime = regime;
              }
            });
            return;
          }
        } catch (e) {
          debugPrint('Config fiscal remoto: $e');
        }
      }
    }
    final cfg = await FiscalConfigStore.carregar();
    if (!mounted) return;
    setState(() {
      _fiscalTokenController.text = cfg.apiToken;
      _fiscalCnpjController.text = cfg.cnpjEmitente;
      _fiscalIeController.text = cfg.inscricaoEstadualEmitente;
      _fiscalAmbiente = cfg.homologacao ? 'homologacao' : 'producao';
      _fiscalRegime = FiscalRegimePadrao.regimeEfetivo(cfg);
      _emailContadorController.text = cfg.emailContador;
      _smtpHostController.text = cfg.smtpHost;
      _smtpPortController.text = '${cfg.smtpPort}';
      _smtpUserController.text = cfg.smtpUser;
      _smtpPasswordController.text = cfg.smtpPassword;
      _smtpFromController.text = cfg.smtpFromEmail;
      _smtpSsl = cfg.smtpSsl;
    });
  }

  Future<void> _salvarConfigFiscal() async {
    if (widget.terminalLeve) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Token Focus e dados fiscais sensiveis so podem ser alterados no PC servidor.',
          ),
        ),
      );
      return;
    }
    final token = _fiscalTokenController.text.trim();
    if (token.isNotEmpty && token.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Token Focus muito curto.')),
      );
      return;
    }
    final smtpPort =
        int.tryParse(_smtpPortController.text.trim()) ?? 587;
    await FiscalConfigStore.salvar(
      apiToken: token,
      ambiente: _fiscalAmbiente,
      cnpjEmitente: _fiscalCnpjController.text,
      inscricaoEstadualEmitente: _fiscalIeController.text,
      regimeTributarioEmitente: _fiscalRegime,
      emailContador: _emailContadorController.text,
      smtpHost: _smtpHostController.text,
      smtpPort: smtpPort,
      smtpUser: _smtpUserController.text,
      smtpPassword: _smtpPasswordController.text,
      smtpFromEmail: _smtpFromController.text,
      smtpSsl: _smtpSsl,
    );
    final empresa = await widget.appConfigRepository.carregarEmpresaConfig();
    await widget.appConfigRepository.salvarEmpresaConfig(
      empresa.copyWith(regimeTributarioEmitente: _fiscalRegime),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Fiscal salvo (${FiscalRegimePadrao.rotuloRegime(_fiscalRegime)}). '
          '${_fiscalAmbiente == 'producao' ? 'Ambiente PRODUCAO.' : 'Homologacao (testes).'}',
        ),
      ),
    );
  }

  Future<void> _abrirPainelFocus() async {
    final uri = Uri.parse('https://app.focusnfe.com.br/');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao foi possivel abrir o painel Focus.')),
      );
    }
  }

  Future<void> _carregarChaveGemini() async {
    final chave = await GeminiConfig.resolverChave();
    if (!mounted) return;
    setState(() {
      _geminiApiKeyController.text = chave;
    });
  }

  Future<void> _abrirUrlGeminiAiStudio() async {
    const url = 'https://aistudio.google.com/apikey';
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel abrir: $url')),
      );
    }
  }

  Future<void> _salvarChaveGemini() async {
    final chave = _geminiApiKeyController.text.trim();
    if (chave.isNotEmpty && !GeminiConfig.chavePareceValida(chave)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chave Gemini invalida. Cole a chave completa do Google AI Studio '
            '(geralmente comeca com AIza).',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    await GeminiConfig.salvarChave(chave);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          chave.isEmpty
              ? 'Chave Gemini removida.'
              : 'Chave Gemini salva. Padronizacao com IA liberada no cadastro de produtos.',
        ),
      ),
    );
  }

  Future<EmpresaConfig> _carregarConfigDoDiscoOuServidor() async {
    final local = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!widget.terminalLeve) return local;
    final client = widget.lanApiClient;
    if (client is! LanApiClient || !client.configurado) {
      return local;
    }
    try {
      final m = await client.obterEmpresaConfig();
      final raw = m['config'];
      if (raw is! Map) return local;
      final mesclado = SyncEntityCodecExtras.empresaConfigDeMap(
        local,
        Map<String, dynamic>.from(raw),
      );
      // Cache local para PDV/caixa; nao propaga de volta ao servidor.
      await widget.appConfigRepository.salvarEmpresaConfig(
        mesclado,
        propagarRede: false,
      );
      return mesclado;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Nao foi possivel ler configuracoes do servidor: $e. '
              'Exibindo cache local.',
            ),
          ),
        );
      }
      return local;
    }
  }

  Future<void> _carregarConfig() async {
    final config = await _carregarConfigDoDiscoOuServidor();
    if (!mounted) return;
    setState(() {
      _nomeLojaController.text = config.nomeLoja;
      _telefoneController.text = config.telefone;
      _enderecoController.text = config.endereco;
      _pastaPadraoPdfController.text = config.pastaPadraoPdf;
      _rodapeNotaController.text = config.rodapeNota;
      _rodapeOrcamentoController.text = config.rodapeOrcamento;
      _limiteDivergenciaCaixaController.text = config.limiteDivergenciaCaixa
          .toStringAsFixed(2)
          .replaceAll('.', ',');
      _modeloPdf = config.modeloPdf;
      _impressoraPadrao = config.impressoraPadrao;
      _logoPath = config.logoPath;
      _permitirVendaSemEstoque = config.permitirVendaSemEstoque;
      _podFotoRetencaoDias =
          PodFotoRetencaoOpcoes.normalizar(config.podFotoRetencaoDias);
      _pdvExigirVendedor = config.pdvExigirVendedor;
      _pdvBloqueioVendedor = config.pdvBloqueioVendedor;
      _pdvBloqueioVendedorAposOrcamento =
          config.pdvBloqueioVendedorAposOrcamento;
      _pdvBloqueioInatividadeAtivo =
          config.pdvBloqueioVendedorInatividadeMinutos > 0;
      _pdvBloqueioInatividadeMinutosController.text =
          config.pdvBloqueioVendedorInatividadeMinutos > 0
              ? '${config.pdvBloqueioVendedorInatividadeMinutos}'
              : '5';
      _pdvBalcaoRapido = config.pdvBalcaoRapido;
      _pdvCheckoutDireto = config.pdvCheckoutDireto;
      _pdvPularDialogOrcamentoSalvo = config.pdvPularDialogOrcamentoSalvo;
      _pdvExigirClienteRetiradaFutura = config.pdvExigirClienteRetiradaFutura;
      _obraCalcTijoloProdutoId = config.obraCalcTijoloProdutoId;
      _obraCalcCimentoProdutoId = config.obraCalcCimentoProdutoId;
      _obraCalcAreiaProdutoId = config.obraCalcAreiaProdutoId;
      _obraCalcPisoProdutoId = config.obraCalcPisoProdutoId;
      _obraCalcPerdaPadraoPct = config.obraCalcPerdaPadraoPct;
      _obraCalcPerdaRebocoPct = config.obraCalcPerdaRebocoPct;
      _obraCalcPerdaPisoPct = config.obraCalcPerdaPisoPct;
      _obraCalcEspessuraRebocoMm = config.obraCalcEspessuraRebocoMm;
      _obraCalcEspessuraContrapisoMm = config.obraCalcEspessuraContrapisoMm;
      _obraCalcM2PorCaixaPiso = config.obraCalcM2PorCaixaPiso;
      _obraCalcGeminiParseAtivo = config.obraCalcGeminiParseAtivo;
      _obraCalcTemplatesJson = config.obraCalcTemplatesJson;
      _obraCalcBritaProdutoId = config.obraCalcBritaProdutoId;
      _obraCalcTelhaProdutoId = config.obraCalcTelhaProdutoId;
      _obraCalcFerroProdutoId = config.obraCalcFerroProdutoId;
      _obraCalcEspessuraLajeMm = config.obraCalcEspessuraLajeMm;
      _obraCalcPerdaLajePct = config.obraCalcPerdaLajePct;
      _obraCalcPerdaFundacaoPct = config.obraCalcPerdaFundacaoPct;
      _obraCalcPerdaTelhadoPct = config.obraCalcPerdaTelhadoPct;
      _obraCalcTelhasPorM2 = config.obraCalcTelhasPorM2;
      _obraCalcInclinacaoTelhadoPct = config.obraCalcInclinacaoTelhadoPct;
      _obraCalcUsarSubstitutoEstoqueZero =
          config.obraCalcUsarSubstitutoEstoqueZero;
      _caixaFiscalNaoBloqueante = config.caixaFiscalNaoBloqueante;
      _caixaLimiteOrcamentosController.text =
          '${config.caixaLimiteOrcamentosPendentes}';
      _mostrarCampoDescontoCaixa = config.mostrarCampoDescontoCaixa;
      _exigirAutorizacaoSegundaViaCupom =
          config.exigirAutorizacaoSegundaViaCupom;
      _maxDescontoPercentualPdvController.text = config.maxDescontoPercentualPdv
          .toStringAsFixed(1)
          .replaceAll('.', ',');
      _margemMinimaPadraoController.text = config.margemMinimaPercentualPadrao
          .toStringAsFixed(1)
          .replaceAll('.', ',');
      _umCaixaAbertoPorLoja = config.umCaixaAbertoPorLoja;
      _prefsEmpresaAplicadas = true;
    });
  }

  Future<void> _carregarDiagnosticoHorario() async {
    final agora = DateTime.now();
    final vendas = widget.vendaRepository.listarTodas();
    DateTime? ultimaFinalizada;
    for (final venda in vendas) {
      if (venda.status == 'finalizada' && !venda.cancelada) {
        if (ultimaFinalizada == null || venda.data.isAfter(ultimaFinalizada)) {
          ultimaFinalizada = venda.data;
        }
      }
    }
    final inconsistente =
        ultimaFinalizada != null &&
        agora.isBefore(ultimaFinalizada.subtract(const Duration(minutes: 2)));
    if (!mounted) return;
    setState(() {
      _agoraSistema = agora;
      _ultimaVendaFinalizada = ultimaFinalizada;
      _horarioInconsistente = inconsistente;
      _diagnosticoHorario = inconsistente
          ? 'Horario do sistema esta atrasado em relacao a ultima venda finalizada. '
                'Corrija data/hora no Windows antes de emitir novas notas.'
          : 'Horario do sistema consistente para operacao de vendas e impressao.';
    });
  }

  Future<void> _abrirAjusteDataHoraSO() async {
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', 'ms-settings:dateandtime']);
      } else if (Platform.isLinux) {
        await Process.start('sh', ['-c', 'gnome-control-center datetime']);
      } else if (Platform.isMacOS) {
        await Process.start('open', [
          'x-apple.systempreferences:com.apple.preference.datetime',
        ]);
      }
    } catch (_) {
      // ignore and inform via snackbar below
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Abra as configuracoes de data/hora do sistema operacional para ajustar.',
        ),
      ),
    );
  }

  Future<void> _sincronizarHorarioWindows() async {
    if (!Platform.isWindows) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sincronizacao automatica disponivel apenas no Windows.',
          ),
        ),
      );
      return;
    }

    try {
      final resultado = await Process.run('w32tm', [
        '/resync',
      ], runInShell: true);
      final codigo = resultado.exitCode;
      final saida = '${resultado.stdout}\n${resultado.stderr}'
          .trim()
          .toLowerCase();
      if (!mounted) return;
      if (codigo == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Relogio sincronizado com sucesso.')),
        );
      } else {
        final precisaPermissao =
            saida.contains('acesso negado') ||
            saida.contains('access is denied') ||
            saida.contains('0x80070005');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              precisaPermissao
                  ? 'Sem permissao para sincronizar automaticamente. Execute o app/terminal como administrador.'
                  : 'Nao foi possivel sincronizar automaticamente. Verifique internet e servico de horario do Windows.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Falha ao tentar sincronizar automaticamente. Use "Ajustar no sistema".',
          ),
        ),
      );
    } finally {
      await _carregarDiagnosticoHorario();
    }
  }

  Future<void> _escolherPastaPadraoPdf() async {
    final pasta = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta padrao para PDFs',
    );
    if (pasta == null || !mounted) return;
    setState(() {
      _pastaPadraoPdfController.text = pasta;
    });
  }

  Future<void> _escolherLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;
    final sourcePath = result.files.single.path!;
    final baseDir = Platform.isWindows
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    final logosDir = Directory(p.join(baseDir.path, 'logos'));
    if (!logosDir.existsSync()) {
      logosDir.createSync(recursive: true);
    }
    final ext = p.extension(sourcePath);
    final destPath = p.join(logosDir.path, 'logo_loja$ext');
    await File(sourcePath).copy(destPath);
    if (!mounted) return;
    setState(() {
      _logoPath = destPath;
    });
  }

  void _removerLogo() {
    setState(() {
      _logoPath = '';
    });
  }

  Future<void> _salvarConfig() async {
    if (!_prefsEmpresaAplicadas) {
      await _carregarConfig();
    }
    if (!mounted) return;
    setState(() => _salvando = true);
    try {
      final disco = await widget.appConfigRepository.carregarEmpresaConfig();
      final atualizado = disco.copyWith(
        nomeLoja: _nomeLojaController.text,
        telefone: _telefoneController.text,
        endereco: _enderecoController.text,
        pastaPadraoPdf: _pastaPadraoPdfController.text,
        impressoraPadrao: _impressoraPadrao,
        modeloPdf: _modeloPdf,
        rodapeNota: _rodapeNotaController.text,
        rodapeOrcamento: _rodapeOrcamentoController.text,
        logoPath: _logoPath,
        limiteDivergenciaCaixa:
            _parseMoeda(_limiteDivergenciaCaixaController.text) ?? 20,
        mostrarCampoDescontoCaixa: _mostrarCampoDescontoCaixa,
        exigirAutorizacaoSegundaViaCupom: _exigirAutorizacaoSegundaViaCupom,
        maxDescontoPercentualPdv:
            (_parseMoeda(_maxDescontoPercentualPdvController.text) ?? 15)
                .clamp(0, 100),
        margemMinimaPercentualPadrao:
            (_parseMoeda(_margemMinimaPadraoController.text) ?? 20)
                .clamp(0, 99),
        umCaixaAbertoPorLoja: _umCaixaAbertoPorLoja,
        permitirVendaSemEstoque: _permitirVendaSemEstoque,
        podFotoRetencaoDias: _podFotoRetencaoDias,
        pdvExigirVendedor: _pdvExigirVendedor,
        pdvBloqueioVendedor: _pdvBloqueioVendedor,
        pdvBloqueioVendedorAposOrcamento:
            _pdvBloqueioVendedor && _pdvBloqueioVendedorAposOrcamento,
        pdvBloqueioVendedorInatividadeMinutos: _pdvBloqueioVendedor &&
                _pdvBloqueioInatividadeAtivo
            ? (int.tryParse(
                    _pdvBloqueioInatividadeMinutosController.text.trim(),
                  ) ??
                  5)
                .clamp(1, 480)
            : 0,
        pdvBalcaoRapido: _pdvBalcaoRapido,
        pdvCheckoutDireto: _pdvCheckoutDireto,
        pdvPularDialogOrcamentoSalvo: _pdvPularDialogOrcamentoSalvo,
        pdvExigirClienteRetiradaFutura: _pdvExigirClienteRetiradaFutura,
        obraCalcTijoloProdutoId: _obraCalcTijoloProdutoId,
        obraCalcCimentoProdutoId: _obraCalcCimentoProdutoId,
        obraCalcAreiaProdutoId: _obraCalcAreiaProdutoId,
        obraCalcPisoProdutoId: _obraCalcPisoProdutoId,
        obraCalcPerdaPadraoPct: _obraCalcPerdaPadraoPct,
        obraCalcPerdaRebocoPct: _obraCalcPerdaRebocoPct,
        obraCalcPerdaPisoPct: _obraCalcPerdaPisoPct,
        obraCalcEspessuraRebocoMm: _obraCalcEspessuraRebocoMm,
        obraCalcEspessuraContrapisoMm: _obraCalcEspessuraContrapisoMm,
        obraCalcM2PorCaixaPiso: _obraCalcM2PorCaixaPiso,
        obraCalcGeminiParseAtivo: _obraCalcGeminiParseAtivo,
        obraCalcTemplatesJson: _obraCalcTemplatesJson,
        obraCalcBritaProdutoId: _obraCalcBritaProdutoId,
        obraCalcTelhaProdutoId: _obraCalcTelhaProdutoId,
        obraCalcFerroProdutoId: _obraCalcFerroProdutoId,
        obraCalcEspessuraLajeMm: _obraCalcEspessuraLajeMm,
        obraCalcPerdaLajePct: _obraCalcPerdaLajePct,
        obraCalcPerdaFundacaoPct: _obraCalcPerdaFundacaoPct,
        obraCalcPerdaTelhadoPct: _obraCalcPerdaTelhadoPct,
        obraCalcTelhasPorM2: _obraCalcTelhasPorM2,
        obraCalcInclinacaoTelhadoPct: _obraCalcInclinacaoTelhadoPct,
        obraCalcUsarSubstitutoEstoqueZero: _obraCalcUsarSubstitutoEstoqueZero,
        caixaFiscalNaoBloqueante: _caixaFiscalNaoBloqueante,
        caixaLimiteOrcamentosPendentes: int.tryParse(
              _caixaLimiteOrcamentosController.text.trim(),
            ) ??
            120,
      );

      final client = widget.lanApiClient;
      final terminalComApi = widget.terminalLeve &&
          client is LanApiClient &&
          client.configurado;

      if (terminalComApi) {
        // Terminal: servidor e fonte da verdade — POST primeiro, depois cache local.
        final resp = await client.salvarEmpresaConfigRemoto(
          SyncEntityCodecExtras.empresaConfigParaMap(atualizado),
        );
        final raw = resp['config'];
        final paraCache = raw is Map
            ? SyncEntityCodecExtras.empresaConfigDeMap(
                atualizado,
                Map<String, dynamic>.from(raw),
              )
            : atualizado;
        await widget.appConfigRepository.salvarEmpresaConfig(
          paraCache,
          propagarRede: false,
        );
      } else {
        await widget.appConfigRepository.salvarEmpresaConfig(atualizado);
        if (client is LanApiClient && client.configurado) {
          try {
            await client.salvarEmpresaConfigRemoto(
              SyncEntityCodecExtras.empresaConfigParaMap(atualizado),
            );
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Salvo localmente, mas falhou ao enviar ao PC1: $e',
                  ),
                ),
              );
            }
          }
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            terminalComApi
                ? 'Configuracoes salvas no servidor.'
                : 'Configuracoes da empresa salvas.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao salvar configuracoes: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _salvando = false);
      }
    }
  }

  Future<Uint8List> _gerarPdfTeste() async {
    final doc = pw.Document();
    final agora = DateTime.now();
    final dataFmt =
        '${agora.day.toString().padLeft(2, '0')}/${agora.month.toString().padLeft(2, '0')}/${agora.year} '
        '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}';
    final logoBytes = _logoPath.trim().isNotEmpty
        ? await File(_logoPath).readAsBytes().catchError((_) => Uint8List(0))
        : Uint8List(0);
    doc.addPage(
      pw.Page(
        pageFormat: _modeloPdf == 'a4'
            ? PdfPageFormat.a4
            : PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
        margin: const pw.EdgeInsets.all(10),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  _nomeLojaController.text.trim().isEmpty
                      ? 'LOJA DE MATERIAIS'
                      : _nomeLojaController.text.trim(),
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              if (logoBytes.isNotEmpty)
                pw.Center(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 6, bottom: 6),
                    child: pw.Image(pw.MemoryImage(logoBytes), height: 45),
                  ),
                ),
              if (_telefoneController.text.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text('Tel: ${_telefoneController.text.trim()}'),
                ),
              if (_enderecoController.text.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    _enderecoController.text.trim(),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              pw.SizedBox(height: 10),
              pw.Text(
                'TESTE DE IMPRESSAO',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text('Data/hora: $dataFmt'),
              pw.Text(
                'Modelo selecionado: ${_modeloPdf == 'a4' ? 'A4' : 'Cupom (80mm)'}',
              ),
              pw.Text(
                'Impressora padrao: ${_impressoraPadrao.isEmpty ? 'Nao definida' : _impressoraPadrao}',
              ),
              pw.Text(
                'Pasta padrao PDF: ${_pastaPadraoPdfController.text.trim().isEmpty ? 'Nao definida' : _pastaPadraoPdfController.text.trim()}',
              ),
              pw.SizedBox(height: 8),
              pw.Divider(),
              pw.Text(
                _rodapeNotaController.text.trim().isEmpty
                    ? 'Documento nao fiscal'
                    : _rodapeNotaController.text.trim(),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  Future<void> _imprimirTeste() async {
    try {
      final printer =
          await widget.printService.resolverImpressoraPorNome(_impressoraPadrao);
      if (printer == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Defina uma impressora padrao para o teste.'),
          ),
        );
        return;
      }
      final salva = await widget.appConfigRepository.carregarEmpresaConfig();
      final empresa = salva.copyWith(
        nomeLoja: _nomeLojaController.text.trim(),
        telefone: _telefoneController.text.trim(),
        endereco: _enderecoController.text.trim(),
        pastaPadraoPdf: _pastaPadraoPdfController.text.trim(),
        impressoraPadrao: _impressoraPadrao,
        modeloPdf: _modeloPdf,
        rodapeNota: _rodapeNotaController.text.trim(),
        rodapeOrcamento: _rodapeOrcamentoController.text.trim(),
        logoPath: _logoPath,
      );
      if (_modeloPdf == 'cupom') {
        final pdf = await CupomLayoutPreviewPdf.gerar(
          empresa: empresa,
          layout: empresa.layoutImpressao.orcamento,
          orcamento: true,
        );
        await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) async => pdf.bytes,
          name: 'Teste_orcamento_80mm',
          format: CupomPdfLayout.formatoImpressaoDireta(
            layout: pdf.layout,
            formatoPdf: pdf.pageFormat,
          ),
        );
      } else {
        final pdfBytes = await _gerarPdfTeste();
        await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) async => pdfBytes,
          name: 'Teste Impressao Sistema Vendas',
          format: PdfPageFormat.a4,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _modeloPdf == 'cupom'
                ? 'Teste de orcamento (80 mm) enviado. Confira subtotal e total.'
                : 'Teste de impressao enviado.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha no teste de impressao: $e')),
      );
    }
  }

  double? _parseMoeda(String texto) {
    final normalizado = texto.trim().replaceAll('.', '').replaceAll(',', '.');
    if (normalizado.isEmpty) return null;
    return double.tryParse(normalizado);
  }

  Widget _configTab(List<Widget> children, {ConfigSecaoInfo? secao}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (secao != null) ...[
            Text(
              secao.titulo,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              secao.descricao,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
          ],
          ...children,
        ],
      ),
    );
  }

  Widget _painelEmpresa() {
    return _configTab(
      [
        ConfigSectionCard(
          icon: Icons.storefront_outlined,
          title: 'Dados da empresa',
          subtitle: 'Nome da loja, telefone e endereco usados em vendas e documentos.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nomeLojaController,
                decoration: const InputDecoration(labelText: 'Nome da loja'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _telefoneController,
                decoration: const InputDecoration(labelText: 'Telefone da loja'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _enderecoController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Endereco da loja'),
              ),
              const SizedBox(height: 12),
              ConfigSaveButton(
                salvando: _salvando,
                onPressed: _salvarConfig,
                label: 'Salvar dados da empresa',
              ),
            ],
          ),
        ),
      ],
      secao: ConfigSecoes.todas[0],
    );
  }

  Widget _painelPdv() {
    return _configTab(
      [
        ConfigSectionCard(
          icon: Icons.point_of_sale_outlined,
          title: 'Regras comerciais do PDV',
          subtitle: 'Controle vendedor, descontos, estoque e fluxo de atendimento.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _maxDescontoPercentualPdvController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Desconto maximo no Ponto de Venda (% sobre subtotal)',
                  hintText: 'Ex.: 15',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Limite percentual sobre o subtotal dos produtos (nao inclui frete). '
                'No PDV o vendedor pode informar % ou valor em reais, desde que o '
                'desconto em reais nao ultrapasse esse percentual do subtotal. '
                'Use 0 para nao permitir desconto no PDV.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _permitirVendaSemEstoque,
                onChanged: (value) {
                  setState(() {
                    _permitirVendaSemEstoque = value;
                  });
                },
                title: const Text('Permitir venda sem estoque'),
                subtitle: const Text(
                  'Ativo por padrao. Vendas e finalizacao no caixa nunca bloqueiam '
                  'por falta de estoque (fisico pode ficar negativo).',
                ),
              ),
              const Divider(height: 28),
              Text('Vendedor', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _pdvExigirVendedor,
                onChanged: (value) {
                  setState(() => _pdvExigirVendedor = value);
                },
                title: const Text('Exigir vendedor no PDV'),
                subtitle: const Text(
                  'Se ninguem estiver selecionado no topo da tela, obriga informar '
                  'quem esta vendendo antes de enviar ao caixa.',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _pdvBloqueioVendedor,
                onChanged: (value) {
                  setState(() => _pdvBloqueioVendedor = value);
                },
                title: const Text('Bloqueio vendedor no PDV'),
                subtitle: const Text(
                  'Ao abrir o terminal, o vendedor informa a senha cadastrada ou '
                  'login do sistema vinculado; o PDV identifica quem vende.',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _pdvBloqueioVendedorAposOrcamento,
                onChanged: _pdvBloqueioVendedor
                    ? (value) {
                        setState(() => _pdvBloqueioVendedorAposOrcamento = value);
                      }
                    : null,
                title: const Text('Bloquear vendedor apos enviar orcamento'),
                subtitle: const Text(
                  'A cada orcamento enviado ao caixa, limpa o vendedor e exige senha '
                  'ou login antes da proxima venda.',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _pdvBloqueioInatividadeAtivo,
                onChanged: _pdvBloqueioVendedor
                    ? (value) {
                        setState(() => _pdvBloqueioInatividadeAtivo = value);
                      }
                    : null,
                title: const Text('Bloquear vendedor apos inatividade'),
                subtitle: const Text(
                  'Exige nova identificacao quando o terminal fica ocioso pelo '
                  'tempo configurado abaixo.',
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: TextField(
                  controller: _pdvBloqueioInatividadeMinutosController,
                  enabled: _pdvBloqueioVendedor && _pdvBloqueioInatividadeAtivo,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Minutos de inatividade',
                    helperText: 'Entre 1 e 480 minutos (8 horas).',
                    isDense: true,
                  ),
                ),
              ),
              const Divider(height: 28),
              Text('Entrega', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _pdvExigirClienteRetiradaFutura,
                onChanged: (value) {
                  setState(() => _pdvExigirClienteRetiradaFutura = value);
                },
                title: const Text('Exigir cliente na retirada futura'),
                subtitle: const Text(
                  'Quando ativo, qualquer item marcado como retirada futura no PDV '
                  'exige selecionar ou cadastrar o cliente antes de enviar ao caixa, '
                  'como no carreto.',
                ),
              ),
              const Divider(height: 28),
              Text('Atendimento', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _pdvBalcaoRapido,
                onChanged: (value) {
                  setState(() => _pdvBalcaoRapido = value);
                },
                title: const Text('PDV balcao rapido'),
                subtitle: const Text(
                  'Adiciona produto com qtd 1 sem dialog (retirada, sem carreto/misto).',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _pdvCheckoutDireto,
                onChanged: (value) {
                  setState(() => _pdvCheckoutDireto = value);
                },
                title: const Text('PDV checkout direto'),
                subtitle: const Text(
                  'Envia ao caixa sem abrir o dialog de fechamento quando os dados '
                  'ja estao no cabecalho.',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _pdvPularDialogOrcamentoSalvo,
                onChanged: (value) {
                  setState(() => _pdvPularDialogOrcamentoSalvo = value);
                },
                title: const Text('PDV: so snackbar apos salvar'),
                subtitle: const Text(
                  'Nao abre dialog de impressao/PDF apos salvar o orcamento.',
                ),
              ),
              const SizedBox(height: 12),
              ConfigSaveButton(
                salvando: _salvando,
                onPressed: _salvarConfig,
                label: 'Salvar regras do PDV',
              ),
            ],
          ),
        ),
        ConfigSectionCard(
          icon: Icons.construction_outlined,
          title: 'Calculadora de obra',
          subtitle: 'Parede, reboco, laje, fundacao, telhado e projeto no PDV (F12).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ObraCalculadoraConfigSection(
                produtoRepository: widget.produtoRepository,
                tijoloProdutoId: _obraCalcTijoloProdutoId,
                cimentoProdutoId: _obraCalcCimentoProdutoId,
                areiaProdutoId: _obraCalcAreiaProdutoId,
                pisoProdutoId: _obraCalcPisoProdutoId,
                britaProdutoId: _obraCalcBritaProdutoId,
                telhaProdutoId: _obraCalcTelhaProdutoId,
                ferroProdutoId: _obraCalcFerroProdutoId,
                perdaPadraoPct: _obraCalcPerdaPadraoPct,
                perdaRebocoPct: _obraCalcPerdaRebocoPct,
                perdaPisoPct: _obraCalcPerdaPisoPct,
                espessuraRebocoMm: _obraCalcEspessuraRebocoMm,
                espessuraContrapisoMm: _obraCalcEspessuraContrapisoMm,
                m2PorCaixaPiso: _obraCalcM2PorCaixaPiso,
                geminiParseAtivo: _obraCalcGeminiParseAtivo,
                templatesJson: _obraCalcTemplatesJson,
                usarSubstitutoEstoqueZero: _obraCalcUsarSubstitutoEstoqueZero,
                onChanged: ({
                  tijoloProdutoId,
                  cimentoProdutoId,
                  areiaProdutoId,
                  pisoProdutoId,
                  britaProdutoId,
                  telhaProdutoId,
                  ferroProdutoId,
                  perdaPadraoPct,
                  perdaRebocoPct,
                  perdaPisoPct,
                  espessuraRebocoMm,
                  espessuraContrapisoMm,
                  m2PorCaixaPiso,
                  geminiParseAtivo,
                  templatesJson,
                  usarSubstitutoEstoqueZero,
                }) {
                  setState(() {
                    if (tijoloProdutoId != null) {
                      _obraCalcTijoloProdutoId = tijoloProdutoId;
                    }
                    if (cimentoProdutoId != null) {
                      _obraCalcCimentoProdutoId = cimentoProdutoId;
                    }
                    if (areiaProdutoId != null) {
                      _obraCalcAreiaProdutoId = areiaProdutoId;
                    }
                    if (pisoProdutoId != null) {
                      _obraCalcPisoProdutoId = pisoProdutoId;
                    }
                    if (britaProdutoId != null) {
                      _obraCalcBritaProdutoId = britaProdutoId;
                    }
                    if (telhaProdutoId != null) {
                      _obraCalcTelhaProdutoId = telhaProdutoId;
                    }
                    if (ferroProdutoId != null) {
                      _obraCalcFerroProdutoId = ferroProdutoId;
                    }
                    if (perdaPadraoPct != null) {
                      _obraCalcPerdaPadraoPct = perdaPadraoPct;
                    }
                    if (perdaRebocoPct != null) {
                      _obraCalcPerdaRebocoPct = perdaRebocoPct;
                    }
                    if (perdaPisoPct != null) {
                      _obraCalcPerdaPisoPct = perdaPisoPct;
                    }
                    if (espessuraRebocoMm != null) {
                      _obraCalcEspessuraRebocoMm = espessuraRebocoMm;
                    }
                    if (espessuraContrapisoMm != null) {
                      _obraCalcEspessuraContrapisoMm = espessuraContrapisoMm;
                    }
                    if (m2PorCaixaPiso != null) {
                      _obraCalcM2PorCaixaPiso = m2PorCaixaPiso;
                    }
                    if (geminiParseAtivo != null) {
                      _obraCalcGeminiParseAtivo = geminiParseAtivo;
                    }
                    if (templatesJson != null) {
                      _obraCalcTemplatesJson = templatesJson;
                    }
                    if (usarSubstitutoEstoqueZero != null) {
                      _obraCalcUsarSubstitutoEstoqueZero =
                          usarSubstitutoEstoqueZero;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              ConfigSaveButton(
                salvando: _salvando,
                onPressed: _salvarConfig,
                label: 'Salvar calculadora de obra',
              ),
            ],
          ),
        ),
      ],
      secao: ConfigSecoes.todas[1],
    );
  }

  Widget _painelCaixa() {
    return _configTab(
      [
        ConfigSectionCard(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Operacao do caixa',
          subtitle: 'Fechamento, autorizacoes e fila do caixa.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _limiteDivergenciaCaixaController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Limite de divergencia sem supervisor (R\$)',
                  hintText: 'Ex.: 20,00',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Defina o limite de divergencia para exigir autorizacao de '
                'supervisor (admin/financeiro) no fechamento do caixa.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _mostrarCampoDescontoCaixa,
                onChanged: (value) {
                  setState(() {
                    _mostrarCampoDescontoCaixa = value;
                  });
                },
                title: const Text('Mostrar desconto rapido no Caixa'),
                subtitle: const Text(
                  'Desligue para ocultar o campo de desconto na tela do Caixa.',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _umCaixaAbertoPorLoja,
                onChanged: (value) {
                  setState(() => _umCaixaAbertoPorLoja = value);
                },
                title: const Text('Um unico caixa aberto por loja'),
                subtitle: const Text(
                  'Impede abrir caixa em outro terminal enquanto ja existir '
                  'sessao aberta na rede.',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _exigirAutorizacaoSegundaViaCupom,
                onChanged: (value) {
                  setState(() {
                    _exigirAutorizacaoSegundaViaCupom = value;
                  });
                },
                title: const Text('Exigir autorizacao para segunda via do cupom'),
                subtitle: const Text(
                  'Quando ativo, o operador precisa informar login e senha de um '
                  'usuario com permissao para imprimir a 2a via.',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _caixaFiscalNaoBloqueante,
                onChanged: (value) {
                  setState(() => _caixaFiscalNaoBloqueante = value);
                },
                title: const Text('Fiscal em segundo plano'),
                subtitle: const Text(
                  'Libera a fila para o proximo cliente enquanto NFC-e ou cupom '
                  'emite em paralelo.',
                ),
              ),
              TextField(
                controller: _caixaLimiteOrcamentosController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Limite de orcamentos pendentes no caixa',
                  hintText: '120',
                  helperText: 'Entre 20 e 500. Reduz memoria com historico grande.',
                ),
              ),
              const SizedBox(height: 12),
              ConfigSaveButton(
                salvando: _salvando,
                onPressed: _salvarConfig,
                label: 'Salvar configuracoes do caixa',
              ),
            ],
          ),
        ),
      ],
      secao: ConfigSecoes.todas[2],
    );
  }

  Widget _painelFiscal() {
    return _configTab(
      [
        ConfigSectionCard(
          icon: Icons.auto_awesome_outlined,
          title: 'IA — padronizar produtos (Gemini)',
          subtitle:
              'Usada no cadastro de produtos. Crie uma chave gratuita no Google AI Studio.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _geminiApiKeyController,
                obscureText: _geminiChaveOculta,
                decoration: InputDecoration(
                  labelText: 'Chave API Gemini (GEMINI_API_KEY)',
                  hintText: 'AIza...',
                  suffixIcon: IconButton(
                    tooltip: _geminiChaveOculta ? 'Mostrar chave' : 'Ocultar chave',
                    onPressed: () =>
                        setState(() => _geminiChaveOculta = !_geminiChaveOculta),
                    icon: Icon(
                      _geminiChaveOculta
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _abrirUrlGeminiAiStudio,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Criar chave no AI Studio'),
                  ),
                  FilledButton.icon(
                    onPressed: _salvarChaveGemini,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Salvar chave Gemini'),
                  ),
                ],
              ),
            ],
          ),
        ),
        ConfigSectionCard(
          icon: Icons.receipt_long_outlined,
          title: 'Fiscal — Focus NFe (NFC-e / NF-e)',
          subtitle:
              'Token salvo neste PC (fora do Git). Ambiente padrao: ${FiscalConfig.ambiente}.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _fiscalRegime == FiscalRegimePadrao.simplesNacional
                    ? FiscalRegimePadrao.simplesNacional
                    : FiscalRegimePadrao.regimeNormal,
                decoration: const InputDecoration(
                  labelText: 'Regime tributario da loja',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: FiscalRegimePadrao.simplesNacional,
                    child: Text('Simples Nacional'),
                  ),
                  DropdownMenuItem(
                    value: FiscalRegimePadrao.regimeNormal,
                    child: Text('Regime Normal'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _fiscalRegime = v);
                },
              ),
              const SizedBox(height: 6),
              Text(
                'Padrao na emissao e XML: ${FiscalRegimePadrao.resumoPadroesEmissao(_fiscalRegime)} '
                '(produtos em Automatico). Valide com o contador.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _fiscalAmbiente,
                decoration: const InputDecoration(
                  labelText: 'Ambiente SEFAZ',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'homologacao',
                    child: Text('Homologacao (testes)'),
                  ),
                  DropdownMenuItem(
                    value: 'producao',
                    child: Text('Producao (validade juridica)'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _fiscalAmbiente = v);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _fiscalTokenController,
                obscureText: _fiscalTokenOculto,
                decoration: InputDecoration(
                  labelText: 'Token API Focus',
                  hintText: 'Cole o token do painel Focus',
                  suffixIcon: IconButton(
                    tooltip: _fiscalTokenOculto ? 'Mostrar token' : 'Ocultar token',
                    onPressed: () =>
                        setState(() => _fiscalTokenOculto = !_fiscalTokenOculto),
                    icon: Icon(
                      _fiscalTokenOculto
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _fiscalCnpjController,
                decoration: const InputDecoration(
                  labelText: 'CNPJ emitente (14 digitos)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _fiscalIeController,
                decoration: const InputDecoration(
                  labelText: 'Inscricao estadual emitente',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              Text(
                'Envio do fechamento ao contador',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailContadorController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail do contador',
                  hintText: 'contador@escritorio.com.br',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _smtpHostController,
                decoration: const InputDecoration(
                  labelText: 'Servidor SMTP',
                  hintText: 'smtp.seudominio.com.br',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _smtpPortController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Porta',
                        hintText: '587',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('SSL direto'),
                      subtitle: const Text('Porta 465'),
                      value: _smtpSsl,
                      onChanged: (v) => setState(() => _smtpSsl = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _smtpUserController,
                decoration: const InputDecoration(
                  labelText: 'Usuario SMTP',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _smtpPasswordController,
                obscureText: _smtpPasswordOculta,
                decoration: InputDecoration(
                  labelText: 'Senha SMTP',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _smtpPasswordOculta
                        ? 'Mostrar senha'
                        : 'Ocultar senha',
                    onPressed: () => setState(
                      () => _smtpPasswordOculta = !_smtpPasswordOculta,
                    ),
                    icon: Icon(
                      _smtpPasswordOculta
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _smtpFromController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Remetente (From) — opcional',
                  hintText: 'Deixe vazio para usar o usuario SMTP',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _abrirPainelFocus,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Painel Focus NFe'),
                  ),
                  FilledButton.icon(
                    onPressed: _salvarConfigFiscal,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Salvar fiscal'),
                  ),
                ],
              ),
            ],
          ),
        ),
        ConfigSectionCard(
          icon: Icons.trending_up_outlined,
          title: 'Margem minima padrao',
          subtitle:
              'Alerta na conferencia de NF-e de entrada quando a margem ficar abaixo deste valor.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _margemMinimaPadraoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Margem minima padrao (%)',
                  hintText: 'Ex.: 20',
                ),
              ),
              const SizedBox(height: 12),
              ConfigSaveButton(
                salvando: _salvando,
                onPressed: _salvarConfig,
                label: 'Salvar margem minima',
              ),
            ],
          ),
        ),
      ],
      secao: ConfigSecoes.todas[3],
    );
  }

  Widget _painelImpressao() {
    return _configTab(
      [
        ConfigSectionCard(
          icon: Icons.print_outlined,
          title: 'Impressao e PDF',
          subtitle: 'Modelo de documento, rodapes, impressora e teste de impressao.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _pastaPadraoPdfController,
                decoration: InputDecoration(
                  labelText: 'Pasta padrao de PDF (opcional)',
                  suffixIcon: IconButton(
                    tooltip: 'Escolher pasta',
                    onPressed: _escolherPastaPadraoPdf,
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _modeloPdf,
                decoration: const InputDecoration(labelText: 'Modelo de PDF'),
                items: const [
                  DropdownMenuItem(value: 'cupom', child: Text('Cupom (80mm)')),
                  DropdownMenuItem(value: 'a4', child: Text('A4')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _modeloPdf = value);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Layout do cupom e orcamento'),
                subtitle: const Text(
                  'Divisorias, colunas, fontes e campos — com pre-visualizacao',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => LayoutImpressaoPage(
                        appConfigRepository: widget.appConfigRepository,
                        printService: widget.printService,
                        terminalLeve: widget.terminalLeve,
                        lanApiClient: widget.lanApiClient,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Impressora padrao'),
                subtitle: Text(
                  _impressoraPadrao.trim().isEmpty
                      ? 'Nao configurada — toque para abrir a tela dedicada'
                      : _impressoraPadrao,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ConfigImpressoraPage(
                        printService: widget.printService,
                        appConfigRepository: widget.appConfigRepository,
                      ),
                    ),
                  );
                  if (context.mounted) await _carregarConfig();
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _rodapeNotaController,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Rodape da nota/cupom nao fiscal',
                  alignLabelWithHint: true,
                  hintText: 'Use Enter para nova linha',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _rodapeOrcamentoController,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Rodape do orcamento',
                  alignLabelWithHint: true,
                  hintText: 'Use Enter para nova linha',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _escolherLogo,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(_logoPath.isEmpty ? 'Selecionar logo' : 'Trocar logo'),
                    ),
                  ),
                  if (_logoPath.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _removerLogo,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remover'),
                    ),
                  ],
                ],
              ),
              if (_logoPath.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Logo selecionada: ${p.basename(_logoPath)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              ConfigSaveButton(
                salvando: _salvando,
                onPressed: _salvarConfig,
                label: 'Salvar configuracoes de impressao/PDF',
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _imprimirTeste,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Teste de impressao'),
                ),
              ),
            ],
          ),
        ),
      ],
      secao: ConfigSecoes.todas[4],
    );
  }

  Widget _painelRede() {
    return _configTab(
      [
        if (widget.terminalLeve)
          ConfigSectionCard(
            icon: Icons.devices_outlined,
            title: 'Terminal',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .secondaryContainer
                    .withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Este PC é um Terminal — conecte ao servidor da loja.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        if (widget.terminalLeve) const SizedBox(height: 12),
        RedeSincronizacaoCard(
          configRepository: widget.appConfigRepository,
          lanSyncScheduler: widget.lanSyncScheduler,
          forcarModoCliente: widget.terminalLeve,
        ),
      ],
      secao: ConfigSecoes.todas[5],
    );
  }

  Widget _painelBackup() {
    if (widget.terminalLeve || widget.objectBox == null) {
      return _configTab(
        [
          BackupTerminalLeveSection(lanApiClient: widget.lanApiClient),
        ],
        secao: ConfigSecoes.todas[6],
      );
    }
    return _configTab(
      [
        BackupConfiguracaoSection(
          appConfigRepository: widget.appConfigRepository,
          objectBox: widget.objectBox!,
          produtoRepository: widget.produtoRepository,
          lanSyncScheduler: widget.lanSyncScheduler,
          nomeLoja: _nomeLojaController.text.trim().isEmpty
              ? 'LOJA DE MATERIAIS'
              : _nomeLojaController.text.trim(),
        ),
      ],
      secao: ConfigSecoes.todas[6],
    );
  }

  Future<void> _aplicarRetencaoPodAgora() async {
    final dias = PodFotoRetencaoOpcoes.normalizar(_podFotoRetencaoDias);
    if (dias <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Retencao desligada. Nada foi apagado.'),
        ),
      );
      return;
    }
    final n = await EntregaPodRetencaoService.aplicar(dias: dias);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n == 0
              ? 'Nenhuma foto antiga para remover (politica: ${PodFotoRetencaoOpcoes.rotulo(dias)}).'
              : '$n foto(s) antiga(s) removida(s).',
        ),
      ),
    );
  }

  Widget _painelSistema(
    String agoraFmt,
    String ultimaVendaFmt,
    String sinal,
    String h,
    String m,
  ) {
    return _configTab(
      [
        ConfigSectionCard(
          icon: Icons.schedule_outlined,
          title: 'Data e hora do sistema',
          subtitle: 'Diagnostico de consistencia para emissao e operacao de vendas.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Agora (sistema): $agoraFmt'),
              Text('Fuso horario: ${_agoraSistema.timeZoneName} (UTC$sinal$h:$m)'),
              Text('Ultima venda finalizada: $ultimaVendaFmt'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _horarioInconsistente
                      ? Colors.red.withValues(alpha: 0.08)
                      : Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _horarioInconsistente
                        ? Colors.red.withValues(alpha: 0.45)
                        : Colors.green.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(_diagnosticoHorario),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _carregarDiagnosticoHorario,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Atualizar diagnostico'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _abrirAjusteDataHoraSO,
                      icon: const Icon(Icons.schedule),
                      label: const Text('Ajustar no sistema'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _sincronizarHorarioWindows,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sincronizar horario agora (Windows)'),
                ),
              ),
            ],
          ),
        ),
        ConfigSectionCard(
          icon: Icons.photo_outlined,
          title: 'Fotos de prova de entrega',
          subtitle:
              'O celular ja envia JPEG reduzido. Aqui o PC apaga fotos antigas.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                key: ValueKey('pod_retencao_$_podFotoRetencaoDias'),
                initialValue: _podFotoRetencaoDias,
                decoration: const InputDecoration(
                  labelText: 'Retencao automatica das fotos',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final d in PodFotoRetencaoOpcoes.valoresPermitidos)
                    DropdownMenuItem(
                      value: d,
                      child: Text(PodFotoRetencaoOpcoes.rotulo(d)),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _podFotoRetencaoDias = v);
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Padrao: 6 meses. Quem recebeu continua no pedido; so o arquivo '
                'JPEG e apagado. Fotos novas saem com no maximo 960 px.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              ConfigSaveButton(
                salvando: _salvando,
                onPressed: _salvarConfig,
                label: 'Salvar retencao de fotos',
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _aplicarRetencaoPodAgora,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Limpar fotos antigas agora'),
              ),
            ],
          ),
        ),
      ],
      secao: ConfigSecoes.todas[7],
    );
  }

  Widget _corpoSecaoConfig(
    String agoraFmt,
    String ultimaVendaFmt,
    String sinal,
    String h,
    String m,
  ) {
    final secaoInfo = ConfigSecoes.todas[_indiceSecaoConfig.clamp(
      0,
      ConfigSecoes.todas.length - 1,
    )];
    switch (secaoInfo.id) {
      case 'empresa':
        return _painelEmpresa();
      case 'pdv':
        return _painelPdv();
      case 'caixa':
        return _painelCaixa();
      case 'fiscal':
        return _painelFiscal();
      case 'impressao':
        return _painelImpressao();
      case 'rede':
        return _painelRede();
      case 'backup':
        return _painelBackup();
      case 'sistema':
        return _painelSistema(agoraFmt, ultimaVendaFmt, sinal, h, m);
      default:
        return _painelEmpresa();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dtFmt = DateFormat('dd/MM/yyyy HH:mm:ss');
    final agoraFmt = dtFmt.format(_agoraSistema);
    final ultimaVendaFmt = _ultimaVendaFinalizada == null
        ? 'Nenhuma venda finalizada ainda'
        : dtFmt.format(_ultimaVendaFinalizada!.toLocal());
    final offset = _agoraSistema.timeZoneOffset;
    final sinal = offset.isNegative ? '-' : '+';
    final h = offset.inHours.abs().toString().padLeft(2, '0');
    final m = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');

    return ConfigPageShell(
      secaoAtual: _indiceSecaoConfig,
      onSecaoChanged: (novoIndice) {
        setState(() {
          _indiceSecaoConfig = novoIndice.clamp(0, ConfigSecoes.todas.length - 1);
        });
      },
      child: _corpoSecaoConfig(agoraFmt, ultimaVendaFmt, sinal, h, m),
    );
  }
}
