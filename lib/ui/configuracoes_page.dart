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
import '../data/produto_repository.dart';
import 'configuracoes/obra_calculadora_config_section.dart';
import 'configuracoes/backup_configuracao_section.dart';
import 'configuracoes/config_page_shell.dart';
import 'configuracoes/config_secao.dart';
import 'configuracoes/config_section_card.dart';
import '../data/mensageria_repository.dart';
import '../data/objectbox.dart';
import '../data/sync/lan_sync_scheduler.dart';
import '../data/venda_repository.dart';
import '../config/fiscal_config.dart';
import '../domain/fiscal/fiscal_regime_padrao.dart';
import '../services/fiscal_config_store.dart';
import '../services/gemini_config.dart';
import '../services/print_service.dart';
import 'widgets/rede_sincronizacao_card.dart';
import '../model/mensagem_log.dart';
import '../model/mensagem_template.dart';
import '../services/cupom_layout_preview_pdf.dart';
import '../services/cupom_pdf_layout.dart';
import 'config_impressora_page.dart';
import 'layout_impressao_page.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({
    super.key,
    required this.vendaRepository,
    required this.objectBox,
    required this.appConfigRepository,
    required this.printService,
    required this.produtoRepository,
    this.lanSyncScheduler,
    this.secaoInicialId,
  });

  final VendaRepository vendaRepository;
  final ObjectBox objectBox;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;
  final ProdutoRepository produtoRepository;
  final LanSyncScheduler? lanSyncScheduler;
  final String? secaoInicialId;

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
  final _whatsappDonoController = TextEditingController();
  final _alertasIntervaloController = TextEditingController(text: '120');
  final _whatsApiVersionController = TextEditingController();
  final _whatsPhoneIdController = TextEditingController();
  final _whatsTokenController = TextEditingController();
  final _mensageriaBackendUrlController = TextEditingController();
  final _geminiApiKeyController = TextEditingController();
  final _fiscalTokenController = TextEditingController();
  final _fiscalCnpjController = TextEditingController();
  final _fiscalIeController = TextEditingController();
  final _mensageriaRepository = MensageriaRepository();
  bool _geminiChaveOculta = true;
  bool _fiscalTokenOculto = true;
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
  bool _alertasProativosWhatsappAtivos = false;
  List<MensagemTemplate> _templatesMensagem = [];
  int _filaPendente = 0;
  int _logsTotais = 0;
  int _logsEnviados = 0;
  int _logsEntregues = 0;
  int _logsLidos = 0;
  int _logsFalhas = 0;
  String _filtroStatusLog = 'todos';
  String _filtroCanalLog = 'todos';
  final _filtroTextoLogController = TextEditingController();
  final _webhookPayloadController = TextEditingController();
  List<MensagemLog> _logsFiltrados = [];
  int _indiceSecaoConfig = 0;

  String _rotuloStatusMensagem(String status) {
    switch (status) {
      case 'aceito_api':
        return 'Aceito pela API';
      case 'enviado':
        return 'Enviado';
      case 'entregue':
        return 'Entregue';
      case 'lido':
        return 'Lido';
      case 'falhou':
        return 'Falhou';
      default:
        return status;
    }
  }

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
    _carregarMensageria();
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
    _whatsappDonoController.dispose();
    _alertasIntervaloController.dispose();
    _whatsApiVersionController.dispose();
    _whatsPhoneIdController.dispose();
    _whatsTokenController.dispose();
    _mensageriaBackendUrlController.dispose();
    _filtroTextoLogController.dispose();
    _webhookPayloadController.dispose();
    _geminiApiKeyController.dispose();
    _fiscalTokenController.dispose();
    _fiscalCnpjController.dispose();
    _fiscalIeController.dispose();
    _caixaLimiteOrcamentosController.dispose();
    _pdvBloqueioInatividadeMinutosController.dispose();
    super.dispose();
  }

  Future<void> _carregarConfigFiscal() async {
    final cfg = await FiscalConfigStore.carregar();
    if (!mounted) return;
    setState(() {
      _fiscalTokenController.text = cfg.apiToken;
      _fiscalCnpjController.text = cfg.cnpjEmitente;
      _fiscalIeController.text = cfg.inscricaoEstadualEmitente;
      _fiscalAmbiente = cfg.homologacao ? 'homologacao' : 'producao';
      _fiscalRegime = FiscalRegimePadrao.regimeEfetivo(cfg);
    });
  }

  Future<void> _salvarConfigFiscal() async {
    final token = _fiscalTokenController.text.trim();
    if (token.isNotEmpty && token.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Token Focus muito curto.')),
      );
      return;
    }
    await FiscalConfigStore.salvar(
      apiToken: token,
      ambiente: _fiscalAmbiente,
      cnpjEmitente: _fiscalCnpjController.text,
      inscricaoEstadualEmitente: _fiscalIeController.text,
      regimeTributarioEmitente: _fiscalRegime,
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

  Future<void> _carregarConfig() async {
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
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
      _alertasProativosWhatsappAtivos = config.alertasProativosWhatsappAtivos;
      _whatsappDonoController.text = config.whatsappDonoNumero;
      _alertasIntervaloController.text =
          config.alertasProativosIntervaloMinutos.toString();
      _whatsApiVersionController.text = config.whatsappApiVersion;
      _whatsPhoneIdController.text = config.whatsappPhoneNumberId;
      _whatsTokenController.text = config.whatsappAccessToken;
      _mensageriaBackendUrlController.text = config.mensageriaBackendUrl;
      _prefsEmpresaAplicadas = true;
    });
  }

  Future<void> _carregarMensageria() async {
    final templates = await _mensageriaRepository.listarTemplates();
    final fila = await _mensageriaRepository.listarFila();
    final logs = await _mensageriaRepository.listarLogs();
    final resumo = await _mensageriaRepository.resumoDashboard();
    if (!mounted) return;
    setState(() {
      _templatesMensagem = templates;
      _filaPendente = fila.where((e) => e.status == 'pendente').length;
      _logsTotais = logs.length;
      _logsEnviados = resumo.enviados;
      _logsEntregues = resumo.entregues;
      _logsLidos = resumo.lidos;
      _logsFalhas = resumo.falhas;
    });
    await _aplicarFiltroLogs();
  }

  Future<void> _aplicarFiltroLogs() async {
    final logs = await _mensageriaRepository.filtrarLogs(
      statusEntrega: _filtroStatusLog,
      canal: _filtroCanalLog,
      texto: _filtroTextoLogController.text,
    );
    if (!mounted) return;
    setState(() {
      _logsFiltrados = logs;
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
      await widget.appConfigRepository.salvarEmpresaConfig(
        disco.copyWith(
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
          alertasProativosWhatsappAtivos: _alertasProativosWhatsappAtivos,
          whatsappDonoNumero: _whatsappDonoController.text.trim(),
          alertasProativosIntervaloMinutos: int.tryParse(
                _alertasIntervaloController.text.trim(),
              ) ??
              120,
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
          pdvExigirVendedor: _pdvExigirVendedor,
          pdvBloqueioVendedor: _pdvBloqueioVendedor,
          pdvBloqueioVendedorAposOrcamento: _pdvBloqueioVendedor &&
              _pdvBloqueioVendedorAposOrcamento,
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
          whatsappApiVersion: _whatsApiVersionController.text,
          whatsappPhoneNumberId: _whatsPhoneIdController.text,
          whatsappAccessToken: _whatsTokenController.text,
          mensageriaBackendUrl: _mensageriaBackendUrlController.text,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuracoes da empresa salvas.')),
      );
    } finally {
      if (mounted) {
        setState(() => _salvando = false);
      }
    }
  }

  Future<void> _abrirCadastroTemplate({MensagemTemplate? template}) async {
    final nomeController = TextEditingController(text: template?.nome ?? '');
    final metaTemplateController = TextEditingController(
      text: template?.metaTemplateName ?? '',
    );
    final textoController = TextEditingController(
      text: template?.textoBase ?? '',
    );
    String canal = template?.canal ?? 'whatsapp';
    String evento = template?.evento ?? 'manual';
    bool ativo = template?.ativo ?? true;
    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                template == null ? 'Novo template' : 'Editar template',
              ),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nomeController,
                      decoration: const InputDecoration(labelText: 'Nome'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: canal,
                      decoration: const InputDecoration(labelText: 'Canal'),
                      items: const [
                        DropdownMenuItem(
                          value: 'whatsapp',
                          child: Text('WhatsApp'),
                        ),
                        DropdownMenuItem(value: 'sms', child: Text('SMS')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => canal = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: evento,
                      decoration: const InputDecoration(labelText: 'Evento'),
                      items: const [
                        DropdownMenuItem(
                          value: 'manual',
                          child: Text('Manual'),
                        ),
                        DropdownMenuItem(
                          value: 'venda_finalizada',
                          child: Text('Venda finalizada'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => evento = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: metaTemplateController,
                      decoration: const InputDecoration(
                        labelText: 'Template Meta (opcional)',
                        hintText: 'Ex.: venda_confirmada',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: textoController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Texto base',
                        hintText:
                            'Use variaveis: {{cliente_nome}} {{numero_orcamento}} {{valor_total}}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Template ativo'),
                      value: ativo,
                      onChanged: (v) => setDialogState(() => ativo = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (salvar != true) return;
    final nome = nomeController.text.trim();
    if (nome.isEmpty) return;
    await _mensageriaRepository.salvarTemplate(
      MensagemTemplate(
        id: template?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        nome: nome,
        canal: canal,
        evento: evento,
        textoBase: textoController.text.trim(),
        metaTemplateName: metaTemplateController.text.trim(),
        ativo: ativo,
        criadoEm: template?.criadoEm ?? DateTime.now(),
      ),
    );
    await _carregarMensageria();
  }

  Future<void> _removerTemplate(MensagemTemplate template) async {
    await _mensageriaRepository.removerTemplate(template.id);
    await _carregarMensageria();
  }

  Future<void> _processarFilaMensagens() async {
    final processadas = await _mensageriaRepository.processarFilaPendente();
    await _carregarMensageria();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Fila processada: $processadas mensagem(ns).')),
    );
  }

  Future<void> _processarWebhookWhatsapp() async {
    final payload = _webhookPayloadController.text.trim();
    if (payload.isEmpty) return;
    final atualizados = await _mensageriaRepository
        .processarWebhookWhatsappPayload(payload);
    await _carregarMensageria();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Webhook processado: $atualizados log(s) atualizados.'),
      ),
    );
  }

  Future<void> _reenfileirarFalhaDeLog(MensagemLog log) async {
    await _mensageriaRepository.reenfileirarFalha(log.filaId);
    await _carregarMensageria();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mensagem falha reenfileirada.')),
    );
  }

  Future<void> _verErroDetalhadoLog(MensagemLog log) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Erro detalhado do envio'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: SelectableText(
                log.responseJson.trim().isEmpty
                    ? 'Sem detalhe retornado pela API.'
                    : log.responseJson,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _mostrarContratoBackendMensageria() async {
    const exemploRequest = '''
{
  "canal": "whatsapp",
  "destino": "5599999999999",
  "templateId": "id_template",
  "templateName": "nome_template_meta_ou_vazio",
  "idioma": "pt_BR",
  "payload": {
    "messaging_product": "whatsapp",
    "to": "5599999999999",
    "type": "text",
    "text": {
      "body": "Mensagem renderizada pelo sistema"
    }
  },
  "meta": {
    "origin": "sistema_vendas_desktop",
    "test": false
  }
}
''';
    const exemploResponseOk = '''
{
  "ok": true,
  "provider": "whatsapp_cloud_api",
  "providerMessageId": "wamid.HBg...",
  "status": "accepted"
}
''';
    const exemploResponseErro = '''
{
  "ok": false,
  "error": "invalid_token_or_destination"
}
''';
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Contrato do Backend de Mensageria'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: SelectableText(
                'REQUEST (POST JSON)\\n$exemploRequest\\n\\n'
                'RESPONSE 2xx (sucesso)\\n$exemploResponseOk\\n\\n'
                'RESPONSE erro (4xx/5xx)\\n$exemploResponseErro',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _testarBackendMensageria() async {
    final url = _mensageriaBackendUrlController.text.trim();
    final resultado = await _mensageriaRepository.testarBackend(
      backendUrl: url,
    );
    if (!mounted) return;
    final status = resultado.statusHttp == 0
        ? '-'
        : resultado.statusHttp.toString();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          resultado.sucesso
              ? 'Backend respondeu com sucesso (HTTP $status).'
              : 'Falha no teste do backend (HTTP $status).',
        ),
      ),
    );
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Resultado do teste de backend'),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: SelectableText(resultado.resposta),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
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
        RedeSincronizacaoCard(
          configRepository: widget.appConfigRepository,
          lanSyncScheduler: widget.lanSyncScheduler,
        ),
      ],
      secao: ConfigSecoes.todas[5],
    );
  }

  Widget _painelBackup() {
    return _configTab(
      [
        BackupConfiguracaoSection(
          appConfigRepository: widget.appConfigRepository,
          objectBox: widget.objectBox,
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

  Widget _painelMensagens() {
    return _configTab(
      [
        ConfigSectionCard(
          icon: Icons.notifications_active_outlined,
          title: 'Alertas proativos WhatsApp',
          subtitle: 'Fiado vencido, estoque zerado e caixa aberto apos 18h.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _alertasProativosWhatsappAtivos,
                onChanged: (value) {
                  setState(() => _alertasProativosWhatsappAtivos = value);
                },
                title: const Text('Ativar alertas proativos'),
                subtitle: const Text(
                  'Envia alertas para o numero do dono (requer mensageria configurada).',
                ),
              ),
              TextField(
                controller: _whatsappDonoController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'WhatsApp do dono',
                  hintText: 'Ex.: 5511999999999',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _alertasIntervaloController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Intervalo entre alertas (minutos)',
                  hintText: '120',
                ),
              ),
              const SizedBox(height: 12),
              ConfigSaveButton(
                salvando: _salvando,
                onPressed: _salvarConfig,
                label: 'Salvar alertas proativos',
              ),
            ],
          ),
        ),
        ConfigSectionCard(
          icon: Icons.chat_outlined,
          title: 'Mensageria (WhatsApp/SMS)',
          subtitle: 'Credenciais, templates, fila e monitoramento de envios.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _mensageriaBackendUrlController,
                decoration: const InputDecoration(
                  labelText: 'Backend URL de envio (opcional)',
                  hintText: 'https://seu-backend/send-whatsapp',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _whatsApiVersionController,
                decoration: const InputDecoration(
                  labelText: 'WhatsApp API Version',
                  hintText: 'v20.0',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _whatsPhoneIdController,
                decoration: const InputDecoration(
                  labelText: 'WhatsApp Phone Number ID',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _whatsTokenController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'WhatsApp Access Token',
                ),
              ),
              const SizedBox(height: 8),
              ConfigSaveButton(
                salvando: _salvando,
                onPressed: _salvarConfig,
                label: 'Salvar credenciais de mensageria',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _mostrarContratoBackendMensageria,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Ver contrato do backend'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testarBackendMensageria,
                      icon: const Icon(Icons.wifi_tethering_outlined),
                      label: const Text('Testar backend'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text('Templates: ${_templatesMensagem.length}')),
                  Expanded(child: Text('Fila pendente: $_filaPendente')),
                  Expanded(child: Text('Logs: $_logsTotais')),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  Text('Enviadas: $_logsEnviados'),
                  Text('Entregues: $_logsEntregues'),
                  Text('Lidas: $_logsLidos'),
                  Text('Falhas: $_logsFalhas'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _abrirCadastroTemplate,
                      icon: const Icon(Icons.add),
                      label: const Text('Novo template'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _processarFilaMensagens,
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Processar fila'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_templatesMensagem.isEmpty)
                const Text('Nenhum template cadastrado.')
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 230),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _templatesMensagem.length,
                    itemBuilder: (context, index) {
                      final t = _templatesMensagem[index];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        title: Text(t.nome),
                        subtitle: Text(
                          '${t.canal} | evento: ${t.evento} | ${t.ativo ? 'ativo' : 'inativo'}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Editar',
                              onPressed: () => _abrirCadastroTemplate(template: t),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Excluir',
                              onPressed: () => _removerTemplate(t),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 10),
              const Divider(),
              const SizedBox(height: 6),
              Text(
                'Monitor de fila e logs',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<String>(
                      initialValue: _filtroStatusLog,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(value: 'todos', child: Text('Todos')),
                        DropdownMenuItem(
                          value: 'aceito_api',
                          child: Text('Aceito pela API'),
                        ),
                        DropdownMenuItem(value: 'enviado', child: Text('Enviado')),
                        DropdownMenuItem(value: 'entregue', child: Text('Entregue')),
                        DropdownMenuItem(value: 'lido', child: Text('Lido')),
                        DropdownMenuItem(value: 'falhou', child: Text('Falhou')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _filtroStatusLog = v);
                        _aplicarFiltroLogs();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<String>(
                      initialValue: _filtroCanalLog,
                      decoration: const InputDecoration(labelText: 'Canal'),
                      items: const [
                        DropdownMenuItem(value: 'todos', child: Text('Todos')),
                        DropdownMenuItem(
                          value: 'whatsapp',
                          child: Text('WhatsApp'),
                        ),
                        DropdownMenuItem(value: 'sms', child: Text('SMS')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _filtroCanalLog = v);
                        _aplicarFiltroLogs();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _filtroTextoLogController,
                      decoration: const InputDecoration(
                        labelText: 'Buscar destino/template/erro',
                      ),
                      onSubmitted: (_) => _aplicarFiltroLogs(),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _aplicarFiltroLogs,
                    icon: const Icon(Icons.search),
                    label: const Text('Filtrar'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_logsFiltrados.isEmpty)
                const Text('Nenhum log para os filtros atuais.')
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 230),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _logsFiltrados.length,
                    itemBuilder: (context, index) {
                      final log = _logsFiltrados[index];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        title: Text(
                          '${log.canal.toUpperCase()} | ${_rotuloStatusMensagem(log.statusEntrega)} | cliente ${log.clienteId}',
                        ),
                        subtitle: Text(log.destino),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(log.resultado),
                            if (log.resultado == 'falhou')
                              IconButton(
                                tooltip: 'Reenfileirar',
                                onPressed: () => _reenfileirarFalhaDeLog(log),
                                icon: const Icon(Icons.refresh),
                              ),
                            if (log.resultado == 'falhou')
                              IconButton(
                                tooltip: 'Ver erro detalhado',
                                onPressed: () => _verErroDetalhadoLog(log),
                                icon: const Icon(Icons.error_outline),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _webhookPayloadController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Payload webhook WhatsApp (JSON)',
                  hintText: 'Cole aqui o payload de status do WhatsApp.',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _processarWebhookWhatsapp,
                icon: const Icon(Icons.hub_outlined),
                label: const Text('Processar webhook de status'),
              ),
            ],
          ),
        ),
      ],
      secao: ConfigSecoes.todas[7],
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
      ],
      secao: ConfigSecoes.todas[8],
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
      case 'mensagens':
        return _painelMensagens();
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
