import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

import '../../data/app_config_repository.dart';
import '../../data/produto_repository.dart';
import '../../domain/obra_calculadora.dart';
import '../../domain/obra_calculadora_gemini_parse.dart';
import '../../domain/obra_calculadora_projeto.dart';
import '../../domain/obra_calculadora_templates.dart';
import '../../domain/pdv_obra_calculadora_insercao.dart';
import '../../domain/pdv_estoque_semaforo_util.dart';
import '../../services/gemini_config.dart';
import '../../services/gemini_service.dart';
import '../../services/obra_calculadora_pdf.dart';

class _HistoricoObraSessao {
  const _HistoricoObraSessao({
    required this.resumo,
    required this.tipo,
    required this.parse,
  });

  final String resumo;
  final ObraReceitaTipo tipo;
  final ObraCalculadoraParseResult parse;
}

/// Calculadora de obra (Fase 3): projeto acumulado, PDF, substitutos.
class PdvObraCalculadoraPanel extends StatefulWidget {
  const PdvObraCalculadoraPanel({
    super.key,
    required this.config,
    required this.produtoRepository,
    required this.onFechar,
    required this.onAdicionarTudo,
    this.onPanDelta,
  });

  static const double largura = 440;
  static const double alturaEstimada = 720;

  final EmpresaConfig config;
  final ProdutoRepository produtoRepository;
  final VoidCallback onFechar;
  final Future<void> Function(List<PdvObraCalculadoraLinhaInsercao> linhas)
      onAdicionarTudo;
  final void Function(Offset delta)? onPanDelta;

  @override
  State<PdvObraCalculadoraPanel> createState() =>
      _PdvObraCalculadoraPanelState();
}

class _PdvObraCalculadoraPanelState extends State<PdvObraCalculadoraPanel> {
  final _larguraCtrl = TextEditingController(text: '4');
  final _alturaCtrl = TextEditingController(text: '3');
  final _areaCtrl = TextEditingController(text: '12');
  final _perdaCtrl = TextEditingController(text: '10');
  final _espessuraCtrl = TextEditingController(text: '20');
  final _textoLivreCtrl = TextEditingController();
  final _portasCtrl = TextEditingController(text: '0');
  final _janelasCtrl = TextEditingController(text: '0');
  final _comprimentoCtrl = TextEditingController(text: '10');
  final _profundidadeCtrl = TextEditingController(text: '0,50');
  final _inclinacaoCtrl = TextEditingController(text: '30');
  final _nomeObraCtrl = TextEditingController();
  final _nomeClienteCtrl = TextEditingController();

  ObraReceitaTipo _tipo = ObraReceitaTipo.parede;
  TipoTijoloObra _tipoTijolo = TipoTijoloObra.ceramico8f_9x19x19;
  ObraCalculadoraResultado? _resultado;
  PdvObraCalculadoraMontagem? _montagem;
  bool _inserindo = false;
  bool _interpretando = false;
  bool _gerandoPdf = false;
  bool _areaEditadaManualmente = false;
  final List<_HistoricoObraSessao> _historico = [];
  final ObraCalculadoraProjetoSessao _projeto = ObraCalculadoraProjetoSessao();

  List<ObraCalculadoraTemplate> get _templates =>
      ObraCalculadoraTemplatesUtil.decode(widget.config.obraCalcTemplatesJson);

  @override
  void initState() {
    super.initState();
    _perdaCtrl.text = _perdaAtual().toStringAsFixed(0);
    _espessuraCtrl.text = _espessuraAtual().toStringAsFixed(0);
    _inclinacaoCtrl.text = widget.config.obraCalcInclinacaoTelhadoPct
        .toStringAsFixed(0);
    _recalcular();
  }

  @override
  void dispose() {
    _larguraCtrl.dispose();
    _alturaCtrl.dispose();
    _areaCtrl.dispose();
    _perdaCtrl.dispose();
    _espessuraCtrl.dispose();
    _textoLivreCtrl.dispose();
    _portasCtrl.dispose();
    _janelasCtrl.dispose();
    _comprimentoCtrl.dispose();
    _profundidadeCtrl.dispose();
    _inclinacaoCtrl.dispose();
    _nomeObraCtrl.dispose();
    _nomeClienteCtrl.dispose();
    super.dispose();
  }

  double _perdaAtual() => switch (_tipo) {
        ObraReceitaTipo.parede => widget.config.obraCalcPerdaPadraoPct,
        ObraReceitaTipo.reboco => widget.config.obraCalcPerdaRebocoPct,
        ObraReceitaTipo.piso => widget.config.obraCalcPerdaPisoPct,
        ObraReceitaTipo.contrapiso => widget.config.obraCalcPerdaPadraoPct,
        ObraReceitaTipo.laje => widget.config.obraCalcPerdaLajePct,
        ObraReceitaTipo.fundacao => widget.config.obraCalcPerdaFundacaoPct,
        ObraReceitaTipo.telhado => widget.config.obraCalcPerdaTelhadoPct,
      };

  double _espessuraAtual() => switch (_tipo) {
        ObraReceitaTipo.reboco => widget.config.obraCalcEspessuraRebocoMm,
        ObraReceitaTipo.contrapiso =>
          widget.config.obraCalcEspessuraContrapisoMm,
        ObraReceitaTipo.laje => widget.config.obraCalcEspessuraLajeMm,
        _ => 20,
      };

  double? _parseBr(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.'));

  /// Area para reboco, piso, laje etc.: dims vencem salvo edicao manual do campo Area.
  double _areaEfetivaM2() {
    if (!_areaEditadaManualmente) {
      final l = _parseBr(_larguraCtrl.text) ?? 0;
      final h = _parseBr(_alturaCtrl.text) ?? 0;
      if (l > 0 && h > 0) return l * h;
    }
    return _parseBr(_areaCtrl.text) ?? 0;
  }

  void _sincronizarAreaDasDimensoes() {
    final l = _parseBr(_larguraCtrl.text) ?? 0;
    final h = _parseBr(_alturaCtrl.text) ?? 0;
    if (l > 0 && h > 0) {
      _areaCtrl.text = (l * h).toStringAsFixed(2);
    }
  }

  void _onDimensao2Changed() {
    _areaEditadaManualmente = false;
    if (usaAreaReceita(_tipo)) {
      _sincronizarAreaDasDimensoes();
    }
    _recalcular();
  }

  void _onAreaChanged() {
    _areaEditadaManualmente = true;
    _recalcular();
  }

  double _m2PorCaixa() {
    final id = widget.config.obraCalcPisoProdutoId;
    if (id > 0) {
      final p = widget.produtoRepository.obterPorId(id);
      if (p != null) {
        return PdvObraCalculadoraInsercaoUtil.m2PorCaixaDoProduto(p);
      }
    }
    return widget.config.obraCalcM2PorCaixaPiso;
  }

  List<ObraAberturaPadrao> _aberturasFormulario() {
    final out = <ObraAberturaPadrao>[];
    final portas = int.tryParse(_portasCtrl.text.trim()) ?? 0;
    final janelas = int.tryParse(_janelasCtrl.text.trim()) ?? 0;
    if (portas > 0) out.add(ObraAberturaPadrao.porta(quantidade: portas));
    if (janelas > 0) out.add(ObraAberturaPadrao.janela(quantidade: janelas));
    return out;
  }

  ObraCalculadoraResultado? _calcularAtual() {
    final perda = _parseBr(_perdaCtrl.text) ?? _perdaAtual();
    switch (_tipo) {
      case ObraReceitaTipo.parede:
        return ObraCalculadora.calcularParedeAlvenaria(
          ObraCalculadoraEntrada(
            larguraM: _parseBr(_larguraCtrl.text) ?? 0,
            alturaM: _parseBr(_alturaCtrl.text) ?? 0,
            tipoTijolo: _tipoTijolo,
            perdaPct: perda,
            aberturas: _aberturasFormulario(),
          ),
        );
      case ObraReceitaTipo.reboco:
        return ObraCalculadora.calcularReboco(
          ObraArgamassaEntrada(
            areaM2: _areaEfetivaM2(),
            perdaPct: perda,
            espessuraMm: _parseBr(_espessuraCtrl.text) ?? _espessuraAtual(),
          ),
        );
      case ObraReceitaTipo.contrapiso:
        return ObraCalculadora.calcularContrapiso(
          ObraArgamassaEntrada(
            areaM2: _areaEfetivaM2(),
            perdaPct: perda,
            espessuraMm: _parseBr(_espessuraCtrl.text) ?? _espessuraAtual(),
          ),
        );
      case ObraReceitaTipo.piso:
        return ObraCalculadora.calcularPiso(
          ObraPisoEntrada(
            areaM2: _areaEfetivaM2(),
            perdaPct: perda,
            m2PorCaixa: _m2PorCaixa(),
          ),
        );
      case ObraReceitaTipo.laje:
        return ObraCalculadora.calcularLaje(
          ObraLajeEntrada(
            areaM2: _areaEfetivaM2(),
            perdaPct: perda,
            espessuraMm: _parseBr(_espessuraCtrl.text) ?? _espessuraAtual(),
          ),
        );
      case ObraReceitaTipo.fundacao:
        return ObraCalculadora.calcularFundacao(
          ObraFundacaoEntrada(
            comprimentoM: _parseBr(_comprimentoCtrl.text) ?? 0,
            larguraM: _parseBr(_larguraCtrl.text) ?? 0.40,
            profundidadeM: _parseBr(_profundidadeCtrl.text) ?? 0.50,
            perdaPct: perda,
          ),
        );
      case ObraReceitaTipo.telhado:
        return ObraCalculadora.calcularTelhado(
          ObraTelhadoEntrada(
            areaM2: _areaEfetivaM2(),
            perdaPct: perda,
            inclinacaoPct: _parseBr(_inclinacaoCtrl.text) ??
                widget.config.obraCalcInclinacaoTelhadoPct,
            telhasPorM2: widget.config.obraCalcTelhasPorM2,
          ),
        );
    }
  }

  void _recalcular() {
    final res = _calcularAtual();
    PdvObraCalculadoraMontagem? mont;
    if (res != null) {
      mont = PdvObraCalculadoraInsercaoUtil.montar(
        resultado: res,
        config: widget.config,
        produtoRepository: widget.produtoRepository,
      );
    }
    setState(() {
      _resultado = res;
      _montagem = mont;
    });
  }

  void _aplicarParse(ObraCalculadoraParseResult parsed) {
    setState(() {
      _tipo = parsed.tipo;
      _tipoTijolo = parsed.tipoTijolo;
      _areaEditadaManualmente = parsed.areaCalculadaM2 > 0 &&
          (parsed.larguraM <= 0 || parsed.alturaM <= 0);
      _perdaCtrl.text = _perdaAtual().toStringAsFixed(0);
      _espessuraCtrl.text = (parsed.espessuraMm > 0
              ? parsed.espessuraMm
              : _espessuraAtual())
          .toStringAsFixed(0);
      if (parsed.larguraM > 0) {
        _larguraCtrl.text = parsed.larguraM.toString();
      }
      if (parsed.alturaM > 0) {
        _alturaCtrl.text = parsed.alturaM.toString();
      }
      if (parsed.areaCalculadaM2 > 0) {
        _areaCtrl.text = parsed.areaCalculadaM2.toStringAsFixed(2);
      }
      if (parsed.comprimentoM > 0) {
        _comprimentoCtrl.text = parsed.comprimentoM.toString();
      }
      if (parsed.profundidadeM > 0) {
        _profundidadeCtrl.text = parsed.profundidadeM.toString();
      }
      if (parsed.inclinacaoPct > 0) {
        _inclinacaoCtrl.text = parsed.inclinacaoPct.toStringAsFixed(0);
      }
      var portas = 0;
      var janelas = 0;
      for (final a in parsed.aberturas) {
        if (a.tipo == ObraAberturaTipo.porta) portas += a.quantidade;
        if (a.tipo == ObraAberturaTipo.janela) janelas += a.quantidade;
      }
      _portasCtrl.text = portas.toString();
      _janelasCtrl.text = janelas.toString();
      if (usaAreaReceita(_tipo) &&
          !_areaEditadaManualmente &&
          (_parseBr(_larguraCtrl.text) ?? 0) > 0 &&
          (_parseBr(_alturaCtrl.text) ?? 0) > 0) {
        _sincronizarAreaDasDimensoes();
      }
    });
    _recalcular();
  }

  Future<void> _aplicarTextoLivre() async {
    final texto = _textoLivreCtrl.text.trim();
    if (texto.isEmpty) return;

    setState(() => _interpretando = true);
    try {
      var parsed = ObraCalculadora.parseTextoLivre(
        texto,
        perdaPadraoPct: widget.config.obraCalcPerdaPadraoPct,
      );

      if (parsed == null &&
          widget.config.obraCalcGeminiParseAtivo &&
          GeminiConfig.chavePareceValida(await GeminiConfig.resolverChave())) {
        try {
          parsed = await ObraCalculadoraGeminiParse.interpretar(
            texto,
            perdaPadraoPct: widget.config.obraCalcPerdaPadraoPct,
          );
        } on GeminiConfigException {
          // cai no snack abaixo
        } on GeminiServiceException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.message)),
            );
          }
        }
      }

      if (parsed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Nao entendi. Ex.: "Parede 4x3 tijolo 9x19x19", '
                '"Reboco 12m2", "Piso 6m2", "Contrapiso 20m2".',
              ),
            ),
          );
        }
        return;
      }
      _aplicarParse(parsed);
    } finally {
      if (mounted) setState(() => _interpretando = false);
    }
  }

  void _aplicarTemplate(ObraCalculadoraTemplate t) {
    _aplicarParse(
      ObraCalculadoraParseResult(
        tipo: t.tipo,
        larguraM: t.larguraM,
        alturaM: t.alturaM,
        areaM2: t.areaM2,
        tipoTijolo: t.tipoTijolo,
        perdaPct: t.perdaPct,
        espessuraMm: t.espessuraMm,
        aberturas: t.aberturas,
      ),
    );
  }

  void _registrarHistorico() {
    final res = _resultado;
    if (res == null) return;
    final parse = ObraCalculadoraParseResult(
      tipo: _tipo,
      larguraM: _parseBr(_larguraCtrl.text) ?? 0,
      alturaM: _parseBr(_alturaCtrl.text) ?? 0,
      areaM2: _areaEditadaManualmente
          ? (_parseBr(_areaCtrl.text) ?? res.areaM2)
          : _areaEfetivaM2(),
      tipoTijolo: _tipoTijolo,
      perdaPct: _parseBr(_perdaCtrl.text) ?? _perdaAtual(),
      espessuraMm: _parseBr(_espessuraCtrl.text) ?? _espessuraAtual(),
      aberturas: _aberturasFormulario(),
    );
    setState(() {
      _historico.insert(
        0,
        _HistoricoObraSessao(
          resumo: res.resumo,
          tipo: _tipo,
          parse: parse,
        ),
      );
      if (_historico.length > 8) _historico.removeLast();
    });
  }

  Future<void> _inserirTudo() async {
    final mont = _montagem;
    if (mont == null || !mont.podeInserir) return;
    setState(() => _inserindo = true);
    try {
      _registrarHistorico();
      await widget.onAdicionarTudo(mont.linhas);
      if (mounted) widget.onFechar();
    } finally {
      if (mounted) setState(() => _inserindo = false);
    }
  }

  void _adicionarAoProjeto() {
    final mont = _montagem;
    final res = _resultado;
    if (mont == null || res == null || !mont.podeInserir) return;
    _projeto.nomeObra = _nomeObraCtrl.text.trim();
    _projeto.nomeCliente = _nomeClienteCtrl.text.trim();
    _projeto.adicionar(
      ObraCalculadoraProjetoItem(
        rotuloReceita: _tipo.rotulo,
        resumo: res.resumo,
        montagem: mont,
      ),
    );
    _registrarHistorico();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Adicionado ao projeto (${_projeto.quantidadeItens} etapas).',
        ),
      ),
    );
  }

  Future<void> _inserirProjeto() async {
    if (_projeto.vazio) return;
    final linhas = _projeto.linhasConsolidadas();
    if (linhas.isEmpty) return;
    setState(() => _inserindo = true);
    try {
      await widget.onAdicionarTudo(linhas);
      if (mounted) widget.onFechar();
    } finally {
      if (mounted) setState(() => _inserindo = false);
    }
  }

  Future<void> _exportarPdfProjeto() async {
    final linhas = _projeto.vazio
        ? (_montagem?.linhas ?? const [])
        : _projeto.linhasConsolidadas();
    if (linhas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nada para exportar.')),
      );
      return;
    }
    _projeto.nomeObra = _nomeObraCtrl.text.trim();
    _projeto.nomeCliente = _nomeClienteCtrl.text.trim();
    setState(() => _gerandoPdf = true);
    try {
      final bytes = await gerarObraCalculadoraProjetoPdf(
        config: widget.config,
        projeto: _projeto,
        linhas: linhas,
      );
      if (!mounted) return;
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _gerandoPdf = false);
    }
  }

  Future<void> _salvarPdfProjeto() async {
    final linhas = _projeto.vazio
        ? (_montagem?.linhas ?? const [])
        : _projeto.linhasConsolidadas();
    if (linhas.isEmpty) return;
    _projeto.nomeObra = _nomeObraCtrl.text.trim();
    _projeto.nomeCliente = _nomeClienteCtrl.text.trim();
    final pasta = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Salvar PDF da obra',
    );
    if (pasta == null || pasta.trim().isEmpty) return;
    setState(() => _gerandoPdf = true);
    try {
      final bytes = await gerarObraCalculadoraProjetoPdf(
        config: widget.config,
        projeto: _projeto,
        linhas: linhas,
      );
      final nome = (_projeto.nomeObra.trim().isEmpty
              ? 'obra_calculada'
              : _projeto.nomeObra.trim())
          .replaceAll(RegExp(r'[^\w\-]+'), '_');
      final arquivo = File(
        p.join(pasta, '${nome}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf'),
      );
      await arquivo.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF salvo: ${arquivo.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _gerandoPdf = false);
    }
  }

  void _mudarTipo(ObraReceitaTipo t) {
    setState(() {
      final anterior = _tipo;
      _tipo = t;
      if (t == ObraReceitaTipo.fundacao &&
          anterior != ObraReceitaTipo.fundacao) {
        _larguraCtrl.text = '0,40';
        _profundidadeCtrl.text = '0,50';
        if ((_parseBr(_comprimentoCtrl.text) ?? 0) <= 0) {
          _comprimentoCtrl.text = '10';
        }
      } else if (t == ObraReceitaTipo.parede &&
          anterior == ObraReceitaTipo.fundacao) {
        _larguraCtrl.text = '4';
        _alturaCtrl.text = '3';
      } else if (usaAreaReceita(t)) {
        _areaEditadaManualmente = false;
        final l = _parseBr(_larguraCtrl.text) ?? 0;
        final a = _parseBr(_alturaCtrl.text) ?? 0;
        if (l > 0 && a > 0) {
          _areaCtrl.text = (l * a).toStringAsFixed(2);
        }
      }
      _perdaCtrl.text = _perdaAtual().toStringAsFixed(0);
      _espessuraCtrl.text = _espessuraAtual().toStringAsFixed(0);
    });
    _recalcular();
  }

  static bool usaAreaReceita(ObraReceitaTipo t) =>
      t == ObraReceitaTipo.reboco ||
      t == ObraReceitaTipo.contrapiso ||
      t == ObraReceitaTipo.piso ||
      t == ObraReceitaTipo.laje ||
      t == ObraReceitaTipo.telhado;

  Future<void> _escolherTemplate(List<ObraCalculadoraTemplate> templates) async {
    final picked = await _OverlayPickerField.showSheet<ObraCalculadoraTemplate>(
      context: context,
      title: 'Template salvo',
      items: templates,
      itemLabel: (t) => t.nome,
      selected: null,
    );
    if (picked != null) _aplicarTemplate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mont = _montagem;
    final res = _resultado;
    final fmt = NumberFormat('#,##0.##', 'pt_BR');
    final templates = _templates;

    return SizedBox(
      width: PdvObraCalculadoraPanel.largura,
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onPanUpdate: widget.onPanDelta == null
                  ? null
                  : (d) => widget.onPanDelta!(d.delta),
              child: Container(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                child: Row(
                  children: [
                    Icon(Icons.construction_outlined,
                        color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Calculadora de obra (F12)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar (Esc)',
                      onPressed: widget.onFechar,
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 560),
              child: SingleChildScrollView(
                clipBehavior: Clip.none,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _textoLivreCtrl,
                      decoration: InputDecoration(
                        labelText: 'Descreva a obra',
                        hintText: 'Parede 4x3 1 porta · Reboco 12m2 · Piso 6m2',
                        isDense: true,
                        suffixIcon: _interpretando
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                tooltip: 'Interpretar texto',
                                onPressed: _aplicarTextoLivre,
                                icon: const Icon(Icons.auto_fix_high_outlined),
                              ),
                      ),
                      onSubmitted: (_) => _aplicarTextoLivre(),
                    ),
                    if (templates.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _escolherTemplate(templates),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Template salvo',
                            isDense: true,
                            suffixIcon: Icon(Icons.arrow_drop_down),
                          ),
                          child: Text(
                            'Toque para aplicar',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (_historico.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Historico (sessao)',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      ..._historico.take(3).map(
                            (h) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                h.resumo,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                              trailing: const Icon(Icons.replay, size: 18),
                              onTap: () => _aplicarParse(h.parse),
                            ),
                          ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nomeObraCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nome da obra',
                              isDense: true,
                            ),
                            onChanged: (_) => _projeto.nomeObra = _nomeObraCtrl.text,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _nomeClienteCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Cliente',
                              isDense: true,
                            ),
                            onChanged: (_) =>
                                _projeto.nomeCliente = _nomeClienteCtrl.text,
                          ),
                        ),
                      ],
                    ),
                    if (!_projeto.vazio) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Projeto: ${_projeto.quantidadeItens} etapa(s) · '
                        '${_projeto.linhasConsolidadas().length} produto(s)',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _OverlayPickerField<ObraReceitaTipo>(
                      label: 'Tipo de calculo',
                      value: _tipo,
                      items: ObraReceitaTipo.values,
                      itemLabel: (t) => t.rotulo,
                      onChanged: _mudarTipo,
                    ),
                    const SizedBox(height: 10),
                    _buildFormulario(theme),
                    if (res != null) ...[
                      const SizedBox(height: 10),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiaryContainer
                              .withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.tertiary
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 18,
                                color: theme.colorScheme.onTertiaryContainer,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  ObraCalculadora.avisoEstimativa,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onTertiaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        switch (res.tipo) {
                          ObraReceitaTipo.parede =>
                            'Area liquida: ${fmt.format(res.areaM2)} m²'
                                '${res.areaAberturasM2 > 0 ? ' (−${fmt.format(res.areaAberturasM2)} aberturas)' : ''}',
                          ObraReceitaTipo.fundacao =>
                            'Volume: ${fmt.format(res.volumeM3)} m³ · Area ${fmt.format(res.areaM2)} m²',
                          ObraReceitaTipo.laje =>
                            'Volume: ${fmt.format(res.volumeM3)} m³ · Area ${fmt.format(res.areaM2)} m²',
                          _ => 'Area: ${fmt.format(res.areaM2)} m²',
                        },
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (mont != null && mont.avisos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...mont.avisos.map(
                        (a) => Text(
                          '↪ $a',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.tertiary,
                          ),
                        ),
                      ),
                    ],
                    if (mont != null && mont.errosConfig.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      MaterialBanner(
                        content: Text(
                          'Configure produtos em Configuracoes > PDV: '
                          '${mont.errosConfig.join(", ")}.',
                        ),
                        leading: Icon(
                          Icons.warning_amber_rounded,
                          color: theme.colorScheme.error,
                        ),
                        actions: [
                          TextButton(
                            onPressed: widget.onFechar,
                            child: const Text('Fechar'),
                          ),
                        ],
                      ),
                    ],
                    if (mont != null && mont.linhas.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Materiais calculados',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...mont.linhas.map(
                        (l) => _LinhaPreview(linha: l, formatar: fmt),
                      ),
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _inserindo ||
                              mont == null ||
                              !mont.podeInserir
                          ? null
                          : _adicionarAoProjeto,
                      icon: const Icon(Icons.playlist_add_outlined),
                      label: const Text('Adicionar ao projeto'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _inserindo ||
                              mont == null ||
                              !mont.podeInserir
                          ? null
                          : _inserirTudo,
                      icon: _inserindo
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_shopping_cart_outlined),
                      label: Text(
                        _inserindo
                            ? 'Adicionando…'
                            : 'Adicionar etapa ao orcamento',
                      ),
                    ),
                    if (!_projeto.vazio) ...[
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: _inserindo ? null : _inserirProjeto,
                        icon: const Icon(Icons.layers_outlined),
                        label: Text(
                          'Inserir projeto completo (${_projeto.quantidadeItens})',
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _gerandoPdf ? null : _exportarPdfProjeto,
                            icon: _gerandoPdf
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('PDF'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _gerandoPdf ? null : _salvarPdfProjeto,
                            icon: const Icon(Icons.save_alt_outlined),
                            label: const Text('Salvar PDF'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ObraCalculadora.avisoEstimativa,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormulario(ThemeData theme) {
    final usaArea =
        _tipo == ObraReceitaTipo.reboco ||
        _tipo == ObraReceitaTipo.contrapiso ||
        _tipo == ObraReceitaTipo.piso ||
        _tipo == ObraReceitaTipo.laje ||
        _tipo == ObraReceitaTipo.telhado;
    final usaDim2 = _tipo == ObraReceitaTipo.parede || usaArea;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_tipo == ObraReceitaTipo.fundacao) ...[
          TextField(
            controller: _comprimentoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Comprimento linear (m)',
              isDense: true,
            ),
            onChanged: (_) => _recalcular(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _larguraCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Largura (m)',
                    isDense: true,
                  ),
                  onChanged: (_) => _recalcular(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _profundidadeCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Profundidade (m)',
                    isDense: true,
                  ),
                  onChanged: (_) => _recalcular(),
                ),
              ),
            ],
          ),
        ] else if (usaDim2)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _larguraCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Largura (m)',
                    isDense: true,
                  ),
                  onChanged: (_) =>
                      usaArea ? _onDimensao2Changed() : _recalcular(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _alturaCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: _tipo == ObraReceitaTipo.parede
                        ? 'Altura (m)'
                        : 'Comprimento (m)',
                    isDense: true,
                  ),
                  onChanged: (_) =>
                      usaArea ? _onDimensao2Changed() : _recalcular(),
                ),
              ),
            ],
          ),
        if (usaArea) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _areaCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Area (m²)',
              isDense: true,
              helperText: () {
                if (_areaEditadaManualmente) {
                  return 'Area informada manualmente';
                }
                return switch (_tipo) {
                  ObraReceitaTipo.piso =>
                    'Largura × comprimento · caixa ≈ ${_m2PorCaixa().toStringAsFixed(2)} m²',
                  ObraReceitaTipo.telhado =>
                    'Largura × comprimento · ${widget.config.obraCalcTelhasPorM2.toStringAsFixed(0)} telhas/m²',
                  _ => 'Atualiza com largura × comprimento',
                };
              }(),
            ),
            onChanged: (_) => _onAreaChanged(),
          ),
        ],
        if (_tipo == ObraReceitaTipo.parede) ...[
          const SizedBox(height: 8),
          _OverlayPickerField<TipoTijoloObra>(
            label: 'Tipo de tijolo',
            value: _tipoTijolo,
            items: TipoTijoloObra.values,
            itemLabel: (t) => t.rotulo,
            onChanged: (v) {
              setState(() => _tipoTijolo = v);
              _recalcular();
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _portasCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Portas (0,80×2,10)',
                    isDense: true,
                  ),
                  onChanged: (_) => _recalcular(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _janelasCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Janelas (1,20×1,20)',
                    isDense: true,
                  ),
                  onChanged: (_) => _recalcular(),
                ),
              ),
            ],
          ),
        ],
        if (_tipo == ObraReceitaTipo.reboco ||
            _tipo == ObraReceitaTipo.contrapiso ||
            _tipo == ObraReceitaTipo.laje) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _espessuraCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Espessura (mm)',
              isDense: true,
              helperText: 'Padrao ${_espessuraAtual().toStringAsFixed(0)} mm',
            ),
            onChanged: (_) => _recalcular(),
          ),
        ],
        if (_tipo == ObraReceitaTipo.telhado) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _inclinacaoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Inclinacao (%)',
              isDense: true,
              helperText:
                  'Padrao ${widget.config.obraCalcInclinacaoTelhadoPct.toStringAsFixed(0)}%',
            ),
            onChanged: (_) => _recalcular(),
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _perdaCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Margem de perda (%)',
            isDense: true,
          ),
          onChanged: (_) => _recalcular(),
        ),
      ],
    );
  }
}

class _LinhaPreview extends StatelessWidget {
  const _LinhaPreview({
    required this.linha,
    required this.formatar,
  });

  final PdvObraCalculadoraLinhaInsercao linha;
  final NumberFormat formatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = linha.produto;
    final nivel = PdvEstoqueSemaforoUtil.nivelDe(p);
    final cor = PdvEstoqueSemaforoUtil.corDe(context, nivel);
    final q = linha.quantidade;
    final qTxt =
        q == q.roundToDouble() ? formatar.format(q) : formatar.format(q);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  linha.substitutoAplicado
                      ? '${p.nome} (subst. ${linha.produtoOriginalNome})'
                      : p.nome,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: linha.substitutoAplicado
                        ? theme.colorScheme.tertiary
                        : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$qTxt ${linha.material.unidadeRotulo} · ${linha.material.detalhe}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Selecao por bottom sheet — evita menu do [DropdownButton] atras do overlay flutuante do PDV.
class _OverlayPickerField<T> extends StatelessWidget {
  const _OverlayPickerField({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T> onChanged;

  static Future<T?> showSheet<T>({
    required BuildContext context,
    required String title,
    required List<T> items,
    required String Function(T) itemLabel,
    T? selected,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...items.map(
                (item) => ListTile(
                  title: Text(itemLabel(item)),
                  selected: selected != null && item == selected,
                  onTap: () => Navigator.pop(ctx, item),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showSheet<T>(
      context: context,
      title: label,
      items: items,
      itemLabel: itemLabel,
      selected: value,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      behavior: HitTestBehavior.opaque,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: null,
          isDense: true,
          suffixIcon: Icon(Icons.arrow_drop_down),
          border: OutlineInputBorder(),
        ).copyWith(labelText: label),
        child: Text(
          itemLabel(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
