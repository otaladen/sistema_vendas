import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../data/api/lan_api_client.dart';
import '../data/api/lan_api_event_hub.dart';
import '../data/api/lista_preco_externa_api_repository.dart';
import '../data/app_config_repository.dart';
import '../data/lista_preco_externa_repository.dart';
import '../data/sync/sync_refresh_hub.dart';
import '../domain/lista_preco_externa.dart';
import '../domain/modo_terminal_leve.dart';
import 'shell/main_menu_deps.dart';

/// Consulta de tabela de precos de loja concorrente (PDF Comprou Levou / Itinga).
///
/// No PC servidor a lista fica em disco; nos terminais a mesma lista vem da API
/// (:8788). Qualquer PC que importar um PDF atualiza todos os outros.
class ListaPrecoExternaPage extends StatefulWidget {
  const ListaPrecoExternaPage({
    super.key,
    this.repository,
  });

  final ListaPrecoExternaStore? repository;

  @override
  State<ListaPrecoExternaPage> createState() => _ListaPrecoExternaPageState();
}

class _ListaPrecoExternaPageState extends State<ListaPrecoExternaPage> {
  ListaPrecoExternaStore? _repo;
  final _buscaCtrl = TextEditingController();
  final _buscaFocus = FocusNode();
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final _data = DateFormat('dd/MM/yyyy');

  ListaPrecoExterna? _lista;
  List<ListaPrecoExternaResumo> _resumos = const [];
  List<ItemListaPrecoExterna> _resultados = const [];
  bool _carregando = true;
  bool _importando = false;
  String? _erro;
  bool _viaApi = false;

  @override
  void initState() {
    super.initState();
    _buscaCtrl.addListener(_filtrar);
    SyncRefreshHub.instance.addListener(_onRedeAtualizou);
    LanApiEventHub.instance.addListener(_onApiHub);
    unawaited(_iniciar());
  }

  @override
  void dispose() {
    SyncRefreshHub.instance.removeListener(_onRedeAtualizou);
    LanApiEventHub.instance.removeListener(_onApiHub);
    _buscaCtrl.dispose();
    _buscaFocus.dispose();
    super.dispose();
  }

  void _onRedeAtualizou() {
    if (!mounted || _importando) return;
    unawaited(_carregar(silencioso: true));
  }

  void _onApiHub() {
    if (!mounted || !_viaApi) return;
    final ent = LanApiEventHub.instance.ultimaEntidade.trim();
    if (ent != 'lista_preco_externa') return;
    final api = _repo;
    if (api is ListaPrecoExternaApiRepository) {
      api.invalidarCache();
    }
    unawaited(_carregar(silencioso: true));
  }

  Future<void> _iniciar() async {
    try {
      _repo = widget.repository ?? await _criarRepositorio();
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = '$e';
      });
    }
  }

  Future<ListaPrecoExternaStore> _criarRepositorio() async {
    final config = await AppConfigRepository().carregarEmpresaConfig();
    if (!modoTerminalLeveAtivo(config)) {
      _viaApi = false;
      return ListaPrecoExternaRepository();
    }
    if (!mounted) {
      throw StateError('Tela fechada antes de conectar ao servidor.');
    }
    final client = LanApiEventHub.instance.client ??
        MainMenuDeps.maybeOf(context)?.lanApiClient;
    if (client == null) {
      throw StateError(
        'Precos Itinga no terminal exige conexao com o PC servidor.',
      );
    }
    _viaApi = true;
    final api = ListaPrecoExternaApiRepository(client);
    await api.hidratar();
    return api;
  }

  Future<void> _carregar({bool silencioso = false}) async {
    final repo = _repo;
    if (repo == null) return;
    if (!silencioso) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }
    try {
      if (repo is ListaPrecoExternaApiRepository) {
        await repo.hidratar(carregarMaisRecente: false);
      }
      final resumos = await repo.listarResumos();
      final idAtual = _lista?.id;
      ListaPrecoExterna? lista;
      if (idAtual != null && resumos.any((r) => r.id == idAtual)) {
        if (repo is ListaPrecoExternaApiRepository) {
          repo.invalidarCache();
        }
        lista = await repo.obterPorId(idAtual);
      } else if (resumos.isNotEmpty) {
        lista = await repo.obterPorId(resumos.first.id);
      }
      if (!mounted) return;
      setState(() {
        _resumos = resumos;
        _lista = lista;
        _carregando = false;
        _erro = null;
      });
      _filtrar();
    } on LanApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        if (!silencioso) _erro = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        if (!silencioso) _erro = '$e';
      });
    }
  }

  void _filtrar() {
    final lista = _lista;
    if (lista == null) {
      setState(() => _resultados = const []);
      return;
    }
    setState(() {
      _resultados = lista.buscar(_buscaCtrl.text, limite: 300);
    });
  }

  Future<void> _importarPdf() async {
    final repo = _repo;
    if (repo == null) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao foi possivel ler o PDF.')),
      );
      return;
    }

    setState(() => _importando = true);
    try {
      final nome = file.name.isNotEmpty
          ? file.name
          : (file.path != null ? p.basename(file.path!) : 'lista.pdf');
      final salva = await repo.importarPdf(bytes, arquivoOrigem: nome);
      if (!mounted) return;
      setState(() {
        _lista = salva;
        _importando = false;
      });
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${salva.quantidade} itens importados'
            '${salva.linhasIgnoradas > 0 ? ' (${salva.linhasIgnoradas} linhas ignoradas)' : ''}'
            '${_viaApi ? ' · disponivel em todos os PCs' : ' · sincronizado na rede'}.',
          ),
        ),
      );
      _buscaFocus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _importando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao importar: $e')),
      );
    }
  }

  Future<void> _trocarLista(ListaPrecoExternaResumo resumo) async {
    final repo = _repo;
    if (repo == null) return;
    if (repo is ListaPrecoExternaApiRepository) {
      repo.invalidarCache();
    }
    final lista = await repo.obterPorId(resumo.id);
    if (!mounted || lista == null) return;
    setState(() => _lista = lista);
    _filtrar();
  }

  Future<void> _excluirListaAtual() async {
    final repo = _repo;
    final lista = _lista;
    if (repo == null || lista == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lista?'),
        content: Text(
          'Remover "${lista.nomeLoja}" de ${_data.format(lista.dataLista)} '
          '(${lista.quantidade} itens)?'
          '${_viaApi ? '\n\nA exclusao vale para todos os PCs da loja.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await repo.excluir(lista.id);
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lista = _lista;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Precos Itinga / Comprou Levou'),
        actions: [
          if (lista != null)
            IconButton(
              tooltip: 'Excluir lista atual',
              onPressed: _importando ? null : _excluirListaAtual,
              icon: const Icon(Icons.delete_outline),
            ),
          IconButton(
            tooltip: 'Atualizar listas da rede',
            onPressed: (_importando || _carregando)
                ? null
                : () {
                    final api = _repo;
                    if (api is ListaPrecoExternaApiRepository) {
                      api.invalidarCache();
                    }
                    unawaited(_carregar());
                  },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Importar PDF da tabela de precos',
            onPressed: _importando ? null : _importarPdf,
            icon: _importando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_erro != null)
                  MaterialBanner(
                    content: Text(_erro!),
                    actions: [
                      TextButton(
                        onPressed: _carregar,
                        child: const Text('Tentar de novo'),
                      ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        lista == null
                            ? 'Importe o PDF da tabela de precos (Codigo, Produto, Preco). '
                                'A lista fica no PC servidor e aparece em todos os terminais.'
                            : '${lista.nomeLoja} · lista de ${_data.format(lista.dataLista)} · '
                                '${lista.quantidade} itens'
                                '${lista.arquivoOrigem.isNotEmpty ? ' · ${lista.arquivoOrigem}' : ''}'
                                '${_viaApi ? ' · via servidor' : ''}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_resumos.length > 1) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: lista?.id,
                          decoration: const InputDecoration(
                            labelText: 'Lista importada',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final r in _resumos)
                              DropdownMenuItem(
                                value: r.id,
                                child: Text(
                                  '${r.nomeLoja} · ${_data.format(r.dataLista)} '
                                  '(${r.quantidade})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (id) {
                            if (id == null) return;
                            final r = _resumos.firstWhere((e) => e.id == id);
                            unawaited(_trocarLista(r));
                          },
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: _buscaCtrl,
                        focusNode: _buscaFocus,
                        enabled: lista != null,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          labelText: 'Buscar produto ou codigo',
                          hintText: 'Ex.: ferro 5/16, cimento, 002748',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _buscaCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Limpar',
                                  onPressed: () {
                                    _buscaCtrl.clear();
                                    _filtrar();
                                  },
                                  icon: const Icon(Icons.clear),
                                ),
                          border: const OutlineInputBorder(),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(r'[\n\r]')),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        lista == null
                            ? 'Nenhuma lista carregada.'
                            : '${_resultados.length} resultado(s)'
                                '${_buscaCtrl.text.trim().isEmpty ? ' (digite para filtrar)' : ''}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: lista == null
                      ? Center(
                          child: FilledButton.icon(
                            onPressed: _importando ? null : _importarPdf,
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('Importar PDF'),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _resultados.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final item = _resultados[i];
                            return ListTile(
                              dense: true,
                              title: Text(item.nome),
                              subtitle: Text('Codigo ${item.codigo}'),
                              trailing: Text(
                                _moeda.format(item.preco),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              onTap: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text:
                                        '${item.codigo} ${item.nome} ${_moeda.format(item.preco)}',
                                  ),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    duration: Duration(seconds: 1),
                                    content: Text('Copiado'),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
