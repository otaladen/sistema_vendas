import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/produto_repository.dart';
import '../../domain/produto_nome_exibicao.dart';
import '../../model/nfe_importada_registro.dart';
import '../../services/devolucao_fornecedor_fiscal_service.dart';
import '../../services/fiscal_config_store.dart';

/// Emite NF-e de devolucao de compra (CFOP 5202/6202) ao fornecedor/fabrica.
///
/// Valores e impostos partem do XML da compra e podem ser ajustados para
/// bater com o espelho enviado pela fabrica.
class NfeDevolucaoFornecedorPage extends StatefulWidget {
  const NfeDevolucaoFornecedorPage({
    super.key,
    required this.produtoRepository,
    this.chaveNotaInicial,
  });

  final ProdutoRepository produtoRepository;
  final String? chaveNotaInicial;

  @override
  State<NfeDevolucaoFornecedorPage> createState() =>
      _NfeDevolucaoFornecedorPageState();
}

class _NfeDevolucaoFornecedorPageState extends State<NfeDevolucaoFornecedorPage> {
  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _data = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final _num = NumberFormat('#,##0.##', 'pt_BR');

  late final DevolucaoFornecedorFiscalService _svc;
  final TextEditingController _motivoCtrl = TextEditingController();
  final TextEditingController _buscaCtrl = TextEditingController();

  List<NfeImportadaRegistro> _notas = const [];
  NfeImportadaRegistro? _selecionada;
  List<DevolucaoFornecedorLinha> _linhas = const [];
  bool _carregando = false;
  bool _emitindo = false;

  @override
  void initState() {
    super.initState();
    _svc = DevolucaoFornecedorFiscalService(
      produtoRepository: widget.produtoRepository,
    );
    _motivoCtrl.text = 'Devolucao de mercadoria ao fornecedor';
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregarNotas());
  }

  @override
  void dispose() {
    _motivoCtrl.dispose();
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarNotas() async {
    setState(() => _carregando = true);
    final notas = _svc.listarNotasCompra();
    NfeImportadaRegistro? inicial;
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
    if (!mounted) return;
    setState(() {
      _notas = notas;
      _carregando = false;
    });
    if (inicial != null) {
      await _selecionarNota(inicial);
    }
  }

  Future<void> _selecionarNota(NfeImportadaRegistro nota) async {
    setState(() {
      _selecionada = nota;
      _linhas = _svc.carregarLinhas(nota.chaveAcesso);
    });
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
      final res = _svc.aplicarEspelhoXml(xmlTexto: xml, linhas: _linhas);
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
    if (!FiscalConfigStore.configurado) {
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
          'Se autorizada, o estoque sera baixado.',
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
    final res = await _svc.emitir(
      chaveNotaCompra: nota.chaveAcesso,
      linhasSelecionadas: _linhas,
      motivo: _motivoCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _emitindo = false;
      if (res.sucesso) {
        _linhas = _svc.carregarLinhas(nota.chaveAcesso);
      }
    });

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
}
