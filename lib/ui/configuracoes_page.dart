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
import '../services/configuracoes_service.dart';
import '../data/api/lan_api_client.dart';
import '../data/sync/sync_entity_codec_extras.dart';
import 'configuracoes/obra_calculadora_config_section.dart';
import 'configuracoes/backup_configuracao_section.dart';
import 'configuracoes/backup_terminal_leve_section.dart';
import 'configuracoes/config_escopo_banner.dart';
import 'configuracoes/config_page_shell.dart';
import 'configuracoes/config_secao.dart';
import 'configuracoes/config_section_card.dart';
import 'configuracoes/config_controles.dart';
import 'configuracoes/config_barra_salvar.dart';
import '../services/impressoes_service.dart';
import '../data/objectbox.dart';
import '../data/sync/lan_sync_scheduler.dart';
import '../config/fiscal_config.dart';
import '../domain/pod_foto_retencao.dart';
import '../services/entrega_pod_retencao_service.dart';
import '../domain/fiscal/fiscal_regime_padrao.dart';
import '../services/gemini_config.dart';
import '../services/print_service.dart';
import 'widgets/rede_sincronizacao_card.dart';
import '../services/cupom_layout_preview_pdf.dart';
import '../services/cupom_pdf_layout.dart';
import 'config_impressora_page.dart';
import 'layout_impressao_page.dart';

/// Blocos salvos de forma independente: cada botao grava so os campos do seu
/// cartao, preservando o que outro terminal ja tinha gravado nas outras secoes.
enum _ConfigGrupo {
  empresa('Dados da empresa'),
  pdv('Regras do PDV'),
  obra('Calculadora de obra'),
  caixa('Configurações do caixa'),
  margem('Margem mínima'),
  documentos('Documentos da loja'),
  terminal('Configurações deste terminal'),
  podFoto('Retenção de fotos');

  const _ConfigGrupo(this.rotulo);

  final String rotulo;
}

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({
    super.key,
    required this.vendaRepository,
    required this.configuracoesService,
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
  final ConfiguracoesService configuracoesService;
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
  bool _pdvAutoImpressaoAoFinalizarVenda = false;
  String _logoPath = '';
  bool _salvando = false;
  bool _prefsEmpresaAplicadas = false;
  DateTime _agoraSistema = DateTime.now();
  DateTime? _ultimaVendaFinalizada;
  bool _horarioInconsistente = false;
  String _diagnosticoHorario = '';
  /// Fonte unica dos valores de fabrica: vale so ate `_carregarConfig` chegar.
  static const _padrao = EmpresaConfig();

  /// Sugestao ao ligar o bloqueio por inatividade (o EmpresaConfig guarda 0 =
  /// desligado, entao o valor inicial do campo nao sai de la).
  static const _minutosInatividadePadrao = 5;

  bool _permitirVendaSemEstoque = _padrao.permitirVendaSemEstoque;
  int _podFotoRetencaoDias = _padrao.podFotoRetencaoDias;
  bool _pdvExigirVendedor = _padrao.pdvExigirVendedor;
  bool _pdvBloqueioVendedor = _padrao.pdvBloqueioVendedor;
  bool _pdvBloqueioVendedorAposOrcamento =
      _padrao.pdvBloqueioVendedorAposOrcamento;
  bool _pdvBloqueioInatividadeAtivo = false;
  final _pdvBloqueioInatividadeMinutosController =
      TextEditingController(text: '$_minutosInatividadePadrao');
  bool _pdvBalcaoRapido = _padrao.pdvBalcaoRapido;
  bool _pdvCheckoutDireto = _padrao.pdvCheckoutDireto;
  bool _pdvPularDialogOrcamentoSalvo = _padrao.pdvPularDialogOrcamentoSalvo;
  bool _pdvExigirClienteRetiradaFutura = _padrao.pdvExigirClienteRetiradaFutura;
  int _obraCalcTijoloProdutoId = _padrao.obraCalcTijoloProdutoId;
  int _obraCalcCimentoProdutoId = _padrao.obraCalcCimentoProdutoId;
  int _obraCalcAreiaProdutoId = _padrao.obraCalcAreiaProdutoId;
  int _obraCalcPisoProdutoId = _padrao.obraCalcPisoProdutoId;
  double _obraCalcPerdaPadraoPct = _padrao.obraCalcPerdaPadraoPct;
  double _obraCalcPerdaRebocoPct = _padrao.obraCalcPerdaRebocoPct;
  double _obraCalcPerdaPisoPct = _padrao.obraCalcPerdaPisoPct;
  double _obraCalcEspessuraRebocoMm = _padrao.obraCalcEspessuraRebocoMm;
  double _obraCalcEspessuraContrapisoMm = _padrao.obraCalcEspessuraContrapisoMm;
  double _obraCalcM2PorCaixaPiso = _padrao.obraCalcM2PorCaixaPiso;
  bool _obraCalcGeminiParseAtivo = _padrao.obraCalcGeminiParseAtivo;
  String _obraCalcTemplatesJson = _padrao.obraCalcTemplatesJson;
  int _obraCalcBritaProdutoId = _padrao.obraCalcBritaProdutoId;
  int _obraCalcTelhaProdutoId = _padrao.obraCalcTelhaProdutoId;
  int _obraCalcFerroProdutoId = _padrao.obraCalcFerroProdutoId;
  double _obraCalcEspessuraLajeMm = _padrao.obraCalcEspessuraLajeMm;
  double _obraCalcPerdaLajePct = _padrao.obraCalcPerdaLajePct;
  double _obraCalcPerdaFundacaoPct = _padrao.obraCalcPerdaFundacaoPct;
  double _obraCalcPerdaTelhadoPct = _padrao.obraCalcPerdaTelhadoPct;
  double _obraCalcTelhasPorM2 = _padrao.obraCalcTelhasPorM2;
  double _obraCalcInclinacaoTelhadoPct = _padrao.obraCalcInclinacaoTelhadoPct;
  bool _obraCalcUsarSubstitutoEstoqueZero =
      _padrao.obraCalcUsarSubstitutoEstoqueZero;
  bool _caixaFiscalNaoBloqueante = _padrao.caixaFiscalNaoBloqueante;
  final _caixaLimiteOrcamentosController = TextEditingController(
    text: '${_padrao.caixaLimiteOrcamentosPendentes}',
  );
  final _caixaSangriaLimiteController = TextEditingController(
    text: _padrao.caixaSangriaLimiteSemSupervisor
        .toStringAsFixed(2)
        .replaceAll('.', ','),
  );
  bool _caixaGavetaSemVendaExigeSenha =
      _padrao.caixaGavetaSemVendaExigeSenha;
  bool _mostrarCampoDescontoCaixa = _padrao.mostrarCampoDescontoCaixa;
  bool _exibirBuscaRapidaOrcamentoCaixa =
      _padrao.exibirBuscaRapidaOrcamentoCaixa;
  bool _exigirAutorizacaoSegundaViaCupom =
      _padrao.exigirAutorizacaoSegundaViaCupom;
  bool _umCaixaAbertoPorLoja = _padrao.umCaixaAbertoPorLoja;
  int _indiceSecaoConfig = 0;

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );
  static final NumberFormat _percentual = NumberFormat('#0.##', 'pt_BR');

  /// Blocos mexidos e ainda nao gravados, para a barra do rodape e o aviso ao sair.
  final Set<_ConfigGrupo> _gruposSujos = {};

  /// Ligado enquanto `_carregarConfig` reescreve os campos, para que os listeners
  /// dos controllers nao confundam carga com edicao do usuario.
  bool _aplicandoConfigCarregada = false;

  void _marcarSujo(_ConfigGrupo grupo) {
    if (_aplicandoConfigCarregada || !_prefsEmpresaAplicadas) return;
    _gruposSujos.add(grupo);
  }

  /// Listener dos campos de texto do PDV: marca sujo e redesenha a simulacao.
  void _aoEditarCampoPdv() {
    if (_aplicandoConfigCarregada || !_prefsEmpresaAplicadas) return;
    setState(() => _gruposSujos.add(_ConfigGrupo.pdv));
  }

  void _aoEditarCampoCaixa() {
    if (_aplicandoConfigCarregada || !_prefsEmpresaAplicadas) return;
    setState(() => _gruposSujos.add(_ConfigGrupo.caixa));
  }

  void _tocarCaixa(VoidCallback alterar) {
    setState(() {
      alterar();
      _marcarSujo(_ConfigGrupo.caixa);
    });
  }

  @override
  void initState() {
    super.initState();
    final secao = widget.secaoInicialId?.trim();
    if (secao != null && secao.isNotEmpty) {
      _indiceSecaoConfig = ConfigSecoes.indiceDeId(secao);
    }
    _maxDescontoPercentualPdvController.addListener(_aoEditarCampoPdv);
    _pdvBloqueioInatividadeMinutosController.addListener(_aoEditarCampoPdv);
    _limiteDivergenciaCaixaController.addListener(_aoEditarCampoCaixa);
    _caixaLimiteOrcamentosController.addListener(_aoEditarCampoCaixa);
    _caixaSangriaLimiteController.addListener(_aoEditarCampoCaixa);
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
    _caixaSangriaLimiteController.dispose();
    _pdvBloqueioInatividadeMinutosController.dispose();
    super.dispose();
  }

  Future<void> _carregarConfigFiscal() async {
    final client = widget.lanApiClient;
    if (client is LanApiClient && client.configurado) {
      widget.configuracoesService.vincularLanApiClient(client);
    }
    final cfg = await widget.configuracoesService.carregarFiscalGlobal();
    if (widget.terminalLeve && mounted) {
      setState(() {
        _fiscalTokenController.text =
            cfg.tokenConfiguradoNoServidor ? '********' : '';
        _fiscalCnpjController.text = cfg.cnpjEmitente;
        _fiscalIeController.text = cfg.inscricaoEstadualEmitente;
        _fiscalAmbiente = cfg.homologacao ? 'homologacao' : 'producao';
        _fiscalRegime = FiscalRegimePadrao.regimeEfetivo(cfg);
      });
      return;
    }
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
            'Token Focus e dados fiscais sensíveis só podem ser alterados no PC servidor.',
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
    await widget.configuracoesService.salvarFiscalGlobal(
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
        const SnackBar(content: Text('Não foi possível abrir o painel Focus.')),
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
        SnackBar(content: Text('Não foi possível abrir: $url')),
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
            'Chave Gemini inválida. Cole a chave completa do Google AI Studio '
            '(geralmente começa com AIza).',
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
              : 'Chave Gemini salva. Padronização com IA liberada no cadastro de produtos.',
        ),
      ),
    );
  }

  Future<EmpresaConfig> _carregarConfigDoDiscoOuServidor() async {
    if (!widget.terminalLeve) {
      return widget.configuracoesService.carregarEfetiva();
    }
    final client = widget.lanApiClient;
    if (client is LanApiClient && client.configurado) {
      widget.configuracoesService.vincularLanApiClient(client);
    }
    try {
      return await widget.configuracoesService.carregarGlobalDoServidor();
    } catch (e) {
      final local = await widget.configuracoesService.carregarEfetiva();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível ler configurações do servidor: $e. '
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
    _aplicandoConfigCarregada = true;
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
      _pdvAutoImpressaoAoFinalizarVenda =
          config.pdvAutoImpressaoAoFinalizarVenda;
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
              : '$_minutosInatividadePadrao';
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
      _caixaSangriaLimiteController.text = config
          .caixaSangriaLimiteSemSupervisor
          .toStringAsFixed(2)
          .replaceAll('.', ',');
      _caixaGavetaSemVendaExigeSenha = config.caixaGavetaSemVendaExigeSenha;
      _mostrarCampoDescontoCaixa = config.mostrarCampoDescontoCaixa;
      _exibirBuscaRapidaOrcamentoCaixa =
          config.exibirBuscaRapidaOrcamentoCaixa;
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
      // Recarregar é a origem da verdade: nada fica pendente depois disso.
      _gruposSujos.clear();
    });
    _aplicandoConfigCarregada = false;
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
          ? 'Horário do sistema está atrasado em relação à última venda finalizada. '
                'Corrija data/hora no Windows antes de emitir novas notas.'
          : 'Horário do sistema consistente para operação de vendas e impressão.';
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
          'Abra as configurações de data/hora do sistema operacional para ajustar.',
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
            'Sincronização automática disponível apenas no Windows.',
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
          const SnackBar(content: Text('Relógio sincronizado com sucesso.')),
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
                  ? 'Sem permissão para sincronizar automaticamente. Execute o app/terminal como administrador.'
                  : 'Não foi possível sincronizar automaticamente. Verifique internet e serviço de horário do Windows.',
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
      dialogTitle: 'Escolha a pasta padrão para PDFs',
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

  /// Aplica ao que esta no disco somente os campos do grupo salvo, para que dois
  /// terminais editando secoes diferentes nao sobrescrevam um ao outro.
  EmpresaConfig _aplicarGrupo(EmpresaConfig disco, _ConfigGrupo grupo) {
    switch (grupo) {
      case _ConfigGrupo.empresa:
        return disco.copyWith(
          nomeLoja: _nomeLojaController.text,
          telefone: _telefoneController.text,
          endereco: _enderecoController.text,
        );
      case _ConfigGrupo.pdv:
        return disco.copyWith(
          maxDescontoPercentualPdv:
              (_parseMoeda(_maxDescontoPercentualPdvController.text) ??
                      _padrao.maxDescontoPercentualPdv)
                  .clamp(0, 100),
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
          pdvExigirVendedor: _pdvExigirVendedor,
          pdvBloqueioVendedor: _pdvBloqueioVendedor,
          pdvBloqueioVendedorAposOrcamento:
              _pdvBloqueioVendedor && _pdvBloqueioVendedorAposOrcamento,
          pdvBloqueioVendedorInatividadeMinutos: _pdvBloqueioVendedor &&
                  _pdvBloqueioInatividadeAtivo
              ? (int.tryParse(
                      _pdvBloqueioInatividadeMinutosController.text.trim(),
                    ) ??
                    _minutosInatividadePadrao)
                  .clamp(1, 480)
              : 0,
          pdvBalcaoRapido: _pdvBalcaoRapido,
          pdvCheckoutDireto: _pdvCheckoutDireto,
          pdvPularDialogOrcamentoSalvo: _pdvPularDialogOrcamentoSalvo,
          pdvExigirClienteRetiradaFutura: _pdvExigirClienteRetiradaFutura,
        );
      case _ConfigGrupo.obra:
        return disco.copyWith(
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
        );
      case _ConfigGrupo.caixa:
        return disco.copyWith(
          limiteDivergenciaCaixa:
              (_parseMoeda(_limiteDivergenciaCaixaController.text) ??
                      _padrao.limiteDivergenciaCaixa)
                  .clamp(0, 999999),
          mostrarCampoDescontoCaixa: _mostrarCampoDescontoCaixa,
          exibirBuscaRapidaOrcamentoCaixa: _exibirBuscaRapidaOrcamentoCaixa,
          exigirAutorizacaoSegundaViaCupom: _exigirAutorizacaoSegundaViaCupom,
          umCaixaAbertoPorLoja: _umCaixaAbertoPorLoja,
          caixaFiscalNaoBloqueante: _caixaFiscalNaoBloqueante,
          caixaLimiteOrcamentosPendentes: (int.tryParse(
                    _caixaLimiteOrcamentosController.text.trim(),
                  ) ??
                  _padrao.caixaLimiteOrcamentosPendentes)
              .clamp(20, 500),
          caixaSangriaLimiteSemSupervisor:
              (_parseMoeda(_caixaSangriaLimiteController.text) ??
                      _padrao.caixaSangriaLimiteSemSupervisor)
                  .clamp(0, 999999),
          caixaGavetaSemVendaExigeSenha: _caixaGavetaSemVendaExigeSenha,
        );
      case _ConfigGrupo.margem:
        return disco.copyWith(
          margemMinimaPercentualPadrao:
              (_parseMoeda(_margemMinimaPadraoController.text) ??
                      _padrao.margemMinimaPercentualPadrao)
                  .clamp(0, 99),
        );
      case _ConfigGrupo.documentos:
        return disco.copyWith(
          modeloPdf: _modeloPdf,
          rodapeNota: _rodapeNotaController.text,
          rodapeOrcamento: _rodapeOrcamentoController.text,
        );
      case _ConfigGrupo.terminal:
        return disco.copyWith(
          pastaPadraoPdf: _pastaPadraoPdfController.text,
          impressoraPadrao: _impressoraPadrao,
          pdvAutoImpressaoAoFinalizarVenda: _pdvAutoImpressaoAoFinalizarVenda,
          logoPath: _logoPath,
        );
      case _ConfigGrupo.podFoto:
        return disco.copyWith(podFotoRetencaoDias: _podFotoRetencaoDias);
    }
  }

  String? get _erroMinutosInatividadePdv {
    if (!_pdvBloqueioVendedor || !_pdvBloqueioInatividadeAtivo) return null;
    final minutos = int.tryParse(
      _pdvBloqueioInatividadeMinutosController.text.trim(),
    );
    if (minutos == null || minutos < 1 || minutos > 480) {
      return 'Informe os minutos de inatividade entre 1 e 480.';
    }
    return null;
  }

  String? _erroDoGrupo(_ConfigGrupo grupo) {
    if (grupo == _ConfigGrupo.pdv) {
      return _erroDescontoMaximoPdv ?? _erroMinutosInatividadePdv;
    }
    if (grupo == _ConfigGrupo.caixa) {
      return _erroLimiteDivergenciaCaixa ??
          _erroLimiteOrcamentosCaixa ??
          _erroSangriaLimiteCaixa;
    }
    return null;
  }

  Future<String?> _dialogoPendencias() {
    final n = _gruposSujos.length;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alterações não salvas'),
        content: Text(
          n == 1
              ? 'Há 1 bloco com alterações. O que deseja fazer?'
              : 'Há $n blocos com alterações. O que deseja fazer?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'continuar'),
            child: const Text('Continuar editando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'descartar'),
            child: const Text('Descartar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'salvar'),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _descartarAlteracoes() => _carregarConfig();

  Future<bool> _salvarGrupos(
    Iterable<_ConfigGrupo> grupos, {
    bool anunciar = true,
  }) async {
    final alvos = grupos.where(_gruposSujos.contains).toList();
    if (alvos.isEmpty) return true;
    for (final grupo in alvos) {
      final erro = _erroDoGrupo(grupo);
      if (erro != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(erro)),
          );
        }
        return false;
      }
    }
    for (final grupo in alvos) {
      final ok = await _salvarConfig(
        grupo,
        anunciar: anunciar && grupo == alvos.last,
      );
      if (!ok) return false;
    }
    return true;
  }

  Future<void> _trocarSecao(int novoIndice) async {
    final indice = novoIndice.clamp(0, ConfigSecoes.todas.length - 1);
    if (indice == _indiceSecaoConfig) return;
    if (_gruposSujos.isNotEmpty) {
      final acao = await _dialogoPendencias();
      if (!mounted) return;
      if (acao == null || acao == 'continuar') return;
      if (acao == 'salvar') {
        final ok = await _salvarGrupos(_gruposSujos.toList());
        if (!ok || !mounted || _gruposSujos.isNotEmpty) return;
      } else if (acao == 'descartar') {
        await _descartarAlteracoes();
        if (!mounted) return;
      } else {
        return;
      }
    }
    if (!mounted) return;
    setState(() => _indiceSecaoConfig = indice);
  }

  Future<void> _aoTentarSair(bool didPop) async {
    if (didPop) return;
    final acao = await _dialogoPendencias();
    if (!mounted) return;
    if (acao == 'descartar') {
      await _descartarAlteracoes();
      if (mounted) Navigator.of(context).pop();
    } else if (acao == 'salvar') {
      final ok = await _salvarGrupos(_gruposSujos.toList());
      if (ok && mounted && _gruposSujos.isEmpty) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<bool> _salvarConfig(_ConfigGrupo grupo, {bool anunciar = true}) async {
    if (!_prefsEmpresaAplicadas) {
      await _carregarConfig();
    }
    if (!mounted) return false;
    final erro = _erroDoGrupo(grupo);
    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erro)),
      );
      return false;
    }
    setState(() => _salvando = true);
    try {
      final disco = await widget.configuracoesService.carregarEfetiva();
      final atualizado = _aplicarGrupo(disco, grupo);

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
        await widget.configuracoesService.salvarEfetiva(
          paraCache,
          propagarRede: false,
        );
      } else {
        await widget.configuracoesService.salvarEfetiva(atualizado);
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
      if (!mounted) return false;
      setState(() => _gruposSujos.remove(grupo));
      if (anunciar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              terminalComApi
                  ? '${grupo.rotulo}: salvo no servidor.'
                  : '${grupo.rotulo}: salvo.',
            ),
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao salvar ${grupo.rotulo}: $e')),
        );
      }
      return false;
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
                'TESTE DE IMPRESSÃO',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text('Data/hora: $dataFmt'),
              pw.Text(
                'Modelo selecionado: ${_modeloPdf == 'a4' ? 'A4' : 'Cupom (80mm)'}',
              ),
              pw.Text(
                'Impressora padrão: ${_impressoraPadrao.isEmpty ? 'Nao definida' : _impressoraPadrao}',
              ),
              pw.Text(
                'Pasta padrão PDF: ${_pastaPadraoPdfController.text.trim().isEmpty ? 'Nao definida' : _pastaPadraoPdfController.text.trim()}',
              ),
              pw.SizedBox(height: 8),
              pw.Divider(),
              pw.Text(
                _rodapeNotaController.text.trim().isEmpty
                    ? 'Documento não fiscal'
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
            content: Text('Defina uma impressora padrão para o teste.'),
          ),
        );
        return;
      }
      final salva = await widget.configuracoesService.carregarEfetiva();
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
          layout: ImpressoesService.layoutOrcamentoEfetivo(empresa),
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
          name: 'Teste Impressão Sistema Vendas',
          format: PdfPageFormat.a4,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _modeloPdf == 'cupom'
                ? 'Teste de orçamento (80 mm) enviado. Confira subtotal e total.'
                : 'Teste de impressão enviado.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha no teste de impressão: $e')),
      );
    }
  }

  double? _parseMoeda(String texto) {
    final normalizado = texto.trim().replaceAll('.', '').replaceAll(',', '.');
    if (normalizado.isEmpty) return null;
    return double.tryParse(normalizado);
  }

  Widget _configTab(
    List<Widget> children, {
    ConfigSecaoInfo? secao,
    List<_ConfigGrupo> gruposDaSecao = const [],
  }) {
    final pendencias = gruposDaSecao.where(_gruposSujos.contains).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (secao != null) ...[
                  Text(
                    secao.titulo,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
          ),
        ),
        if (gruposDaSecao.isNotEmpty)
          ConfigBarraSalvar(
            pendencias: pendencias,
            salvando: _salvando,
            onSalvar: () {
              _salvarGrupos(gruposDaSecao);
            },
            onDescartar: _descartarAlteracoes,
          ),
      ],
    );
  }

  Widget _painelEmpresa() {
    return _configTab(
      [
        ConfigEscopoBanner(
          tipo: ConfigEscopoTipo.lojaServidor,
          terminalLeve: widget.terminalLeve,
        ),
        ConfigSectionCard(
          icon: Icons.storefront_outlined,
          title: 'Dados da empresa',
          subtitle: 'Nome da loja, telefone e endereço usados em vendas e documentos.',
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
                decoration: const InputDecoration(labelText: 'Endereço da loja'),
              ),
              const SizedBox(height: 12),
              ConfigSaveButton(
                salvando: _salvando,
                onPressed: () => _salvarConfig(_ConfigGrupo.empresa),
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
        ConfigEscopoBanner(
          tipo: ConfigEscopoTipo.lojaServidor,
          terminalLeve: widget.terminalLeve,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final coluna1 = [
              _cardPdvDescontos(),
              _cardPdvVendedor(),
              _cardPdvAtendimento(),
            ];
            final coluna2 = [
              _cardPdvEstoqueEntrega(),
              _cardPdvObra(),
            ];
            if (constraints.maxWidth < ConfigSecoes.breakpointDuasColunas) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...coluna1, ...coluna2],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: coluna1,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: coluna2,
                  ),
                ),
              ],
            );
          },
        ),
      ],
      secao: ConfigSecoes.todas[1],
      gruposDaSecao: const [_ConfigGrupo.pdv, _ConfigGrupo.obra],
    );
  }

  /// Limite de desconto digitado, ou nulo quando o texto nao e um numero valido.
  double? get _descontoMaximoPdvDigitado =>
      _parseMoeda(_maxDescontoPercentualPdvController.text);

  String? get _erroDescontoMaximoPdv {
    if (_maxDescontoPercentualPdvController.text.trim().isEmpty) {
      return 'Informe o limite. Use 0 para não permitir desconto no PDV.';
    }
    final valor = _descontoMaximoPdvDigitado;
    if (valor == null) return 'Valor inválido. Use números, ex.: 15 ou 12,5.';
    if (valor < 0 || valor > 100) return 'O limite deve ficar entre 0 e 100%.';
    return null;
  }

  Widget _cardPdvDescontos() {
    final valor = _descontoMaximoPdvDigitado;
    final erro = _erroDescontoMaximoPdv;
    const vendaExemplo = 1000.0;

    return ConfigSectionCard(
      icon: Icons.percent_outlined,
      title: 'Descontos e preço',
      subtitle: 'Quanto o vendedor abre sozinho antes de pedir autorização.',
      destacado: true,
      resumo: ConfigResumoChips(
        itens: [
          if (erro != null)
            const ConfigResumoItem.alerta('Limite inválido')
          else if (valor == 0)
            const ConfigResumoItem.inativo('Desconto bloqueado no PDV')
          else
            ConfigResumoItem.ativo(
              'Até ${_percentual.format(valor)}% do subtotal',
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _maxDescontoPercentualPdvController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Desconto máximo no PDV',
              suffixText: '%',
              hintText: 'Ex.: 15',
              errorText: erro,
              helperText: erro == null
                  ? 'Percentual sobre o subtotal dos produtos, sem o frete. '
                      'No PDV vale % ou valor em reais, limitado a esse teto.'
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          ConfigLinhaSimulacao(
            texto: erro != null
                ? 'Corrija o limite para ver a simulação.'
                : valor == 0
                    ? 'Com 0%, todo desconto no PDV passa por autorização de quem '
                        'tem permissão para alterar preço.'
                    : 'Numa venda de ${_moeda.format(vendaExemplo)}, o vendedor '
                        'libera até ${_moeda.format(vendaExemplo * valor! / 100)} '
                        'sem pedir autorização.',
            alerta: erro != null,
          ),
        ],
      ),
    );
  }

  Widget _cardPdvVendedor() {
    final minutos = int.tryParse(
      _pdvBloqueioInatividadeMinutosController.text.trim(),
    );
    const motivoDependente = 'Disponível com "Bloqueio vendedor no PDV" ativo.';

    return ConfigSectionCard(
      icon: Icons.badge_outlined,
      title: 'Vendedor e identificação',
      subtitle: 'Quem responde pela venda e como o terminal confirma isso.',
      resumo: ConfigResumoChips(
        itens: [
          _pdvExigirVendedor
              ? const ConfigResumoItem.ativo('Vendedor obrigatório')
              : const ConfigResumoItem.inativo('Vendedor opcional'),
          if (_pdvBloqueioVendedor)
            const ConfigResumoItem.ativo('Identificação por senha')
          else
            const ConfigResumoItem.inativo('Sem bloqueio de terminal'),
          if (_pdvBloqueioVendedor && _pdvBloqueioVendedorAposOrcamento)
            const ConfigResumoItem.ativo('Relogin por orçamento'),
          if (_pdvBloqueioVendedor &&
              _pdvBloqueioInatividadeAtivo &&
              minutos != null)
            ConfigResumoItem.ativo('Ocioso: $minutos min'),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConfigSwitchTile(
            titulo: 'Exigir vendedor no PDV',
            resumo: 'Obriga informar quem vendeu antes de enviar ao caixa.',
            detalhe:
                'Se ninguém estiver selecionado no topo da tela do PDV, o envio '
                'ao caixa é recusado até que um vendedor seja escolhido.',
            valor: _pdvExigirVendedor,
            onChanged: (v) => setState(() {
              _pdvExigirVendedor = v;
              _marcarSujo(_ConfigGrupo.pdv);
            }),
          ),
          ConfigSwitchTile(
            titulo: 'Bloqueio vendedor no PDV',
            resumo: 'Terminal pede senha ou login para liberar a venda.',
            detalhe:
                'Ao abrir o terminal, o vendedor informa a senha cadastrada ou o '
                'login do sistema vinculado; o PDV passa a identificar quem vende '
                'em cada orçamento.',
            valor: _pdvBloqueioVendedor,
            onChanged: (v) => setState(() {
              _pdvBloqueioVendedor = v;
              _marcarSujo(_ConfigGrupo.pdv);
            }),
          ),
          ConfigSubGrupo(
            visivel: _pdvBloqueioVendedor,
            children: [
              ConfigSwitchTile(
                titulo: 'Bloquear após enviar orçamento',
                resumo: 'Cada orçamento enviado limpa o vendedor.',
                detalhe:
                    'A cada orçamento enviado ao caixa, o PDV limpa o vendedor e '
                    'exige senha ou login antes da próxima venda. Indicado em '
                    'balcão compartilhado por vários vendedores.',
                valor: _pdvBloqueioVendedorAposOrcamento,
                motivoDesabilitado: motivoDependente,
                onChanged: _pdvBloqueioVendedor
                    ? (v) => setState(() {
                          _pdvBloqueioVendedorAposOrcamento = v;
                          _marcarSujo(_ConfigGrupo.pdv);
                        })
                    : null,
              ),
              ConfigSwitchTile(
                titulo: 'Bloquear após inatividade',
                resumo: 'Terminal ocioso volta a pedir identificação.',
                detalhe:
                    'Exige nova identificação quando o terminal fica ocioso pelo '
                    'tempo configurado abaixo.',
                valor: _pdvBloqueioInatividadeAtivo,
                motivoDesabilitado: motivoDependente,
                onChanged: _pdvBloqueioVendedor
                    ? (v) => setState(() {
                          _pdvBloqueioInatividadeAtivo = v;
                          _marcarSujo(_ConfigGrupo.pdv);
                        })
                    : null,
              ),
              ConfigSubGrupo(
                visivel: _pdvBloqueioVendedor && _pdvBloqueioInatividadeAtivo,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: TextField(
                      controller: _pdvBloqueioInatividadeMinutosController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Minutos de inatividade',
                        isDense: true,
                        errorText: _erroMinutosInatividadePdv,
                        helperText: 'Entre 1 e 480 minutos (8 horas).',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardPdvEstoqueEntrega() {
    return ConfigSectionCard(
      icon: Icons.inventory_2_outlined,
      title: 'Estoque e entrega',
      subtitle: 'O que o balcão pode vender e quando o cliente é obrigatório.',
      resumo: ConfigResumoChips(
        itens: [
          _permitirVendaSemEstoque
              ? const ConfigResumoItem.ativo('Venda sem estoque liberada')
              : const ConfigResumoItem.alerta('Venda sem estoque bloqueada'),
          _pdvExigirClienteRetiradaFutura
              ? const ConfigResumoItem.ativo('Retirada futura com cliente')
              : const ConfigResumoItem.alerta('Retirada futura sem cliente'),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConfigSwitchTile(
            titulo: 'Permitir venda sem estoque',
            resumo: 'Falta de estoque nunca trava a venda nem o caixa.',
            detalhe:
                'Ativo por padrão. Vendas e finalização no caixa nunca bloqueiam '
                'por falta de estoque, e o saldo físico pode ficar negativo até o '
                'acerto da entrada.',
            valor: _permitirVendaSemEstoque,
            onChanged: (v) => setState(() {
              _permitirVendaSemEstoque = v;
              _marcarSujo(_ConfigGrupo.pdv);
            }),
          ),
          const ConfigGrupoTitulo('Retirada futura'),
          ConfigSwitchTile(
            titulo: 'Exigir cliente na retirada futura',
            resumo: 'Item para retirar depois precisa de cliente, como o carreto.',
            detalhe:
                'Ativo por padrão. Qualquer item marcado como retirada futura '
                'exige selecionar ou cadastrar o cliente antes de enviar ao '
                'caixa. Desligue só se a loja controla a reserva fora do '
                'sistema: sem cliente não há como saber quem retira a mercadoria.',
            valor: _pdvExigirClienteRetiradaFutura,
            onChanged: (v) => setState(() {
              _pdvExigirClienteRetiradaFutura = v;
              _marcarSujo(_ConfigGrupo.pdv);
            }),
          ),
        ],
      ),
    );
  }

  Widget _cardPdvAtendimento() {
    final atalhos = [
      _pdvBalcaoRapido,
      _pdvCheckoutDireto,
      _pdvPularDialogOrcamentoSalvo,
    ].where((e) => e).length;

    return ConfigSectionCard(
      icon: Icons.bolt_outlined,
      title: 'Velocidade de atendimento',
      subtitle: 'Quantos diálogos o vendedor atravessa em cada venda.',
      resumo: ConfigResumoChips(
        itens: [
          atalhos == 3
              ? const ConfigResumoItem.ativo('Fluxo mais rápido')
              : atalhos == 0
                  ? const ConfigResumoItem.inativo('Fluxo completo com diálogos')
                  : ConfigResumoItem.ativo('$atalhos de 3 atalhos ativos'),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConfigSwitchTile(
            titulo: 'Balcão rápido',
            resumo: 'Produto entra com quantidade 1, sem abrir diálogo.',
            detalhe:
                'Adiciona o produto direto com quantidade 1 e entrega por '
                'retirada. Itens com carreto ou entrega mista continuam abrindo '
                'o diálogo.',
            valor: _pdvBalcaoRapido,
            onChanged: (v) => setState(() {
              _pdvBalcaoRapido = v;
              _marcarSujo(_ConfigGrupo.pdv);
            }),
          ),
          ConfigSwitchTile(
            titulo: 'Checkout direto',
            resumo: 'Envia ao caixa sem o diálogo de fechamento.',
            detalhe:
                'Quando vendedor, cliente e entrega já estão no cabeçalho, o '
                'envio ao caixa acontece sem abrir o diálogo de fechamento.',
            valor: _pdvCheckoutDireto,
            onChanged: (v) => setState(() {
              _pdvCheckoutDireto = v;
              _marcarSujo(_ConfigGrupo.pdv);
            }),
          ),
          ConfigSwitchTile(
            titulo: 'Só avisar após salvar',
            resumo: 'Mostra o número do orçamento sem abrir impressão.',
            detalhe:
                'Depois de salvar o orçamento, exibe apenas o aviso com o número '
                'em vez de abrir o diálogo de impressão ou PDF.',
            valor: _pdvPularDialogOrcamentoSalvo,
            onChanged: (v) => setState(() {
              _pdvPularDialogOrcamentoSalvo = v;
              _marcarSujo(_ConfigGrupo.pdv);
            }),
          ),
        ],
      ),
    );
  }

  Widget _cardPdvObra() {
    final produtosPadrao = [
      _obraCalcTijoloProdutoId,
      _obraCalcCimentoProdutoId,
      _obraCalcAreiaProdutoId,
      _obraCalcPisoProdutoId,
      _obraCalcBritaProdutoId,
      _obraCalcTelhaProdutoId,
      _obraCalcFerroProdutoId,
    ].where((id) => id > 0).length;

    return ConfigSectionCard(
      icon: Icons.construction_outlined,
      title: 'Calculadora de obra',
      subtitle: 'Parede, reboco, laje, fundação, telhado e projeto no PDV (F12).',
      resumo: ConfigResumoChips(
        itens: [
          produtosPadrao == 0
              ? const ConfigResumoItem.inativo('Produtos padrão não definidos')
              : ConfigResumoItem.ativo(
                  '$produtosPadrao produtos padrão definidos',
                ),
        ],
      ),
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
                  _obraCalcUsarSubstitutoEstoqueZero = usarSubstitutoEstoqueZero;
                }
                if (!_aplicandoConfigCarregada && _prefsEmpresaAplicadas) {
                  _gruposSujos.add(_ConfigGrupo.obra);
                }
              });
            },
          ),
        ],
      ),
    );
  }

  double? get _limiteDivergenciaCaixaDigitado =>
      _parseMoeda(_limiteDivergenciaCaixaController.text);

  String? get _erroLimiteDivergenciaCaixa {
    if (_limiteDivergenciaCaixaController.text.trim().isEmpty) {
      return 'Informe o limite. Use 0 para exigir supervisor em qualquer diferença.';
    }
    final valor = _limiteDivergenciaCaixaDigitado;
    if (valor == null) {
      return 'Valor inválido. Use números, ex.: 20 ou 20,00.';
    }
    if (valor < 0) return 'O limite não pode ser negativo.';
    return null;
  }

  String? get _erroLimiteOrcamentosCaixa {
    final texto = _caixaLimiteOrcamentosController.text.trim();
    if (texto.isEmpty) {
      return 'Informe o limite de orçamentos na fila (20 a 500).';
    }
    final n = int.tryParse(texto);
    if (n == null) return 'Use um número inteiro, ex.: 120.';
    if (n < 20 || n > 500) return 'O limite deve ficar entre 20 e 500.';
    return null;
  }

  double? get _sangriaLimiteDigitado =>
      _parseMoeda(_caixaSangriaLimiteController.text);

  String? get _erroSangriaLimiteCaixa {
    if (_caixaSangriaLimiteController.text.trim().isEmpty) {
      return 'Informe o teto. Use 0 para exigir supervisor em qualquer sangria.';
    }
    final valor = _sangriaLimiteDigitado;
    if (valor == null) {
      return 'Valor inválido. Use números, ex.: 200 ou 200,00.';
    }
    if (valor < 0) return 'O teto não pode ser negativo.';
    return null;
  }

  Widget _layoutDuasColunas({
    required List<Widget> coluna1,
    required List<Widget> coluna2,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < ConfigSecoes.breakpointDuasColunas) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [...coluna1, ...coluna2],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: coluna1,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: coluna2,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _painelCaixa() {
    return _configTab(
      [
        ConfigEscopoBanner(
          tipo: ConfigEscopoTipo.lojaServidor,
          terminalLeve: widget.terminalLeve,
        ),
        _layoutDuasColunas(
          coluna1: [
            _cardCaixaFechamento(),
            _cardCaixaDesconto(),
            _cardCaixaSeguranca(),
          ],
          coluna2: [
            _cardCaixaFila(),
            _cardCaixaFiscal(),
            _cardCaixaSangriaGaveta(),
          ],
        ),
      ],
      secao: ConfigSecoes.todas[2],
      gruposDaSecao: const [_ConfigGrupo.caixa],
    );
  }

  Widget _cardCaixaFechamento() {
    final valor = _limiteDivergenciaCaixaDigitado;
    final erro = _erroLimiteDivergenciaCaixa;

    return ConfigSectionCard(
      icon: Icons.balance_outlined,
      title: 'Fechamento',
      subtitle: 'Quando o operador precisa de supervisor para fechar o caixa.',
      destacado: true,
      resumo: ConfigResumoChips(
        itens: [
          if (erro != null)
            const ConfigResumoItem.alerta('Limite inválido')
          else if (valor == 0)
            const ConfigResumoItem.alerta('Qualquer diferença pede supervisor')
          else
            ConfigResumoItem.ativo(
              'Até ${_moeda.format(valor)} sem supervisor',
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _limiteDivergenciaCaixaController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Limite de divergência sem supervisor',
              prefixText: r'R$ ',
              hintText: 'Ex.: 20,00',
              errorText: erro,
              helperText: erro == null
                  ? 'Diferença entre o dinheiro contado e o esperado no fechamento.'
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          ConfigLinhaSimulacao(
            texto: erro != null
                ? 'Corrija o limite para ver o efeito no fechamento.'
                : valor == 0
                    ? 'Com R\$ 0,00 qualquer sobra ou falta exige login de '
                        'administrador ou financeiro.'
                    : 'No fechamento, diferença até ${_moeda.format(valor!)} '
                        'o operador confirma sozinho. Acima disso pede autorização.',
            alerta: erro != null || valor == 0,
          ),
        ],
      ),
    );
  }

  Widget _cardCaixaDesconto() {
    final tetoPdv = _descontoMaximoPdvDigitado;
    final descontoNaTela = _mostrarCampoDescontoCaixa;
    final tetoBloqueia = tetoPdv != null && tetoPdv <= 0.004;

    return ConfigSectionCard(
      icon: Icons.percent_outlined,
      title: 'Desconto no caixa',
      subtitle: 'Campo F6 na conferência. O teto percentual é o do PDV.',
      resumo: ConfigResumoChips(
        itens: [
          if (!descontoNaTela)
            const ConfigResumoItem.inativo('Campo de desconto oculto')
          else if (tetoBloqueia)
            const ConfigResumoItem.alerta('Teto do PDV em 0% — F6 some')
          else
            const ConfigResumoItem.ativo('Desconto visível no caixa'),
          if (descontoNaTela && tetoPdv != null && !tetoBloqueia)
            ConfigResumoItem.ativo(
              'Teto: ${_percentual.format(tetoPdv)}% (PDV)',
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConfigSwitchTile(
            titulo: 'Mostrar desconto rápido no caixa',
            resumo: 'Exibe o campo e o atalho F6 na conferência.',
            detalhe:
                'Desligue para ocultar o desconto na tela do Caixa. Mesmo ligado, '
                'o F6 some se o desconto máximo do PDV estiver em 0%. O teto é o '
                'mesmo percentual configurado em Ponto de venda.',
            valor: _mostrarCampoDescontoCaixa,
            onChanged: (v) => _tocarCaixa(() => _mostrarCampoDescontoCaixa = v),
          ),
          if (tetoBloqueia) ...[
            const SizedBox(height: 8),
            const ConfigLinhaSimulacao(
              texto:
                  'O desconto máximo do PDV está em 0%. O caixa não oferece F6 '
                  'enquanto esse teto não for maior que zero.',
              alerta: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardCaixaSeguranca() {
    return ConfigSectionCard(
      icon: Icons.verified_user_outlined,
      title: 'Segurança da sessão',
      subtitle: 'Quantos caixas abrem na loja e quem imprime 2ª via.',
      resumo: ConfigResumoChips(
        itens: [
          _umCaixaAbertoPorLoja
              ? const ConfigResumoItem.ativo('Um caixa aberto por loja')
              : const ConfigResumoItem.alerta('Vários caixas simultâneos'),
          _exigirAutorizacaoSegundaViaCupom
              ? const ConfigResumoItem.ativo('2ª via com autorização')
              : const ConfigResumoItem.inativo('2ª via livre'),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConfigSwitchTile(
            titulo: 'Um único caixa aberto por loja',
            resumo: 'Outro terminal não abre sessão enquanto esta estiver aberta.',
            detalhe:
                'Impede abrir caixa em outro computador da rede se já existir '
                'sessão aberta. O segundo terminal pode aderir à sessão, mas não '
                'abrir um caixa paralelo.',
            valor: _umCaixaAbertoPorLoja,
            onChanged: (v) => _tocarCaixa(() => _umCaixaAbertoPorLoja = v),
          ),
          ConfigSwitchTile(
            titulo: 'Exigir autorização para 2ª via do cupom',
            resumo: 'Login e senha de quem pode autorizar a reimpressão.',
            detalhe:
                'Quando ativo, F2 e a 2ª via na listagem de vendas pedem login e '
                'senha de um usuário com permissão para autorizar segunda via.',
            valor: _exigirAutorizacaoSegundaViaCupom,
            onChanged: (v) =>
                _tocarCaixa(() => _exigirAutorizacaoSegundaViaCupom = v),
          ),
        ],
      ),
    );
  }

  Widget _cardCaixaFila() {
    final n = int.tryParse(_caixaLimiteOrcamentosController.text.trim());
    final erro = _erroLimiteOrcamentosCaixa;

    return ConfigSectionCard(
      icon: Icons.queue_outlined,
      title: 'Fila de orçamentos',
      subtitle: 'Como o caixa acha o pedido e quantos carrega na memória.',
      resumo: ConfigResumoChips(
        itens: [
          _exibirBuscaRapidaOrcamentoCaixa
              ? const ConfigResumoItem.ativo('Busca rápida visível')
              : const ConfigResumoItem.inativo('Só atalho F1'),
          if (erro != null)
            const ConfigResumoItem.alerta('Limite da fila inválido')
          else if (n != null)
            ConfigResumoItem.ativo('Até $n orçamentos na fila'),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConfigSwitchTile(
            titulo: 'Exibir busca rápida de orçamento',
            resumo: 'Campo de número acima dos atalhos. F1 continua valendo.',
            detalhe:
                'Mostra o campo de entrada direta por número de orçamento na '
                'etapa da fila. Desligado, o operador usa só o atalho F1.',
            valor: _exibirBuscaRapidaOrcamentoCaixa,
            onChanged: (v) =>
                _tocarCaixa(() => _exibirBuscaRapidaOrcamentoCaixa = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _caixaLimiteOrcamentosController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Orçamentos pendentes na memória',
              hintText: '120',
              errorText: erro,
              helperText: erro == null
                  ? 'Entre 20 e 500. Valor menor reduz memória com fila grande.'
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardCaixaFiscal() {
    return ConfigSectionCard(
      icon: Icons.receipt_long_outlined,
      title: 'Emissão fiscal',
      subtitle: 'Se a NFC-e segura a fila ou corre em paralelo.',
      resumo: ConfigResumoChips(
        itens: [
          _caixaFiscalNaoBloqueante
              ? const ConfigResumoItem.ativo('Fila libera na hora')
              : const ConfigResumoItem.alerta('Fila espera a nota'),
        ],
      ),
      child: ConfigSwitchTile(
        titulo: 'Fiscal em segundo plano',
        resumo: 'Próximo cliente entra enquanto a nota emite.',
        detalhe:
            'Ativo: depois de finalizar o pagamento o caixa volta para a fila e '
            'a NFC-e ou o cupom segue em paralelo. Desligado: o operador fica na '
            'tela fiscal até concluir a emissão.',
        valor: _caixaFiscalNaoBloqueante,
        onChanged: (v) => _tocarCaixa(() => _caixaFiscalNaoBloqueante = v),
      ),
    );
  }

  Widget _cardCaixaSangriaGaveta() {
    final teto = _sangriaLimiteDigitado;
    final erro = _erroSangriaLimiteCaixa;

    return ConfigSectionCard(
      icon: Icons.payments_outlined,
      title: 'Sangria e gaveta',
      subtitle: 'Quanto sai da gaveta sem senha e quem abre ela à toa.',
      destacado: true,
      resumo: ConfigResumoChips(
        itens: [
          if (erro != null)
            const ConfigResumoItem.alerta('Teto de sangria inválido')
          else if (teto == 0)
            const ConfigResumoItem.alerta('Toda sangria pede supervisor')
          else
            ConfigResumoItem.ativo(
              'Sangria até ${_moeda.format(teto)} sem senha',
            ),
          _caixaGavetaSemVendaExigeSenha
              ? const ConfigResumoItem.ativo('Gaveta sem venda com senha')
              : const ConfigResumoItem.alerta('Gaveta abre sem senha'),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _caixaSangriaLimiteController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Sangria máxima sem supervisor',
              prefixText: r'R$ ',
              hintText: 'Ex.: 200,00',
              errorText: erro,
              helperText: erro == null
                  ? '0 = qualquer sangria pede login. Nunca sangra acima do '
                      'dinheiro esperado na gaveta.'
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          ConfigLinhaSimulacao(
            texto: erro != null
                ? 'Corrija o teto para ver o efeito na sangria.'
                : teto == 0
                    ? 'Toda retirada de dinheiro pede administrador ou financeiro. '
                        'Mesmo autorizado, o valor não pode passar do saldo da gaveta.'
                    : 'Até ${_moeda.format(teto!)} o operador sangra sozinho. '
                        'Acima disso pede senha e motivo. Nunca acima do saldo.',
            alerta: erro != null || teto == 0,
          ),
          const SizedBox(height: 8),
          ConfigSwitchTile(
            titulo: 'Abrir gaveta sem venda exige senha',
            resumo: 'O botão Testar gaveta pede supervisor. Pagamento continua livre.',
            detalhe:
                'Ativo: abrir a gaveta pelo caixa, sem uma venda na hora, exige '
                'login de administrador ou financeiro. A abertura automática após '
                'receber dinheiro na venda não pede senha.',
            valor: _caixaGavetaSemVendaExigeSenha,
            onChanged: (v) =>
                _tocarCaixa(() => _caixaGavetaSemVendaExigeSenha = v),
          ),
        ],
      ),
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
              'Token salvo neste PC (fora do Git). Ambiente padrão: ${FiscalConfig.ambiente}.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _fiscalRegime == FiscalRegimePadrao.simplesNacional
                    ? FiscalRegimePadrao.simplesNacional
                    : FiscalRegimePadrao.regimeNormal,
                decoration: const InputDecoration(
                  labelText: 'Regime tributário da loja',
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
                'Padrão na emissão e XML: ${FiscalRegimePadrao.resumoPadroesEmissao(_fiscalRegime)} '
                '(produtos em Automático). Valide com o contador.',
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
                    child: Text('Homologação (testes)'),
                  ),
                  DropdownMenuItem(
                    value: 'producao',
                    child: Text('Produção (validade jurídica)'),
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
                  labelText: 'CNPJ emitente (14 dígitos)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _fiscalIeController,
                decoration: const InputDecoration(
                  labelText: 'Inscrição estadual emitente',
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
                  labelText: 'Usuário SMTP',
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
                  hintText: 'Deixe vazio para usar o usuário SMTP',
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
          title: 'Margem mínima padrão',
          subtitle:
              'Alerta na conferência de NF-e de entrada quando a margem ficar abaixo deste valor.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _margemMinimaPadraoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Margem mínima padrão (%)',
                  hintText: 'Ex.: 20',
                ),
              ),
              const SizedBox(height: 12),
              ConfigSaveButton(
                salvando: _salvando,
                onPressed: () => _salvarConfig(_ConfigGrupo.margem),
                label: 'Salvar margem mínima',
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
        const ConfigEscopoBanner(
          tipo: ConfigEscopoTipo.lojaServidor,
        ),
        ConfigSectionCard(
          icon: Icons.receipt_long_outlined,
          title: 'Documentos da loja',
          subtitle:
              'Modelo, textos de rodapé e estilo do cupom (sincronizados na rede).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _modeloPdf,
                decoration: const InputDecoration(labelText: 'Modelo de PDF'),
                items: const [
                  DropdownMenuItem(value: 'cupom', child: Text('Cupom térmico')),
                  DropdownMenuItem(value: 'a4', child: Text('A4')),
                ],
                onChanged: widget.terminalLeve
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _modeloPdf = value);
                      },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Layout do cupom e orçamento'),
                subtitle: Text(
                  widget.terminalLeve
                      ? 'Visualize o padrão da loja; edição no PC servidor.'
                      : 'Divisórias, colunas, fontes e campos — com pre-visualização',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => LayoutImpressaoPage(
                        configuracoesService: widget.configuracoesService,
                        printService: widget.printService,
                        terminalLeve: widget.terminalLeve,
                        lanApiClient: widget.lanApiClient,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _rodapeNotaController,
                readOnly: widget.terminalLeve,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Rodapé da nota/cupom não fiscal',
                  alignLabelWithHint: true,
                  hintText: 'Use Enter para nova linha',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _rodapeOrcamentoController,
                readOnly: widget.terminalLeve,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Rodapé do orçamento',
                  alignLabelWithHint: true,
                  hintText: 'Use Enter para nova linha',
                ),
              ),
              if (!widget.terminalLeve) ...[
                const SizedBox(height: 12),
                ConfigSaveButton(
                  salvando: _salvando,
                  onPressed: () => _salvarConfig(_ConfigGrupo.documentos),
                  label: 'Salvar documentos da loja',
                ),
              ],
            ],
          ),
        ),
        ConfigEscopoBanner(
          tipo: ConfigEscopoTipo.terminalLocal,
          terminalLeve: widget.terminalLeve,
        ),
        ConfigSectionCard(
          icon: Icons.print_outlined,
          title: 'Impressora deste terminal',
          subtitle:
              'Hardware local: fila Windows, bobina 58/80 mm, margens e auto-impressão no PDV.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _pastaPadraoPdfController,
                decoration: InputDecoration(
                  labelText: 'Pasta padrão de PDF neste PC (opcional)',
                  suffixIcon: IconButton(
                    tooltip: 'Escolher pasta',
                    onPressed: _escolherPastaPadraoPdf,
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Impressora, bobina e ESC/POS'),
                subtitle: Text(
                  _impressoraPadrao.trim().isEmpty
                      ? 'Não configurada — abra a tela dedicada'
                      : _impressoraPadrao,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ConfigImpressoraPage(
                        printService: widget.printService,
                        configuracoesService: widget.configuracoesService,
                      ),
                    ),
                  );
                  if (context.mounted) await _carregarConfig();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-impressão ao finalizar venda (PDV)'),
                subtitle: const Text(
                  'Imprime o cupom automaticamente neste terminal, sem diálogo.',
                ),
                value: _pdvAutoImpressaoAoFinalizarVenda,
                onChanged: (v) =>
                    setState(() => _pdvAutoImpressaoAoFinalizarVenda = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _escolherLogo,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                        _logoPath.isEmpty ? 'Logo neste PC' : 'Trocar logo local',
                      ),
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
                  'Logo neste terminal: ${p.basename(_logoPath)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              ConfigSaveButton(
                salvando: _salvando,
                onPressed: () => _salvarConfig(_ConfigGrupo.terminal),
                label: 'Salvar configurações deste terminal',
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _imprimirTeste,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Teste de impressão (bobina local)'),
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
          configuracoesService: widget.configuracoesService,
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
          configuracoesService: widget.configuracoesService,
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
          content: Text('Retenção desligada. Nada foi apagado.'),
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
              ? 'Nenhuma foto antiga para remover (política: ${PodFotoRetencaoOpcoes.rotulo(dias)}).'
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
          subtitle: 'Diagnóstico de consistência para emissão e operação de vendas.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Agora (sistema): $agoraFmt'),
              Text('Fuso horário: ${_agoraSistema.timeZoneName} (UTC$sinal$h:$m)'),
              Text('Última venda finalizada: $ultimaVendaFmt'),
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
                      label: const Text('Atualizar diagnóstico'),
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
                  label: const Text('Sincronizar horário agora (Windows)'),
                ),
              ),
            ],
          ),
        ),
        ConfigSectionCard(
          icon: Icons.photo_outlined,
          title: 'Fotos de prova de entrega',
          subtitle:
              'O celular já envia JPEG reduzido. Aqui o PC apaga fotos antigas.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                key: ValueKey('pod_retencao_$_podFotoRetencaoDias'),
                initialValue: _podFotoRetencaoDias,
                decoration: const InputDecoration(
                  labelText: 'Retenção automática das fotos',
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
                'Padrão: 6 meses. Quem recebeu continua no pedido; só o arquivo '
                'JPEG e apagado. Fotos novas saem com no máximo 960 px.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              ConfigSaveButton(
                salvando: _salvando,
                onPressed: () => _salvarConfig(_ConfigGrupo.podFoto),
                label: 'Salvar retenção de fotos',
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
    final secaoId =
        ConfigSecoes.todas[_indiceSecaoConfig.clamp(0, ConfigSecoes.todas.length - 1)]
            .id;
    final conteudoAmplo = secaoId == 'pdv' || secaoId == 'caixa';

    return PopScope(
      canPop: _gruposSujos.isEmpty,
      onPopInvokedWithResult: (didPop, _) => _aoTentarSair(didPop),
      child: ConfigPageShell(
        secaoAtual: _indiceSecaoConfig,
        conteudoAmplo: conteudoAmplo,
        onSecaoChanged: (novoIndice) {
          _trocarSecao(novoIndice);
        },
        child: _corpoSecaoConfig(agoraFmt, ultimaVendaFmt, sinal, h, m),
      ),
    );
  }
}
