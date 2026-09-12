import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api/lan_api_event_hub.dart';
import '../../data/api/nfe_importada_api_repository.dart';
import '../../data/api/produto_api_repository.dart';
import '../../data/devolucao_fornecedor_fiscal_store.dart';
import '../../data/produto_repository.dart';
import '../../data/sync/sync_refresh_hub.dart';
import '../../domain/produto_nome_exibicao.dart';
import '../../model/nfe_importada_registro.dart';
import '../../services/devolucao_fornecedor_fiscal_service.dart';
import '../../services/configuracoes_service.dart';
import '../shell/main_menu_deps.dart';
import '../widgets/lan_api_feedback.dart';
import 'abrir_documento_fiscal.dart';

/// Emite NF-e de devolucao de compra (CFOP 5202/6202) ao fornecedor/fabrica.
///
/// Valores e impostos partem do XML da compra e podem ser ajustados para
/// bater com o espelho enviado pela fabrica.
/// Terminal Leve: listagem/linhas/emissao via API :8788 (Focus no PC1).
class NfeDevolucaoFornecedorPage extends StatefulWidget {
  const NfeDevolucaoFornecedorPage({
    super.key,
    required this.produtoRepository,
    this.nfeImportadaRepository,
    this.chaveNotaInicial,
  });

  final dynamic produtoRepository;
  /// [NfeImportadaApiRepository] no Terminal Leve.
  final dynamic nfeImportadaRepository;
  final String? chaveNotaInicial;

  @override
  State<NfeDevolucaoFornecedorPage> createState() =>
      _NfeDevolucaoFornecedorPageState();
}

class _NfeDevolucaoFornecedorPageState extends State<NfeDevolucaoFornecedorPage> {
  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _data = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final _dataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  static final _num = NumberFormat('#,##0.##', 'pt_BR');

  DevolucaoFornecedorFiscalService? _svcLocal;
  final TextEditingController _motivoCtrl = TextEditingController();
  final TextEditingController _buscaCtrl = TextEditingController();

  List<NfeImportadaRegistro> _notas = const [];
  NfeImportadaRegistro? _selecionada;
  List<DevolucaoFornecedorLinha> _linhas = const [];
  List<DevolucaoFornecedorFiscalRegistro> _historico = const [];
  bool _carregando = false;
  bool _carregandoLinhas = false;
  bool _emitindo = false;
  bool _reconsultando = false;
  VoidCallback? _syncHubListener;
  bool? _apiOnlineAnterior;

  bool get _terminalLeve =>
      MainMenuDeps.maybeOf(context)?.terminalLeve == true;

  NfeImportadaApiRepository? get _repoRemoto {
    final inj = widget.nfeImportadaRepository;
    if (inj is NfeImportadaApiRepository) return inj;
    final deps = MainMenuDeps.maybeOf(context)?.nfeImportadaRepository;
    if (deps is NfeImportadaApiRepository) return deps;
    return null;
  }

  /// So PC servidor (ObjectBox). Terminal usa API — nao chamar aqui.
  DevolucaoFornecedorFiscalService get _svc {
    if (_svcLocal != null) return _svcLocal!;
    final repo = widget.produtoRepository;
    if (repo is! ProdutoRepository) {
      throw StateError(
        'Devolucao local exige ObjectBox do PC servidor.',
      );
    }
    return _svcLocal ??= DevolucaoFornecedorFiscalService(
      produtoRepository: repo,
    );
  }

  @override
  void initState() {
    super.initState();
    _motivoCtrl.text = 'Devolucao de mercadoria ao fornecedor';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_terminalLeve) {
        _apiOnlineAnterior = LanApiEventHub.instance.online;
        LanApiEventHub.instance.addListener(_onLanApiEvento);
      } else {
        _syncHubListener = () {
          if (!mounted) return;
          unawaited(_recarregarAposMutacaoRede());
        };
        SyncRefreshHub.instance.addListener(_syncHubListener!);
      }
      unawaited(ConfiguracoesService.resolverFiscalGlobal());
      unawaited(_carregarNotas());
      unawaited(_reconsultarPendentes(silencioso: true));
    });
  }

  @override
  void dispose() {
    _motivoCtrl.dispose();
    _buscaCtrl.dispose();
    LanApiEventHub.instance.removeListener(_onLanApiEvento);
    if (_syncHubListener != null) {
      SyncRefreshHub.instance.removeListener(_syncHubListener!);
      _syncHubListener = null;
    }
    super.dispose();
  }

  void _onLanApiEvento() {
    if (!_terminalLeve) return;
    final hub = LanApiEventHub.instance;
    final online = hub.online;
    final ficouOnline = online && _apiOnlineAnterior == false;
    _apiOnlineAnterior = online;
    if (hub.deveBloquearOperacoes) return;
    final ent = hub.ultimaEntidade;
    if (!ficouOnline &&
        ent != 'nfe_importada' &&
        ent != 'produto' &&
        ent != 'historico_entrada') {
      return;
    }
    unawaited(_recarregarAposMutacaoRede());
  }

  Future<void> _recarregarAposMutacaoRede() async {
    final sel = _selecionada;
    await _carregarNotas(manterSelecao: true);
    if (!mounted || sel == null) return;
    final ainda = _notas.where((n) => n.id == sel.id).toList();
    if (ainda.isEmpty) {
      setState(() {
        _selecionada = null;
        _linhas = const [];
        _historico = const [];
      });
      return;
    }
    await _selecionarNota(ainda.first);
  }

  Future<void> _carregarNotas({bool manterSelecao = false}) async {
    if (_terminalLeve &&
        !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      return;
    }
    setState(() => _carregando = true);
    try {
      List<NfeImportadaRegistro> notas;
      if (_terminalLeve) {
        final repo = _repoRemoto;
        if (repo == null) {
          throw StateError('Repositorio remoto de NF-e indisponivel.');
        }
        final result = await repo.listarImportadasRemoto(
          ordenacao: 'importacaoDesc',
        );
        notas = result.items;
      } else {
        notas = _svc.listarNotasCompra();
      }
      NfeImportadaRegistro? inicial;
      if (!manterSelecao) {
        final chaveIni =
            (widget.chaveNotaInicial ?? '').replaceAll(RegExp(r'\D'), '');
        if (chaveIni.length == 44) {
          for (final n in notas) {
            if (n.chaveAcesso.replaceAll(RegExp(r'\D'), '') == chaveIni) {
              inicial = n;
              break;
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _notas = notas;
        _carregando = false;
      });
      if (inicial != null) {
        await _selecionarNota(inicial);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      LanApiFeedback.snackErro(
        context,
        e,
        prefixo: 'Falha ao carregar NF-e de compra',
      );
    }
  }

  Future<void> _selecionarNota(NfeImportadaRegistro nota) async {
    if (_terminalLeve &&
        !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      return;
    }
    setState(() {
      _selecionada = nota;
      _linhas = const [];
      _historico = const [];
      _carregandoLinhas = true;
    });
    try {
      List<DevolucaoFornecedorLinha> linhas;
      List<DevolucaoFornecedorFiscalRegistro> historico;
      if (_terminalLeve) {
        final repo = _repoRemoto;
        if (repo == null) {
          throw StateError('Repositorio remoto de NF-e indisponivel.');
        }
        final r = await repo.obterDevolucaoFornecedorRemoto(nota.id);
        linhas = r.linhas;
        historico = r.historico;
      } else {
        linhas = _svc.carregarLinhas(nota.chaveAcesso);
        historico = _svc.listarHistoricoPorChave(nota.chaveAcesso);
      }
      if (!mounted) return;
      setState(() {
        _linhas = linhas;
        _historico = historico;
        _carregandoLinhas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregandoLinhas = false);
      LanApiFeedback.snackErro(
        context,
        e,
        prefixo: 'Falha ao carregar itens da devolucao',
      );
    }
  }

  List<NfeImportadaRegistro> get _notasFiltradas {
    final t = _buscaCtrl.text.trim().toLowerCase();
    if (t.isEmpty) return _notas;
    final dig = t.replaceAll(RegExp(r'\D'), '');
    return _notas.where((r) {
      if (dig.length >= 3 &&
          (r.chaveAcesso.contains(dig) ||
              r.cnpjFornecedor.replaceAll(RegExp(r'\D'), '').contains(dig))) {
        return true;
      }
      return r.nomeFornecedor.toLowerCase().contains(t) ||
          r.numeroNota.toString().contains(t);
    }).toList();
  }

  Future<void> _aplicarXmlEspelho(String xml) async {
    if (_selecionada == null || _linhas.isEmpty) return;
    try {
      final res = DevolucaoFornecedorFiscalService.aplicarEspelhoXml(
        xmlTexto: xml,
        linhas: _linhas,
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.mensagemResumo),
          backgroundColor: res.teveMatch
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
        ),
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('XML do espelho invalido: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao aplicar espelho: $e')),
      );
    }
  }

  Future<void> _importarXmlEspelhoArquivo() async {
    if (_selecionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione antes a NF-e de compra.')),
      );
      return;
    }
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xml'],
      dialogTitle: 'XML do espelho da fabrica',
    );
    if (pick == null || pick.files.isEmpty) return;
    final path = pick.files.single.path;
    if (path == null || path.isEmpty) return;
    final xml = await File(path).readAsString();
    await _aplicarXmlEspelho(xml);
  }

  Future<void> _colarXmlEspelho() async {
    if (_selecionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione antes a NF-e de compra.')),
      );
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final texto = data?.text?.trim() ?? '';
    if (texto.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Area de transferencia vazia.')),
      );
      return;
    }
    if (!texto.contains('<') ||
        (!texto.toLowerCase().contains('infnfe') &&
            !texto.toLowerCase().contains('nfe'))) {
      if (!mounted) return;
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Colar XML do espelho?'),
          content: const Text(
            'O texto colado nao parece um XML de NF-e. '
            'Deseja tentar aplicar mesmo assim?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tentar'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
    }
    await _aplicarXmlEspelho(texto);
  }

  Future<void> _colarXmlDialogo() async {
    if (_selecionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione antes a NF-e de compra.')),
      );
      return;
    }
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Colar XML do espelho'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: ctrl,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: 'Cole aqui o XML enviado pela fabrica…',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    final texto = ctrl.text.trim();
    ctrl.dispose();
    if (ok == true && texto.isNotEmpty) {
      await _aplicarXmlEspelho(texto);
    }
  }

  Future<void> _editarEspelho(DevolucaoFornecedorLinha linha) async {
    final e = linha.espelho.copy();
    final cfopCtrl = TextEditingController(text: e.cfop);
    final unitCtrl = TextEditingController(
      text: e.valorUnitario.toStringAsFixed(2).replaceAll('.', ','),
    );
    final cstCtrl = TextEditingController(text: e.icmsSituacaoTributaria);
    final aliqCtrl = TextEditingController(
      text: e.icmsAliquota.toStringAsFixed(2).replaceAll('.', ','),
    );
    final bcCtrl = TextEditingController(
      text: e.icmsBaseCalculo.toStringAsFixed(2).replaceAll('.', ','),
    );
    final vicmsCtrl = TextEditingController(
      text: e.icmsValor.toStringAsFixed(2).replaceAll('.', ','),
    );
    final bcStCtrl = TextEditingController(
      text: e.icmsBaseCalculoSt.toStringAsFixed(2).replaceAll('.', ','),
    );
    final vStCtrl = TextEditingController(
      text: e.icmsValorSt.toStringAsFixed(2).replaceAll('.', ','),
    );
    final ipiCtrl = TextEditingController(
      text: e.ipiValor.toStringAsFixed(2).replaceAll('.', ','),
    );

    double parseBr(String s) =>
        double.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.')) ??
        double.tryParse(s.trim().replaceAll(',', '.')) ??
        0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Espelho da fabrica'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ProdutoNomeExibicao.paraImpressao(linha.produto),
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                if (e.cfopCompraOrigem.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'CFOP da compra: ${e.cfopCompraOrigem}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Digite os valores exatamente como no espelho enviado '
                  'pela fabrica. A quantidade ainda e definida na lista.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cfopCtrl,
                  decoration: const InputDecoration(
                    labelText: 'CFOP (saida)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Valor unitario',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cstCtrl,
                  decoration: const InputDecoration(
                    labelText: 'CST / CSOSN ICMS',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: aliqCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Aliquota %',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: bcCtrl,
                        decoration: const InputDecoration(
                          labelText: 'BC ICMS',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: vicmsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Valor ICMS',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: bcStCtrl,
                        decoration: const InputDecoration(
                          labelText: 'BC ICMS ST',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: vStCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Valor ICMS ST',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ipiCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Valor IPI',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aplicar espelho'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      setState(() {
        linha.espelho.cfop = cfopCtrl.text.trim();
        linha.espelho.valorUnitario = parseBr(unitCtrl.text);
        linha.espelho.icmsSituacaoTributaria = cstCtrl.text.trim();
        linha.espelho.icmsAliquota = parseBr(aliqCtrl.text);
        linha.espelho.icmsBaseCalculo = parseBr(bcCtrl.text);
        linha.espelho.icmsValor = parseBr(vicmsCtrl.text);
        linha.espelho.icmsBaseCalculoSt = parseBr(bcStCtrl.text);
        linha.espelho.icmsValorSt = parseBr(vStCtrl.text);
        linha.espelho.ipiValor = parseBr(ipiCtrl.text);
      });
    }

    cfopCtrl.dispose();
    unitCtrl.dispose();
    cstCtrl.dispose();
    aliqCtrl.dispose();
    bcCtrl.dispose();
    vicmsCtrl.dispose();
    bcStCtrl.dispose();
    vStCtrl.dispose();
    ipiCtrl.dispose();
  }

  Future<void> _emitir() async {
    final nota = _selecionada;
    if (nota == null) return;
    if (_terminalLeve) {
      if (!LanApiEventHub.instance.garantirOnlineOuAvisar(context)) return;
    } else if (!(ConfiguracoesService.tryGlobal?.fiscalEmCache.configurado ??
        false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configure o Focus NFe em Configuracoes.'),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Emitir devolucao ao fornecedor?'),
        content: Text(
          'Sera emitida NF-e de saida (finalidade 4) com os valores do espelho '
          '(CFOP, unitario e impostos que voce conferiu), referenciando a NF '
          '${nota.numeroNota > 0 ? "#${nota.numeroNota}" : "de compra"}.\n\n'
          'Se autorizada, o estoque sera baixado'
          '${_terminalLeve ? ' no PC servidor' : ''}. '
          'Se ficar processando, reconsulte no historico desta tela.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Emitir NF-e'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _emitindo = true);
    try {
      final idsBaixa = <int>[
        for (final l in _linhas)
          if (l.quantidade > 0 && l.produto.id > 0) l.produto.id,
      ];
      final DevolucaoFornecedorOperacaoResultado res;
      if (_terminalLeve) {
        final repo = _repoRemoto;
        if (repo == null) {
          throw StateError('Repositorio remoto de NF-e indisponivel.');
        }
        res = await repo.emitirDevolucaoRemoto(
          importacaoId: nota.id,
          motivo: _motivoCtrl.text,
          linhas: _linhas,
        );
      } else {
        res = await _svc.emitir(
          chaveNotaCompra: nota.chaveAcesso,
          linhasSelecionadas: _linhas,
          motivo: _motivoCtrl.text,
        );
      }
      if (!mounted) return;
      setState(() => _emitindo = false);
      if (res.sucesso) {
        try {
          final prodRepo = widget.produtoRepository;
          if (prodRepo is ProdutoApiRepository && idsBaixa.isNotEmpty) {
            await prodRepo.atualizarEstoquePorIds(idsBaixa);
          } else {
            prodRepo.invalidarCacheBusca();
          }
        } catch (_) {}
        await _selecionarNota(nota);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.mensagem),
          backgroundColor: res.sucesso
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
        ),
      );

      if (res.sucesso && res.urlDanfe.trim().isNotEmpty) {
        final uri = Uri.tryParse(res.urlDanfe.trim());
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _emitindo = false);
      LanApiFeedback.snackErro(context, e, prefixo: 'Falha ao emitir devolucao');
    }
  }

  Future<void> _atualizarEstoqueLocal(List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      final prodRepo = widget.produtoRepository;
      if (prodRepo is ProdutoApiRepository) {
        await prodRepo.atualizarEstoquePorIds(ids);
      } else {
        prodRepo.invalidarCacheBusca();
      }
    } catch (_) {}
  }

  Future<void> _reconsultarUma(DevolucaoFornecedorFiscalRegistro reg) async {
    if (_reconsultando) return;
    if (_terminalLeve &&
        !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      return;
    }
    setState(() => _reconsultando = true);
    try {
      final DevolucaoFornecedorReconsultaResultado res;
      if (_terminalLeve) {
        final repo = _repoRemoto;
        if (repo == null) {
          throw StateError('Repositorio remoto de NF-e indisponivel.');
        }
        res = await repo.reconsultarDevolucaoRemoto(reg.referenciaFocus);
      } else {
        res = await _svc.reconsultar(reg.referenciaFocus);
      }
      if (!mounted) return;
      setState(() => _reconsultando = false);
      await _atualizarEstoqueLocal(res.produtoIds);
      final nota = _selecionada;
      if (nota != null) await _selecionarNota(nota);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.sucesso
                ? (res.mensagem.isNotEmpty
                    ? res.mensagem
                    : 'Status atualizado.')
                : res.mensagem,
          ),
          backgroundColor: res.sucesso
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _reconsultando = false);
      LanApiFeedback.snackErro(context, e, prefixo: 'Falha na reconsulta');
    }
  }

  Future<void> _reconsultarPendentes({bool silencioso = false}) async {
    if (_reconsultando) return;
    if (_terminalLeve) {
      if (!LanApiEventHub.instance.online) return;
      if (!silencioso &&
          !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
        return;
      }
    } else if (!(ConfiguracoesService.tryGlobal?.fiscalEmCache.configurado ??
        false)) {
      return;
    }
    setState(() => _reconsultando = true);
    try {
      final DevolucaoFornecedorReconsultaLote lote;
      if (_terminalLeve) {
        final repo = _repoRemoto;
        if (repo == null) {
          setState(() => _reconsultando = false);
          return;
        }
        lote = await repo.reconsultarDevolucaoProcessandoRemoto();
      } else {
        lote = await _svc.reconsultarPendentes();
      }
      if (!mounted) return;
      setState(() => _reconsultando = false);
      await _atualizarEstoqueLocal(lote.produtoIds);
      final nota = _selecionada;
      if (nota != null) {
        await _selecionarNota(nota);
      }
      if (!mounted || silencioso) return;
      final msg = lote.total == 0
          ? 'Nenhuma devolucao aguardando autorizacao.'
          : lote.autorizadas > 0
              ? '${lote.autorizadas} nota(s) autorizada(s)'
                  '${lote.estoqueBaixado > 0 ? " · estoque baixado" : ""}.'
              : 'Nenhuma autorizacao nova (${lote.total} consultada(s)).';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _reconsultando = false);
      if (!silencioso) {
        LanApiFeedback.snackErro(context, e, prefixo: 'Falha na reconsulta');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                SizedBox(
                  width: 360,
                  child: Material(
                    color: theme.colorScheme.surfaceContainerLowest,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(
                            'NF-e de compra',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: TextField(
                            controller: _buscaCtrl,
                            decoration: const InputDecoration(
                              hintText: 'Buscar fornecedor, NF ou chave',
                              prefixIcon: Icon(Icons.search),
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _notasFiltradas.isEmpty
                              ? Center(
                                  child: Text(
                                    'Nenhuma NF-e importada.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _notasFiltradas.length,
                                  itemBuilder: (context, i) {
                                    final n = _notasFiltradas[i];
                                    final sel = _selecionada?.id == n.id;
                                    return ListTile(
                                      selected: sel,
                                      title: Text(
                                        n.nomeFornecedor.trim().isEmpty
                                            ? 'Fornecedor'
                                            : n.nomeFornecedor,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        'NF ${n.numeroNota > 0 ? n.numeroNota : "—"} · '
                                        '${_data.format(n.dataEmissao.toLocal())}',
                                      ),
                                      onTap: () => _selecionarNota(n),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _buildPainelDireito(theme)),
              ],
            ),
    );
  }

  Widget _buildPainelDireito(ThemeData theme) {
    final nota = _selecionada;
    if (nota == null) {
      return Center(
        child: Text(
          'Selecione uma NF-e de compra. Depois ajuste o espelho '
          'conforme a fabrica enviou e emita.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (_carregandoLinhas) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalSel = _linhas.fold<double>(
      0,
      (s, l) => s + (l.quantidade * l.espelho.valorUnitario),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Devolucao ao fornecedor / fabrica',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${nota.nomeFornecedor} · NF ${nota.numeroNota > 0 ? "#${nota.numeroNota}" : "—"}',
                style: theme.textTheme.bodyMedium,
              ),
              SelectableText(
                'Chave ${nota.chaveAcesso}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Importe o XML do espelho que a fabrica mandou (ou cole o texto). '
                'O sistema preenche CFOP, qtd, unitario e impostos. '
                'Ainda da para ajustar item a item em "Espelho".',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _linhas.isEmpty ? null : _importarXmlEspelhoArquivo,
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('Importar XML do espelho'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _linhas.isEmpty ? null : _colarXmlEspelho,
                    icon: const Icon(Icons.content_paste_outlined, size: 18),
                    label: const Text('Colar da area de transferencia'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _linhas.isEmpty ? null : _colarXmlDialogo,
                    icon: const Icon(Icons.notes_outlined, size: 18),
                    label: const Text('Colar texto…'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _reconsultando
                        ? null
                        : () => unawaited(_reconsultarPendentes()),
                    icon: _reconsultando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: const Text('Reconsultar pendentes'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _motivoCtrl,
            decoration: const InputDecoration(
              labelText: 'Motivo / informacoes adicionais',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
        ),
        if (_historico.isNotEmpty) _buildHistorico(theme),
        const SizedBox(height: 8),
        Expanded(
          child: _linhas.isEmpty
              ? Center(
                  child: Text(
                    'Nenhum item disponivel para devolucao nesta NF '
                    '(ja devolvido ou sem vinculo de produto).',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _linhas.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final l = _linhas[i];
                    return ListTile(
                      isThreeLine: true,
                      title: Text(
                        ProdutoNomeExibicao.paraImpressao(l.produto),
                      ),
                      subtitle: Text(
                        'Unit. ${_moeda.format(l.espelho.valorUnitario)} · '
                        'CFOP ${l.espelho.cfop.isEmpty ? "—" : l.espelho.cfop}'
                        '${l.espelho.icmsSituacaoTributaria.isEmpty ? "" : " · CST ${l.espelho.icmsSituacaoTributaria}"}'
                        '${l.espelho.icmsValor > 0 ? " · ICMS ${_moeda.format(l.espelho.icmsValor)}" : ""}\n'
                        'Disponivel ${l.quantidadeMaxima}'
                        '${l.espelho.cfopCompraOrigem.isEmpty ? "" : " · compra CFOP ${l.espelho.cfopCompraOrigem}"}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _editarEspelho(l),
                            child: const Text('Espelho'),
                          ),
                          SizedBox(
                            width: 88,
                            child: TextFormField(
                              key: ValueKey(
                                'qtd-${l.historico.id}-${l.quantidade}',
                              ),
                              initialValue:
                                  l.quantidade > 0 ? '${l.quantidade}' : '',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Qtd',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) {
                                final q = int.tryParse(v) ?? 0;
                                setState(() => l.aplicarQuantidade(q));
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Material(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Total estimado: ${_moeda.format(totalSel)}'
                    '${_linhas.any((l) => l.quantidade > 0) ? " · ${_num.format(_linhas.fold<int>(0, (s, l) => s + l.quantidade))} un" : ""}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _emitindo ||
                          _linhas.every((l) => l.quantidade <= 0)
                      ? null
                      : _emitir,
                  icon: _emitindo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.undo_outlined),
                  label: Text(_emitindo ? 'Emitindo…' : 'Emitir NF-e'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistorico(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            itemCount: _historico.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 12),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Text(
                  'Emissoes desta NF',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                );
              }
              final r = _historico[i - 1];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${r.rotuloStatus}'
                          '${r.numero.isNotEmpty ? " · NF-e ${r.numero}" : ""}'
                          '${r.estoqueBaixado ? " · estoque baixado" : ""}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _dataHora.format(r.emitidaEm.toLocal()),
                          style: theme.textTheme.bodySmall,
                        ),
                        if (r.referenciaFocus.isNotEmpty)
                          Text(
                            r.referenciaFocus,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (r.urlDanfe.trim().isNotEmpty)
                    IconButton(
                      tooltip: 'Abrir DANFE',
                      onPressed: () => abrirUrlDocumentoFiscal(
                        context,
                        r.urlDanfe,
                        mensagemSeVazio: 'DANFE indisponivel.',
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                    ),
                  if (r.pendenteReconsulta)
                    TextButton(
                      onPressed: _reconsultando
                          ? null
                          : () => unawaited(_reconsultarUma(r)),
                      child: const Text('Reconsultar'),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
