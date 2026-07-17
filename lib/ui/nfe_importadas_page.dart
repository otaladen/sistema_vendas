import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/nfe_entrada_repository.dart';
import '../data/produto_repository.dart';
import '../model/historico_entrada.dart';
import '../model/nfe_importada_registro.dart';
import 'fiscal/nfe_devolucao_fornecedor_page.dart';

/// Log de NF-e importadas por XML: KPIs, filtros, ordenacao, detalhe e exportacao CSV.
class NfeImportadasPage extends StatefulWidget {
  const NfeImportadasPage({
    super.key,
    required this.produtoRepository,
  });

  final ProdutoRepository produtoRepository;

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

  @override
  void initState() {
    super.initState();
    _buscaCtrl.addListener(_onBuscaChanged);
    _recarregarDados();
  }

  void _onBuscaChanged() => setState(() {});

  @override
  void dispose() {
    _buscaCtrl.removeListener(_onBuscaChanged);
    _buscaCtrl.dispose();
    super.dispose();
  }

  void _recarregarDados() {
    final repo = NfeEntradaRepository(widget.produtoRepository.objectBox);
    setState(() {
      _todos = repo.listarImportacoesNfeDesc();
    });
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

  List<NfeImportadaRegistro> get _filtrados {
    return _todos.where((r) => _dentroDoPeriodo(r) && _passaBusca(r)).toList();
  }

  List<NfeImportadaRegistro> get _listaExibicao {
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
    DateTime? max;
    for (final r in it) {
      if (max == null || r.dataHoraImportacao.isAfter(max)) {
        max = r.dataHoraImportacao;
      }
    }
    if (max == null) return null;
    return _nfDataCurta.format(max.toLocal());
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
          chaveNotaInicial: r.chaveAcesso,
        ),
      ),
    );
  }

  Future<void> _confirmarEstornoImportacao(
    BuildContext sheetContext,
    NfeImportadaRegistro r,
  ) async {
    final repo = NfeEntradaRepository(widget.produtoRepository.objectBox);
    final validacao = repo.validarEstornoImportacao(r.id);
    final nfLabel = r.numeroNota > 0 ? 'NF #${r.numeroNota}' : 'esta NF-e';
    final fornecedor = r.nomeFornecedor.trim().isEmpty
        ? 'fornecedor nao informado'
        : r.nomeFornecedor;

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
                  'O estoque das entradas abaixo volta atras e a chave fica '
                  'livre para importar o XML de novo.',
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
      repo.estornarImportacaoNfe(r.id);
      widget.produtoRepository.invalidarCacheBusca();
      if (sheetContext.mounted) {
        Navigator.pop(sheetContext);
      }
      _recarregarDados();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Importacao estornada. Estoque revertido; a nota pode ser importada de novo.',
          ),
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  void _abrirDetalhe(NfeImportadaRegistro r) {
    final repo = NfeEntradaRepository(widget.produtoRepository.objectBox);
    final historico = repo.listarHistoricoPorChaveNfe(r.chaveAcesso);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  r.nomeFornecedor.trim().isEmpty
                      ? 'Fornecedor nao informado'
                      : r.nomeFornecedor,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'NF ${r.numeroNota > 0 ? "#${r.numeroNota}" : "—"} · '
                  'Emissao ${_nfDataS.format(r.dataEmissao.toLocal())}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                Text(
                  'Importado em ${_nfData.format(r.dataHoraImportacao.toLocal())}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _copiar('Chave', r.chaveAcesso),
                      icon: const Icon(Icons.key_outlined, size: 18),
                      label: const Text('Copiar chave'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: r.cnpjFornecedor.trim().isEmpty
                          ? null
                          : () => _copiar('CNPJ', r.cnpjFornecedor.trim()),
                      icon: const Icon(Icons.badge_outlined, size: 18),
                      label: const Text('Copiar CNPJ'),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _abrirDevolucaoFornecedor(r);
                      },
                      icon: const Icon(Icons.assignment_return_outlined, size: 18),
                      label: const Text('Devolver ao fornecedor'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _confirmarEstornoImportacao(ctx, r),
                  icon: Icon(
                    Icons.undo_outlined,
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                  label: Text(
                    'Estornar importacao (desfazer entrada)',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Itens no estoque (historico por chave)',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: historico.isEmpty
                      ? Center(
                          child: Text(
                            'Nenhum lancamento de historico para esta chave.',
                            textAlign: TextAlign.center,
                            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: historico.length,
                          separatorBuilder: (context, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final h = historico[i];
                            return _TileHistoricoImportada(h: h);
                          },
                        ),
                ),
              ],
            ),
          ),
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
    final tema = Theme.of(context);
    final onVar = tema.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NF-e importadas (XML)'),
        actions: [
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
                    valor: filtrados.length.toString(),
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
                        onPressed: () => setState(() => _periodo = null),
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
                              if (v != null) setState(() => _ordenacao = v);
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
            child: _todos.isEmpty
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
                        onRefresh: () async => _recarregarDados(),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: lista.length,
                          separatorBuilder: (context, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final r = lista[i];
                            return Card(
                              child: InkWell(
                                onTap: () => _abrirDetalhe(r),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
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
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TileHistoricoImportada extends StatelessWidget {
  const _TileHistoricoImportada({required this.h});

  final HistoricoEntrada h;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final prod = h.produto.target;
    final nomeProd = prod?.nome.trim().isNotEmpty == true
        ? prod!.nome
        : (prod?.descricao ?? 'Produto');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        nomeProd,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        'Qtd nota ${h.quantidadeFornecedor} ${h.unidadeFornecedor} · '
        'Entrada ${h.quantidadeEntradaEstoque} un. · '
        'Fator ${h.fatorConversaoUtilizado}',
        style: tema.textTheme.bodySmall,
      ),
    );
  }
}
