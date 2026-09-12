import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../config/focus_nfe_runtime.dart';
import '../../services/configuracoes_service.dart';
import '../../data/api/lan_api_client.dart';
import '../../data/nfe_recebidas_cache_store.dart';
import '../../domain/fiscal/nfe_recebida.dart';
import '../../domain/fiscal/nfe_recebidas_filtro.dart';
import '../../services/focus_nfe_service.dart';
import 'nfe_importacao_xml_flow.dart';
import 'widgets/nfe_ambiente_banner.dart';

/// NF-e emitidas contra o CNPJ da loja (Focus NFe — recebidas / MDe).
class NotasRecebidasPage extends StatefulWidget {
  const NotasRecebidasPage({
    super.key,
    required this.produtoRepository,
    required this.configuracoesService,
    this.lanApiClient,
  });

  final dynamic produtoRepository;
  final ConfiguracoesService configuracoesService;
  final LanApiClient? lanApiClient;

  @override
  State<NotasRecebidasPage> createState() => _NotasRecebidasPageState();
}

class _NotasRecebidasPageState extends State<NotasRecebidasPage> {
  late FocusNfeService _focus;
  final _buscaCtrl = TextEditingController();
  NfeRecebidasFiltro _filtro = const NfeRecebidasFiltro();
  List<NfeRecebida> _todas = [];
  bool _carregandoCache = true;
  bool _sincronizando = false;
  String? _acaoChave;

  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _dataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  String _cnpjLoja = '';

  @override
  void initState() {
    super.initState();
    _focus = FocusNfeService(config: criarFocusNfeConfigPadrao());
    unawaited(_inicializarFiscal());
  }

  Future<void> _inicializarFiscal() async {
    final cfg = await widget.configuracoesService.carregarFiscalGlobal();
    if (!mounted) return;
    setState(() {
      _cnpjLoja = cfg.cnpjEmitente.replaceAll(RegExp(r'\D'), '');
      _focus = FocusNfeService(config: criarFocusNfeConfigPadrao());
    });
    await _carregarCache();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarCache() async {
    setState(() => _carregandoCache = true);
    final lista = await NfeRecebidasCacheStore.carregar(_cnpjLoja);
    if (!mounted) return;
    setState(() {
      _todas = lista;
      _carregandoCache = false;
    });
  }

  Future<void> _sincronizarFocus({bool historicoCompleto = false}) async {
    try {
      _focus.validarConfiguracao();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
      return;
    }

    if (historicoCompleto) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Recarregar historico completo'),
          content: const Text(
            'A Focus devolve ate 100 NF-e por requisicao. Este processo pode '
            'demorar alguns minutos se houver muitas notas contra o CNPJ.\n\n'
            'Deseja continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Recarregar'),
            ),
          ],
        ),
      );
      if (confirmar != true || !mounted) return;
    }

    setState(() => _sincronizando = true);
    try {
      final versao = await NfeRecebidasCacheStore.lerUltimaVersao(_cnpjLoja);
      final sync = historicoCompleto
          ? await _focus.sincronizarNfesRecebidasHistoricoCompleto(
              cnpjDestinatario: _cnpjLoja,
            )
          : await _focus.sincronizarNfesRecebidas(
              versaoArmazenada: versao,
              cnpjDestinatario: _cnpjLoja,
            );
      if (!mounted) return;
      if (sync.erro != null && sync.notas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sync.erro!)),
        );
        return;
      }
      if (sync.notas.isNotEmpty) {
        _todas = NfeRecebidasCacheStore.mesclar(_todas, sync.notas);
        await NfeRecebidasCacheStore.salvar(_cnpjLoja, _todas);
        if (sync.novaVersaoMax > versao) {
          await NfeRecebidasCacheStore.salvarUltimaVersao(
            _cnpjLoja,
            sync.novaVersaoMax,
          );
        }
      }
      if (!mounted) return;
      setState(() {});
      final qtd = sync.notas.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            historicoCompleto
                ? (qtd > 0
                    ? 'Historico completo: $qtd registro(s) obtidos da Focus.'
                    : 'Nenhuma NF-e encontrada na Focus para este CNPJ.')
                : (qtd > 0
                    ? 'Sincronizado: $qtd registro(s) atualizado(s) na Focus.'
                    : 'Nenhuma NF-e nova ou alterada desde a ultima sincronizacao.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  List<NfeRecebida> get _filtradas =>
      NfeRecebidasFiltroUtil.aplicar(_todas, _filtro);

  Future<void> _escolherPeriodo() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _filtro.dataInicio != null && _filtro.dataFim != null
          ? DateTimeRange(start: _filtro.dataInicio!, end: _filtro.dataFim!)
          : null,
      locale: const Locale('pt', 'BR'),
    );
    if (range == null || !mounted) return;
    setState(() {
      _filtro = NfeRecebidasFiltro(
        textoBusca: _filtro.textoBusca,
        dataInicio: range.start,
        dataFim: range.end,
      );
    });
  }

  void _limparPeriodo() {
    setState(() {
      _filtro = NfeRecebidasFiltro(
        textoBusca: _filtro.textoBusca,
      );
    });
  }

  Future<void> _copiarChave(String chave) async {
    await Clipboard.setData(ClipboardData(text: chave));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chave copiada.')),
    );
  }

  Future<void> _baixarXml(NfeRecebida nota) async {
    setState(() => _acaoChave = nota.chaveNfe);
    try {
      final xml = await _focus.baixarNfeRecebidaXml(nota.chaveNfe);
      if (!mounted) return;
      if (xml == null || xml.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'XML indisponivel. Manifeste ciencia da operacao na SEFAZ '
              'para liberar o XML completo, depois sincronize novamente.',
            ),
            duration: Duration(seconds: 8),
          ),
        );
        return;
      }
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar XML da NF-e',
        fileName: 'NFe_${nota.chaveNfe}.xml',
        type: FileType.custom,
        allowedExtensions: const ['xml'],
      );
      if (path != null && path.isNotEmpty) {
        await File(path).writeAsString(xml);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('XML salvo em $path')),
        );
      }
    } finally {
      if (mounted) setState(() => _acaoChave = null);
    }
  }

  Future<void> _baixarDanfe(NfeRecebida nota) async {
    setState(() => _acaoChave = nota.chaveNfe);
    try {
      final pdf = await _focus.baixarNfeRecebidaDanfePdf(nota.chaveNfe);
      if (!mounted) return;
      if (pdf == null || pdf.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nao foi possivel baixar o DANFE.')),
        );
        return;
      }
      await Printing.layoutPdf(onLayout: (_) async => pdf);
    } finally {
      if (mounted) setState(() => _acaoChave = null);
    }
  }

  Future<void> _manifestar(NfeRecebida nota) async {
    final escolha = await showDialog<_ManifestacaoEscolha>(
      context: context,
      builder: (ctx) => const _ManifestacaoNfeDialog(),
    );
    if (escolha == null || !mounted) return;

    setState(() => _acaoChave = nota.chaveNfe);
    try {
      final r = await _focus.manifestarNfeRecebida(
        chaveAcesso: nota.chaveNfe,
        tipo: escolha.tipo,
        justificativa: escolha.justificativa,
      );
      if (!mounted) return;
      if (!r.sucesso) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r.mensagem)),
        );
        return;
      }
      final idx = _todas.indexWhere((n) => n.chaveNfe == nota.chaveNfe);
      if (idx >= 0) {
        _todas[idx] = nota.copyWith(
          manifestacaoDestinatario: escolha.tipo,
        );
        await NfeRecebidasCacheStore.salvar(_cnpjLoja, _todas);
      }
      setState(() {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.mensagem)),
      );
      await _sincronizarFocus();
    } finally {
      if (mounted) setState(() => _acaoChave = null);
    }
  }

  Future<void> _importarEstoque(NfeRecebida nota) async {
    setState(() => _acaoChave = nota.chaveNfe);
    try {
      final xml = await _focus.baixarNfeRecebidaXml(nota.chaveNfe);
      if (!mounted) return;
      if (xml == null || xml.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Importacao exige XML completo. Registre ciencia ou confirmacao '
              'e sincronize antes de importar.',
            ),
            duration: Duration(seconds: 8),
          ),
        );
        return;
      }
      await NfeImportacaoXmlFlow.executarComConteudoXml(
        context,
        xml: xml,
        produtoRepository: widget.produtoRepository,
        configuracoesService: widget.configuracoesService,
        lanApiClient: widget.lanApiClient,
      );
    } finally {
      if (mounted) setState(() => _acaoChave = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtradas = _filtradas;
    final periodo = _rotuloPeriodo(_filtro.dataInicio, _filtro.dataFim);

    return Scaffold(
      appBar: AppBar(
        title: const Text('NF-e recebidas (entrada)'),
        actions: [
          if (_sincronizando)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            TextButton.icon(
              onPressed: () => _sincronizarFocus(),
              icon: const Icon(Icons.cloud_sync_outlined),
              label: const Text('Sincronizar Focus'),
            ),
            IconButton(
              tooltip: 'Recarregar historico completo na Focus',
              icon: const Icon(Icons.history),
              onPressed: () => _sincronizarFocus(historicoCompleto: true),
            ),
          ],
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const NfeAmbienteBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Notas emitidas contra o CNPJ da loja (Focus NFe / MDe).',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _buscaCtrl,
                  decoration: InputDecoration(
                    hintText: 'Fornecedor, CNPJ ou chave de acesso...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _buscaCtrl.text.trim().isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _buscaCtrl.clear();
                              setState(() {
                                _filtro = NfeRecebidasFiltro(
                                  dataInicio: _filtro.dataInicio,
                                  dataFim: _filtro.dataFim,
                                );
                              });
                            },
                          ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() {
                    _filtro = NfeRecebidasFiltro(
                      textoBusca: v,
                      dataInicio: _filtro.dataInicio,
                      dataFim: _filtro.dataFim,
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _escolherPeriodo,
                      icon: const Icon(Icons.date_range_outlined, size: 18),
                      label: Text(periodo),
                    ),
                    if (_filtro.dataInicio != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _limparPeriodo,
                        child: const Text('Limpar periodo'),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      '${filtradas.length} de ${_todas.length}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _carregandoCache
                ? const Center(child: CircularProgressIndicator())
                : filtradas.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _todas.isEmpty
                                ? 'Nenhuma nota no cache. Toque em "Sincronizar Focus" '
                                    'para buscar NF-e recebidas na API.'
                                : 'Nenhuma nota corresponde aos filtros.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: filtradas.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final nota = filtradas[index];
                          return _NotaRecebidaCard(
                            nota: nota,
                            moeda: _moeda,
                            dataHora: _dataHora,
                            ocupado: _acaoChave == nota.chaveNfe,
                            onCopiarChave: () => _copiarChave(nota.chaveNfe),
                            onBaixarXml: () => _baixarXml(nota),
                            onBaixarDanfe: () => _baixarDanfe(nota),
                            onManifestar: () => _manifestar(nota),
                            onImportar: () => _importarEstoque(nota),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  static String _rotuloPeriodo(DateTime? ini, DateTime? fim) {
    if (ini == null && fim == null) return 'Periodo: todos';
    final fmt = DateFormat('dd/MM/yyyy');
    if (ini != null && fim != null) {
      return '${fmt.format(ini)} — ${fmt.format(fim)}';
    }
    if (ini != null) return 'A partir de ${fmt.format(ini)}';
    return 'Ate ${fmt.format(fim!)}';
  }
}

class _NotaRecebidaCard extends StatelessWidget {
  const _NotaRecebidaCard({
    required this.nota,
    required this.moeda,
    required this.dataHora,
    required this.ocupado,
    required this.onCopiarChave,
    required this.onBaixarXml,
    required this.onBaixarDanfe,
    required this.onManifestar,
    required this.onImportar,
  });

  final NfeRecebida nota;
  final NumberFormat moeda;
  final DateFormat dataHora;
  final bool ocupado;
  final VoidCallback onCopiarChave;
  final VoidCallback onBaixarXml;
  final VoidCallback onBaixarDanfe;
  final VoidCallback onManifestar;
  final VoidCallback onImportar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cnpj = nota.documentoEmitente.replaceAll(RegExp(r'\D'), '');
    final cnpjFmt = cnpj.length == 14
        ? '${cnpj.substring(0, 2)}.${cnpj.substring(2, 5)}.${cnpj.substring(5, 8)}/${cnpj.substring(8, 12)}-${cnpj.substring(12)}'
        : nota.documentoEmitente;
    final emissao = nota.dataEmissao != null
        ? dataHora.format(nota.dataEmissao!.toLocal())
        : '—';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nota.nomeEmitente.isNotEmpty
                            ? nota.nomeEmitente
                            : 'Emitente nao informado',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text('CNPJ: $cnpjFmt', style: theme.textTheme.bodySmall),
                      Text('Emissao: $emissao',
                          style: theme.textTheme.bodySmall),
                      Text(
                        moeda.format(nota.valorTotal),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _ChipStatus(
                      label: NfeRecebidaRotulos.situacao(nota.situacao),
                      cor: _corSituacao(nota.situacao),
                    ),
                    const SizedBox(height: 4),
                    _ChipStatus(
                      label: NfeRecebidaRotulos.manifestacao(
                        nota.manifestacaoDestinatario,
                      ),
                      cor: Colors.blueGrey,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    nota.chaveNfe,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar chave',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: onCopiarChave,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _acao(
                  label: 'Baixar XML',
                  icon: Icons.code,
                  onPressed: ocupado ? null : onBaixarXml,
                ),
                _acao(
                  label: 'DANFE / PDF',
                  icon: Icons.picture_as_pdf_outlined,
                  onPressed: ocupado ? null : onBaixarDanfe,
                ),
                _acao(
                  label: 'Manifestar',
                  icon: Icons.fact_check_outlined,
                  onPressed: ocupado ? null : onManifestar,
                ),
                _acao(
                  label: 'Importar estoque',
                  icon: Icons.inventory_2_outlined,
                  onPressed: ocupado ? null : onImportar,
                ),
              ],
            ),
            if (ocupado)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  Color _corSituacao(String s) {
    switch (s.toLowerCase()) {
      case 'autorizada':
        return Colors.green.shade700;
      case 'cancelada':
        return Colors.red.shade700;
      default:
        return Colors.orange.shade800;
    }
  }

  Widget _acao({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}

class _ManifestacaoEscolha {
  const _ManifestacaoEscolha({
    required this.tipo,
    this.justificativa = '',
  });

  final String tipo;
  final String justificativa;
}

class _ManifestacaoNfeDialog extends StatefulWidget {
  const _ManifestacaoNfeDialog();

  @override
  State<_ManifestacaoNfeDialog> createState() => _ManifestacaoNfeDialogState();
}

class _ManifestacaoNfeDialogState extends State<_ManifestacaoNfeDialog> {
  String? _tipo;
  final _justificativaCtrl = TextEditingController();

  @override
  void dispose() {
    _justificativaCtrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final tipo = _tipo;
    if (tipo == null) return;
    if (tipo == 'nao_realizada') {
      final j = _justificativaCtrl.text.trim();
      if (j.length < 15 || j.length > 255) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Justificativa: minimo 15 e maximo 255 caracteres.'),
          ),
        );
        return;
      }
      Navigator.pop(
        context,
        _ManifestacaoEscolha(tipo: tipo, justificativa: j),
      );
      return;
    }
    Navigator.pop(context, _ManifestacaoEscolha(tipo: tipo));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Manifestar NF-e'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Manifestacao do destinatario (MDe), enviada a SEFAZ via Focus.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              _opcao('ciencia', 'Ciencia da operacao',
                  'Operacao conhecida; XML completo pode ser liberado apos ciencia.'),
              _opcao('confirmacao', 'Confirmacao da operacao',
                  'Mercadoria/servico recebido conforme a NF-e.'),
              _opcao('desconhecimento', 'Desconhecimento da operacao',
                  'A empresa nao reconhece esta NF-e.'),
              _opcao('nao_realizada', 'Operacao nao realizada',
                  'Operacao conhecida, mas nao concluida (exige justificativa).'),
              if (_tipo == 'nao_realizada') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _justificativaCtrl,
                  maxLines: 3,
                  maxLength: 255,
                  decoration: const InputDecoration(
                    labelText: 'Justificativa',
                    hintText: 'Minimo 15 caracteres',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _tipo == null ? null : _confirmar,
          child: const Text('Enviar manifestacao'),
        ),
      ],
    );
  }

  Widget _opcao(String valor, String titulo, String subtitulo) {
    final sel = _tipo == valor;
    return ListTile(
      leading: Icon(
        sel ? Icons.radio_button_checked : Icons.radio_button_off,
        color: sel ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(titulo),
      subtitle: Text(subtitulo, style: const TextStyle(fontSize: 12)),
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: () => setState(() => _tipo = valor),
    );
  }
}

class _ChipStatus extends StatelessWidget {
  const _ChipStatus({required this.label, required this.cor});

  final String label;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: cor,
        ),
      ),
    );
  }
}
