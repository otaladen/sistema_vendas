import 'dart:async';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/api/lan_api_event_hub.dart';
import '../data/api/nfe_importada_api_repository.dart';
import '../data/api/produto_api_repository.dart';
import '../data/nfe_entrada_repository.dart';
import '../data/sync/sync_refresh_hub.dart';
import '../model/historico_entrada.dart';
import '../model/nfe_importada_registro.dart';
import 'fiscal/nfe_devolucao_fornecedor_page.dart';
import 'shell/main_menu_deps.dart';
import 'widgets/lan_api_feedback.dart';

/// Log de NF-e importadas por XML: KPIs, filtros, ordenacao, detalhe e exportacao CSV.
/// Terminal Leve: 100% via API :8788 ([NfeImportadaApiRepository]).
/// PC servidor: ObjectBox local ([NfeEntradaRepository]).
class NfeImportadasPage extends StatefulWidget {
  const NfeImportadasPage({
    super.key,
    required this.produtoRepository,
    this.nfeImportadaRepository,
  });

  final dynamic produtoRepository;
  /// [NfeImportadaApiRepository] no Terminal Leve; null no PC1.
  final dynamic nfeImportadaRepository;

  @override
  State<NfeImportadasPage> createState() => _NfeImportadasPageState();
}

enum _OrdenacaoNfe {
  importacaoDesc,
  importacaoAsc,
  emissaoDesc,
  emissaoAsc,
  fornecedorAsc,
  numeroNotaDesc,
  itensDesc,
}

enum _BaseDataFiltro { importacao, emissao }

extension _OrdenacaoNfeRotulo on _OrdenacaoNfe {
  String get rotulo {
    switch (this) {
      case _OrdenacaoNfe.importacaoDesc:
        return 'Importacao (mais recente)';
      case _OrdenacaoNfe.importacaoAsc:
        return 'Importacao (mais antiga)';
      case _OrdenacaoNfe.emissaoDesc:
        return 'Emissao da NF (mais recente)';
      case _OrdenacaoNfe.emissaoAsc:
        return 'Emissao da NF (mais antiga)';
      case _OrdenacaoNfe.fornecedorAsc:
        return 'Fornecedor (A-Z)';
      case _OrdenacaoNfe.numeroNotaDesc:
        return 'Numero da NF (maior primeiro)';
      case _OrdenacaoNfe.itensDesc:
        return 'Quantidade de itens';
    }
  }

  String get apiValue => name;
}

class _NfeImportadasPageState extends State<NfeImportadasPage> {
  static final _nfData = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  static final _nfDataS = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final _nfDataCurta = DateFormat('dd/MM HH:mm', 'pt_BR');

  final TextEditingController _buscaCtrl = TextEditingController();

  List<NfeImportadaRegistro> _todos = const [];
  _OrdenacaoNfe _ordenacao = _OrdenacaoNfe.importacaoDesc;
  _BaseDataFiltro _baseDataFiltro = _BaseDataFiltro.importacao;
  DateTimeRange? _periodo;

  /// Meta dos cards quando a listagem veio filtrada da API.
  int? _metaTotalNotas;
  int? _metaFornecedores;
  DateTime? _metaUltimaImportacao;

  Timer? _debounceBusca;
  bool _carregando = false;
  VoidCallback? _syncHubListener;
  bool? _apiOnlineAnterior;

  bool get _terminalLeve =>
      MainMenuDeps.maybeOf(context)?.terminalLeve == true;

  dynamic get _repoRemoto {
    final inj = widget.nfeImportadaRepository;
    if (inj != null) return inj;
    return MainMenuDeps.maybeOf(context)?.nfeImportadaRepository;
  }

  @override
  void initState() {
    super.initState();
    _buscaCtrl.addListener(_onBuscaChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_terminalLeve) {
        _apiOnlineAnterior = LanApiEventHub.instance.online;
        LanApiEventHub.instance.addListener(_onLanApiEvento);
      } else {
        _syncHubListener = () {
          if (mounted) _recarregarDados();
        };
        SyncRefreshHub.instance.addListener(_syncHubListener!);
      }
      _recarregarDados();
    });
  }

  void _onBuscaChanged() {
    setState(() {});
    if (!_terminalLeve) return;
    _debounceBusca?.cancel();
    _debounceBusca = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _recarregarDados();
    });
  }

  void _onLanApiEvento() {
    if (!_terminalLeve) return;
    final hub = LanApiEventHub.instance;
    final online = hub.online;
    final ficouOnline = online && _apiOnlineAnterior == false;
    _apiOnlineAnterior = online;
    if (hub.deveBloquearOperacoes) return;
    if (!ficouOnline && hub.ultimaEntidade != 'nfe_importada') return;
    _recarregarDados();
  }

  @override
  void dispose() {
    _debounceBusca?.cancel();
    _buscaCtrl.removeListener(_onBuscaChanged);
    _buscaCtrl.dispose();
    LanApiEventHub.instance.removeListener(_onLanApiEvento);
    if (_syncHubListener != null) {
      SyncRefreshHub.instance.removeListener(_syncHubListener!);
      _syncHubListener = null;
    }
    super.dispose();
  }

  void _recarregarDados() {
    unawaited(_recarregarDadosAsync());
  }

  Future<void> _recarregarDadosAsync() async {
    setState(() => _carregando = true);
    try {
      if (_terminalLeve) {
        final repo = _repoRemoto;
        if (repo == null) {
          throw StateError('Repositorio remoto de NF-e importadas indisponivel.');
        }
        final result = await repo.listarImportadasRemoto(
          q: _buscaCtrl.text.trim(),
          tipoData: _baseDataFiltro == _BaseDataFiltro.importacao
              ? 'importacao'
              : 'emissao',
          periodoInicio: _periodo?.start,
          periodoFim: _periodo?.end,
          ordenacao: _ordenacao.apiValue,
        ) as NfeImportadasListagemRemota;
        if (!mounted) return;
        setState(() {
          _todos = result.items;
          _metaTotalNotas = result.totalNotas;
          _metaFornecedores = result.fornecedoresDistintos;
          _metaUltimaImportacao = result.ultimaImportacao;
          _carregando = false;
        });
        return;
      }
      final local = NfeEntradaRepository(widget.produtoRepository.objectBox);
      if (!mounted) return;
      setState(() {
        _todos = local.listarImportacoesNfeDesc();
        _metaTotalNotas = null;
        _metaFornecedores = null;
        _metaUltimaImportacao = null;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      LanApiFeedback.snackErro(
        context,
        e,
        prefixo: 'Falha ao carregar NF-e importadas',
      );
    }
  }

  DateTime _soDataLocal(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  bool _dentroDoPeriodo(NfeImportadaRegistro r) {
    if (_periodo == null) return true;
    final alvo = _baseDataFiltro == _BaseDataFiltro.importacao
        ? r.dataHoraImportacao
        : r.dataEmissao;
    final d = _soDataLocal(alvo);
    final ini = _soDataLocal(_periodo!.start);
    final fim = _soDataLocal(_periodo!.end);
    return !d.isBefore(ini) && !d.isAfter(fim);
  }

  bool _passaBusca(NfeImportadaRegistro r) {
    final t = _buscaCtrl.text.trim().toLowerCase();
    if (t.isEmpty) return true;
    final soDig = t.replaceAll(RegExp(r'\D'), '');
    if (soDig.length >= 3) {
      if (r.chaveAcesso.contains(soDig)) return true;
      final cnpjLimpo = r.cnpjFornecedor.replaceAll(RegExp(r'\D'), '');
      if (cnpjLimpo.contains(soDig)) return true;
    }
    if (r.nomeFornecedor.toLowerCase().contains(t)) return true;
    if (r.cnpjFornecedor.toLowerCase().contains(t)) return true;
    if (r.numeroNota > 0 && r.numeroNota.toString().contains(t)) return true;
    if (r.chaveAcesso.toLowerCase().contains(t)) return true;
    return false;
  }

  /// No Terminal Leve a API ja filtra/ordena; no PC1 filtramos localmente.
  List<NfeImportadaRegistro> get _filtrados {
    if (_terminalLeve) return _todos;
    return _todos.where((r) => _dentroDoPeriodo(r) && _passaBusca(r)).toList();
  }

  List<NfeImportadaRegistro> get _listaExibicao {
    if (_terminalLeve) return _filtrados;
    final l = List<NfeImportadaRegistro>.from(_filtrados);
    int cmpStr(String a, String b) =>
        a.toLowerCase().trim().compareTo(b.toLowerCase().trim());
    switch (_ordenacao) {
      case _OrdenacaoNfe.importacaoDesc:
        l.sort((a, b) => b.dataHoraImportacao.compareTo(a.dataHoraImportacao));
        break;
      case _OrdenacaoNfe.importacaoAsc:
        l.sort((a, b) => a.dataHoraImportacao.compareTo(b.dataHoraImportacao));
        break;
      case _OrdenacaoNfe.emissaoDesc:
        l.sort((a, b) => b.dataEmissao.compareTo(a.dataEmissao));
        break;
      case _OrdenacaoNfe.emissaoAsc:
        l.sort((a, b) => a.dataEmissao.compareTo(b.dataEmissao));
        break;
      case _OrdenacaoNfe.fornecedorAsc:
        l.sort(
          (a, b) => cmpStr(
            a.nomeFornecedor.isEmpty ? 'ZZZ' : a.nomeFornecedor,
            b.nomeFornecedor.isEmpty ? 'ZZZ' : b.nomeFornecedor,
          ),
        );
        break;
      case _OrdenacaoNfe.numeroNotaDesc:
        l.sort((a, b) => b.numeroNota.compareTo(a.numeroNota));
        break;
      case _OrdenacaoNfe.itensDesc:
        l.sort((a, b) => b.quantidadeItens.compareTo(a.quantidadeItens));
        break;
    }
    return l;
  }

  int _fornecedoresDistintos(Iterable<NfeImportadaRegistro> it) {
    if (_terminalLeve && _metaFornecedores != null) return _metaFornecedores!;
    final set = <String>{};
    for (final r in it) {
      final c = r.cnpjFornecedor.replaceAll(RegExp(r'\D'), '');
      if (c.isNotEmpty) {
        set.add(c);
      } else {
        final n = r.nomeFornecedor.trim().toLowerCase();
        if (n.isNotEmpty) set.add('n:$n');
      }
    }
    return set.length;
  }

  String? _ultimaImportacaoTexto(Iterable<NfeImportadaRegistro> it) {
    DateTime? max = _terminalLeve ? _metaUltimaImportacao : null;
    if (max == null) {
      for (final r in it) {
        if (max == null || r.dataHoraImportacao.isAfter(max)) {
          max = r.dataHoraImportacao;
        }
      }
    }
    if (max == null) return null;
    return _nfDataCurta.format(max.toLocal());
  }

  int _kpiTotalNotas(List<NfeImportadaRegistro> filtrados) {
    if (_terminalLeve && _metaTotalNotas != null) return _metaTotalNotas!;
    return filtrados.length;
  }

  Future<void> _escolherPeriodo() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 15),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _periodo,
      helpText: _baseDataFiltro == _BaseDataFiltro.importacao
          ? 'Filtrar por data de importacao'
          : 'Filtrar por data de emissao da NF',
    );
    if (picked != null) {
      setState(() => _periodo = picked);
      if (_terminalLeve) _recarregarDados();
    }
  }

  Future<void> _exportarCsvLeitura() async {
    final lista = _listaExibicao;
    if (lista.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nada para exportar com os filtros atuais.')),
      );
      return;
    }
    final rows = <List<dynamic>>[
      [
        'chave_acesso',
        'numero_nota',
        'data_emissao',
        'fornecedor',
        'cnpj',
        'data_importacao',
        'itens',
      ],
      for (final r in lista)
        [
          r.chaveAcesso,
          r.numeroNota,
          _nfDataS.format(r.dataEmissao.toLocal()),
          r.nomeFornecedor,
          r.cnpjFornecedor,
          _nfData.format(r.dataHoraImportacao.toLocal()),
          r.quantidadeItens,
        ],
    ];
    final conteudo = csv.encode(rows);
    final nomeArquivo =
        'nfe_importadas_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar lista de NF-e importadas',
      fileName: nomeArquivo,
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (selectedPath == null) return;
    final path = selectedPath.toLowerCase().endsWith('.csv')
        ? selectedPath
        : '$selectedPath.csv';
    final file = File(path);
    await file.writeAsString(conteudo, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('CSV salvo: $path')),
    );
  }

  void _copiar(String label, String valor) {
    if (valor.isEmpty) return;
    Clipboard.setData(ClipboardData(text: valor));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado.')),
    );
  }

  void _abrirDevolucaoFornecedor(NfeImportadaRegistro r) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NfeDevolucaoFornecedorPage(
          produtoRepository: widget.produtoRepository,
          nfeImportadaRepository: widget.nfeImportadaRepository ??
              MainMenuDeps.maybeOf(context)?.nfeImportadaRepository,
          chaveNotaInicial: r.chaveAcesso,
        ),
      ),
    );
  }

  Future<void> _baixarXml(NfeImportadaRegistro r) async {
    try {
      if (_terminalLeve) {
        final repo = _repoRemoto;
        if (repo == null) {
          throw StateError('Repositorio remoto indisponivel.');
        }
        final arquivo = await repo.baixarXmlRemoto(r.id)
            as ({List<int> bytes, String filename});
        final selectedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Salvar XML da NF-e',
          fileName: arquivo.filename,
          type: FileType.custom,
          allowedExtensions: const ['xml'],
        );
        if (selectedPath == null) return;
        final path = selectedPath.toLowerCase().endsWith('.xml')
            ? selectedPath
            : '$selectedPath.xml';
        await File(path).writeAsBytes(arquivo.bytes, flush: true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('XML salvo: $path')),
        );
        return;
      }
      final local = NfeEntradaRepository(widget.produtoRepository.objectBox);
      final xml = local.lerXmlImportacao(r.chaveAcesso);
      if (xml == null || xml.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('XML nao encontrado no disco local.')),
        );
        return;
      }
      final chave = r.chaveAcesso.replaceAll(RegExp(r'\D'), '');
      final selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar XML da NF-e',
        fileName: 'nfe_$chave.xml',
        type: FileType.custom,
        allowedExtensions: const ['xml'],
      );
      if (selectedPath == null) return;
      final path = selectedPath.toLowerCase().endsWith('.xml')
          ? selectedPath
          : '$selectedPath.xml';
      await File(path).writeAsString(xml, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('XML salvo: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Falha ao baixar XML');
    }
  }

  Future<void> _confirmarEstornoImportacao(
    BuildContext sheetContext,
    NfeImportadaRegistro r,
  ) async {
    final nfLabel = r.numeroNota > 0 ? 'NF #${r.numeroNota}' : 'esta NF-e';
    final fornecedor = r.nomeFornecedor.trim().isEmpty
        ? 'fornecedor nao informado'
        : r.nomeFornecedor;

    ValidacaoEstornoNfe validacao;
    var qtdContasPagar = 0;

    if (_terminalLeve) {
      final api = _repoRemoto;
      if (api is! NfeImportadaApiRepository) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Repositorio remoto de NF-e indisponivel.'),
          ),
        );
        return;
      }
      try {
        final preview = await api.validarEstornoRemoto(r.id);
        validacao = preview.validacao;
        qtdContasPagar = preview.qtdContasPagar;
      } catch (e) {
        if (!mounted) return;
        LanApiFeedback.snackErro(
          context,
          e,
          prefixo: 'Falha ao validar estorno',
        );
        return;
      }
    } else {
      final repo = NfeEntradaRepository(widget.produtoRepository.objectBox);
      validacao = repo.validarEstornoImportacao(r.id);
      qtdContasPagar =
          repo.listarContasPagarPorChaveNfe(r.chaveAcesso).length;
    }

    if (!mounted) return;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final erro = Theme.of(ctx).colorScheme.error;
        return AlertDialog(
          title: const Text('Estornar importacao?'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$nfLabel ($fornecedor) sera desfeita.\n\n'
                  'O estoque e o custo medio das entradas abaixo voltam atras'
                  '${qtdContasPagar > 0 ? ', $qtdContasPagar titulo(s) no '
                      'Contas a Pagar serao removidos' : ''} '
                  'e a chave fica livre para importar o XML de novo.',
                ),
                if (!validacao.podeEstornar) ...[
                  const SizedBox(height: 12),
                  Text(
                    validacao.motivoBloqueio ?? 'Estorno bloqueado.',
                    style: TextStyle(color: erro, fontWeight: FontWeight.w600),
                  ),
                ] else if (validacao.linhas.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Reversao de estoque:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  ...validacao.linhas.map(
                    (l) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• ${l.nomeProduto}: −${l.rotuloEstorno} '
                        '(fisico atual ${l.rotuloEstoqueAtual})',
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Nao ha lancamentos de historico; apenas o registro da '
                    'importacao sera removido.',
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: erro,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: validacao.podeEstornar
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Estornar entrada'),
            ),
          ],
        );
      },
    );

    if (confirmou != true || !mounted) return;

    try {
      if (_terminalLeve) {
        final api = _repoRemoto;
        if (api is! NfeImportadaApiRepository) {
          throw StateError('Repositorio remoto de NF-e indisponivel.');
        }
        final m = await api.estornarEntradaRemoto(r.id);
        try {
          final idsRaw = m['produtoIds'];
          final ids = idsRaw is List
              ? idsRaw
                  .map((e) => (e as num?)?.toInt() ?? 0)
                  .where((id) => id > 0)
                  .toList()
              : <int>[];
          final prodRepo = widget.produtoRepository;
          if (prodRepo is ProdutoApiRepository) {
            if (ids.isNotEmpty) {
              await prodRepo.atualizarEstoquePorIds(ids);
            } else {
              prodRepo.invalidarCacheBusca();
            }
          } else {
            prodRepo.invalidarCacheBusca();
          }
        } catch (_) {}
        if (sheetContext.mounted) {
          Navigator.pop(sheetContext);
        }
        _recarregarDados();
        if (!mounted) return;
        final msg = (m['mensagem'] ?? '').toString().trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              msg.isNotEmpty
                  ? msg
                  : 'Importacao estornada. Estoque revertido; a nota pode '
                      'ser importada de novo.',
            ),
          ),
        );
      } else {
        final repo = NfeEntradaRepository(widget.produtoRepository.objectBox);
        repo.estornarImportacaoNfe(r.id);
        widget.produtoRepository.invalidarCacheBusca();
        if (sheetContext.mounted) {
          Navigator.pop(sheetContext);
        }
        _recarregarDados();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              qtdContasPagar > 0
                  ? 'Importacao estornada. Estoque revertido e '
                      '$qtdContasPagar titulo(s) a pagar removido(s).'
                  : 'Importacao estornada. Estoque revertido; a nota pode '
                      'ser importada de novo.',
            ),
          ),
        );
      }
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(
        context,
        e,
        prefixo: 'Falha ao estornar importacao',
      );
    }
  }

  Future<void> _abrirDetalhe(NfeImportadaRegistro r) async {
    List<_LinhaEspelho> linhas = const [];
    var temXml = false;
    var carregandoItens = _terminalLeve;

    if (!_terminalLeve) {
      try {
        final repo = NfeEntradaRepository(widget.produtoRepository.objectBox);
        final historico = repo.listarHistoricoPorChaveNfe(r.chaveAcesso);
        linhas = historico.map(_LinhaEspelho.deHistorico).toList();
        temXml = repo.lerXmlImportacao(r.chaveAcesso) != null;
      } catch (_) {}
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _DetalheSheet(
          registro: r,
          linhasIniciais: linhas,
          temXmlInicial: temXml,
          carregandoInicial: carregandoItens,
          terminalLeve: _terminalLeve,
          nfData: _nfData,
          nfDataS: _nfDataS,
          onCopiar: _copiar,
          onDevolver: () {
            Navigator.pop(ctx);
            _abrirDevolucaoFornecedor(r);
          },
          onEstornar: () => _confirmarEstornoImportacao(ctx, r),
          onBaixarXml: () => _baixarXml(r),
          carregarRemoto: carregandoItens
              ? () async {
                  final repo = _repoRemoto;
                  if (repo == null) {
                    throw StateError('Repositorio remoto indisponivel.');
                  }
                  final d = await repo.obterDetalhesRemoto(r.id)
                      as NfeImportadaDetalheRemoto;
                  return (
                    linhas: d.itens
                        .map(_LinhaEspelho.deRemoto)
                        .toList(growable: false),
                    temXml: d.temXml,
                  );
                }
              : null,
        );
      },
    );
  }

  bool get _temFiltrosAtivos =>
      _periodo != null || _buscaCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    final lista = _listaExibicao;
    final ultima = _ultimaImportacaoTexto(filtrados);
    final nForn = _fornecedoresDistintos(filtrados);
    final totalNotas = _kpiTotalNotas(filtrados);
    final tema = Theme.of(context);
    final onVar = tema.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NF-e importadas (XML)'),
        actions: [
          if (_carregando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Exportar CSV (lista filtrada)',
            onPressed: _exportarCsvLeitura,
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: _KpiChip(
                    titulo: 'Notas',
                    valor: totalNotas.toString(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _KpiChip(
                    titulo: 'Ultima import.',
                    valor: ultima ?? '—',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _KpiChip(
                    titulo: 'Fornecedores',
                    valor: nForn.toString(),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<_BaseDataFiltro>(
                  segments: const [
                    ButtonSegment(
                      value: _BaseDataFiltro.importacao,
                      label: Text('Data importacao'),
                    ),
                    ButtonSegment(
                      value: _BaseDataFiltro.emissao,
                      label: Text('Data emissao NF'),
                    ),
                  ],
                  selected: {_baseDataFiltro},
                  onSelectionChanged: (s) {
                    setState(() => _baseDataFiltro = s.first);
                    if (_terminalLeve) _recarregarDados();
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _escolherPeriodo,
                        icon: const Icon(Icons.date_range_outlined, size: 20),
                        label: Text(
                          _periodo == null
                              ? 'Periodo (opcional)'
                              : '${_nfDataS.format(_periodo!.start)} — ${_nfDataS.format(_periodo!.end)}',
                        ),
                      ),
                    ),
                    if (_periodo != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Limpar periodo',
                        onPressed: () {
                          setState(() => _periodo = null);
                          if (_terminalLeve) _recarregarDados();
                        },
                        icon: const Icon(Icons.clear),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _buscaCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Fornecedor, CNPJ, numero NF ou trecho da chave',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _buscaCtrl.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Limpar',
                            onPressed: () {
                              _buscaCtrl.clear();
                              if (_terminalLeve) _recarregarDados();
                            },
                            icon: const Icon(Icons.clear),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Ordenar por',
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<_OrdenacaoNfe>(
                            isExpanded: true,
                            value: _ordenacao,
                            isDense: true,
                            items: _OrdenacaoNfe.values
                                .map(
                                  (o) => DropdownMenuItem(
                                    value: o,
                                    child: Text(
                                      o.rotulo,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _ordenacao = v);
                              if (_terminalLeve) _recarregarDados();
                            },
                          ),
                        ),
                      ),
                    ),
                    if (_temFiltrosAtivos) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _periodo = null;
                            _buscaCtrl.clear();
                          });
                          if (_terminalLeve) _recarregarDados();
                        },
                        child: const Text('Limpar filtros'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _todos.isEmpty && !_carregando
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Ainda nao ha importacoes.\n'
                        'Confirme uma entrada pelo XML em Notas Fiscais.',
                        textAlign: TextAlign.center,
                        style: tema.textTheme.bodyLarge?.copyWith(color: onVar),
                      ),
                    ),
                  )
                : lista.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Nenhum registro com os filtros atuais.',
                            textAlign: TextAlign.center,
                            style:
                                tema.textTheme.bodyLarge?.copyWith(color: onVar),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async => _recarregarDadosAsync(),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: lista.length,
                          separatorBuilder: (context, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final r = lista[i];
                            return Card(
                              child: InkWell(
                                onTap: () => unawaited(_abrirDetalhe(r)),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              r.nomeFornecedor.trim().isEmpty
                                                  ? 'Fornecedor nao informado'
                                                  : r.nomeFornecedor,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            Icons.chevron_right,
                                            color: onVar,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'CNPJ ${r.cnpjFornecedor} · '
                                        'NF ${r.numeroNota > 0 ? "#${r.numeroNota}" : "—"} · '
                                        'Emissao ${_nfDataS.format(r.dataEmissao.toLocal())}',
                                        style: tema.textTheme.bodySmall,
                                      ),
                                      Text(
                                        'Importado ${_nfData.format(r.dataHoraImportacao.toLocal())} · '
                                        '${r.quantidadeItens} item(ns)',
                                        style: tema.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _LinhaEspelho {
  const _LinhaEspelho({
    required this.produtoNome,
    required this.quantidadeFornecedor,
    required this.unidadeFornecedor,
    required this.quantidadeEntradaEstoque,
    required this.fatorConversaoUtilizado,
    this.produtoCodigoInterno = '',
  });

  final String produtoNome;
  final String produtoCodigoInterno;
  final double quantidadeFornecedor;
  final String unidadeFornecedor;
  final double quantidadeEntradaEstoque;
  final double fatorConversaoUtilizado;

  factory _LinhaEspelho.deHistorico(HistoricoEntrada h) {
    final prod = h.produto.target;
    final nome = prod?.nome.trim().isNotEmpty == true
        ? prod!.nome
        : (prod?.descricao ?? 'Produto');
    return _LinhaEspelho(
      produtoNome: nome,
      produtoCodigoInterno: prod?.codigoInterno ?? '',
      quantidadeFornecedor: h.quantidadeFornecedor,
      unidadeFornecedor: h.unidadeFornecedor,
      quantidadeEntradaEstoque: h.quantidadeEntradaEstoque.toDouble(),
      fatorConversaoUtilizado: h.fatorConversaoUtilizado,
    );
  }

  factory _LinhaEspelho.deRemoto(NfeImportadaLinhaRemota l) => _LinhaEspelho(
        produtoNome: l.produtoNome,
        produtoCodigoInterno: l.produtoCodigoInterno,
        quantidadeFornecedor: l.quantidadeFornecedor,
        unidadeFornecedor: l.unidadeFornecedor,
        quantidadeEntradaEstoque: l.quantidadeEntradaEstoque,
        fatorConversaoUtilizado: l.fatorConversaoUtilizado,
      );
}

class _DetalheSheet extends StatefulWidget {
  const _DetalheSheet({
    required this.registro,
    required this.linhasIniciais,
    required this.temXmlInicial,
    required this.carregandoInicial,
    required this.terminalLeve,
    required this.nfData,
    required this.nfDataS,
    required this.onCopiar,
    required this.onDevolver,
    required this.onEstornar,
    required this.onBaixarXml,
    this.carregarRemoto,
  });

  final NfeImportadaRegistro registro;
  final List<_LinhaEspelho> linhasIniciais;
  final bool temXmlInicial;
  final bool carregandoInicial;
  final bool terminalLeve;
  final DateFormat nfData;
  final DateFormat nfDataS;
  final void Function(String label, String valor) onCopiar;
  final VoidCallback onDevolver;
  final VoidCallback onEstornar;
  final VoidCallback onBaixarXml;
  final Future<({List<_LinhaEspelho> linhas, bool temXml})> Function()?
      carregarRemoto;

  @override
  State<_DetalheSheet> createState() => _DetalheSheetState();
}

class _DetalheSheetState extends State<_DetalheSheet> {
  late List<_LinhaEspelho> _linhas = widget.linhasIniciais;
  late bool _temXml = widget.temXmlInicial;
  late bool _carregando = widget.carregandoInicial;
  String? _erro;

  @override
  void initState() {
    super.initState();
    if (widget.carregarRemoto != null) {
      unawaited(_carregar());
    }
  }

  Future<void> _carregar() async {
    try {
      final r = await widget.carregarRemoto!();
      if (!mounted) return;
      setState(() {
        _linhas = r.linhas;
        _temXml = r.temXml;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.registro;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              r.nomeFornecedor.trim().isEmpty
                  ? 'Fornecedor nao informado'
                  : r.nomeFornecedor,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'NF ${r.numeroNota > 0 ? "#${r.numeroNota}" : "—"} · '
              'Emissao ${widget.nfDataS.format(r.dataEmissao.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Importado em ${widget.nfData.format(r.dataHoraImportacao.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => widget.onCopiar('Chave', r.chaveAcesso),
                  icon: const Icon(Icons.key_outlined, size: 18),
                  label: const Text('Copiar chave'),
                ),
                FilledButton.tonalIcon(
                  onPressed: r.cnpjFornecedor.trim().isEmpty
                      ? null
                      : () => widget.onCopiar('CNPJ', r.cnpjFornecedor.trim()),
                  icon: const Icon(Icons.badge_outlined, size: 18),
                  label: const Text('Copiar CNPJ'),
                ),
                FilledButton.tonalIcon(
                  onPressed: (!_carregando && _erro == null && _temXml)
                      ? widget.onBaixarXml
                      : null,
                  icon: const Icon(Icons.code_outlined, size: 18),
                  label: const Text('Baixar XML'),
                ),
                FilledButton.icon(
                  onPressed: widget.onDevolver,
                  icon: const Icon(Icons.assignment_return_outlined, size: 18),
                  label: const Text('Devolver ao fornecedor'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: widget.onEstornar,
              icon: Icon(
                Icons.undo_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              label: Text(
                'Estornar importacao (desfazer entrada)',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Itens no estoque (historico por chave)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _carregando
                  ? const Center(child: CircularProgressIndicator())
                  : _erro != null
                      ? Center(
                          child: Text(
                            _erro!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        )
                      : _linhas.isEmpty
                          ? Center(
                              child: Text(
                                'Nenhum lancamento de historico para esta chave.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _linhas.length,
                              separatorBuilder: (context, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final h = _linhas[i];
                                return _TileHistoricoImportada(linha: h);
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiChip extends StatelessWidget {
  const _KpiChip({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tema.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: tema.textTheme.labelSmall?.copyWith(
                color: tema.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              valor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tema.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TileHistoricoImportada extends StatelessWidget {
  const _TileHistoricoImportada({required this.linha});

  final _LinhaEspelho linha;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        linha.produtoCodigoInterno.trim().isEmpty
            ? linha.produtoNome
            : '${linha.produtoCodigoInterno} · ${linha.produtoNome}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        'Qtd nota ${linha.quantidadeFornecedor} ${linha.unidadeFornecedor} · '
        'Entrada ${linha.quantidadeEntradaEstoque} un. · '
        'Fator ${linha.fatorConversaoUtilizado}',
        style: tema.textTheme.bodySmall,
      ),
    );
  }
}
