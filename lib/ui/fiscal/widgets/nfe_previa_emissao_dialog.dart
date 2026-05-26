import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../config/fiscal_config.dart';
import '../../../domain/fiscal/nfe_pre_emissao_service.dart';
import '../../../domain/fiscal/nfe_previa_resumo.dart';
import '../../../model/venda.dart';
import '../../../services/focus_nfe_service.dart';

/// Etapa 2: conferencia do payload, JSON e DANFe antes de transmitir a SEFAZ.
class NfePreviaEmissaoDialog extends StatefulWidget {
  const NfePreviaEmissaoDialog({
    super.key,
    required this.focusNfe,
    required this.payload,
    required this.venda,
    required this.preEmissao,
    required this.referencia,
  });

  final FocusNfeService focusNfe;
  final Map<String, dynamic> payload;
  final Venda venda;
  final NfePreEmissaoResultado preEmissao;
  final String referencia;

  @override
  State<NfePreviaEmissaoDialog> createState() => _NfePreviaEmissaoDialogState();
}

class _NfePreviaEmissaoDialogState extends State<NfePreviaEmissaoDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final NfePreviaResumo _resumo;
  late final String _payloadJson;

  bool _carregandoDanfe = true;
  FocusNfePreviaDanfeResultado? _danfe;
  bool _confirmando = false;

  final _moeda = NumberFormat('#,##0.00', 'pt_BR');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _resumo = NfePreviaResumoBuilder.fromPayload(
      widget.payload,
      referencia: widget.referencia,
    );
    _payloadJson = const JsonEncoder.withIndent('  ').convert(widget.payload);
    _carregarDanfe();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _carregarDanfe() async {
    setState(() {
      _carregandoDanfe = true;
      _danfe = null;
    });
    final r = await widget.focusNfe.previsualizarDanfeNfe(widget.payload);
    if (!mounted) return;
    setState(() {
      _danfe = r;
      _carregandoDanfe = false;
    });
  }

  Future<void> _abrirPdfSistema() async {
    final bytes = _danfe?.pdfBytes;
    if (bytes == null || bytes.isEmpty) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  void _copiarJson() {
    Clipboard.setData(ClipboardData(text: _payloadJson));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('JSON copiado para a area de transferencia.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final homolog = FiscalConfig.ambiente.toLowerCase() == 'homologacao';

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.fact_check_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Confirmar emissao NF-e — Venda '
              '${widget.venda.numeroOrcamento > 0 ? widget.venda.numeroOrcamento : widget.venda.id}',
            ),
          ),
          if (homolog)
            Chip(
              label: const Text('HOMOLOGACAO'),
              backgroundColor: Colors.orange.shade100,
            ),
        ],
      ),
      content: SizedBox(
        width: 920,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Revise os dados abaixo. A transmissao a SEFAZ so ocorre ao confirmar.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Resumo', icon: Icon(Icons.summarize_outlined, size: 18)),
                Tab(text: 'Itens', icon: Icon(Icons.list_alt_outlined, size: 18)),
                Tab(text: 'JSON Focus', icon: Icon(Icons.data_object_outlined, size: 18)),
                Tab(text: 'DANFe', icon: Icon(Icons.picture_as_pdf_outlined, size: 18)),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _abaResumo(theme),
                  _abaItens(theme),
                  _abaJson(theme),
                  _abaDanfe(theme),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _confirmando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        if (_danfe?.sucesso == true && _danfe!.pdfBytes != null)
          OutlinedButton.icon(
            onPressed: _confirmando ? null : _abrirPdfSistema,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimir previa'),
          ),
        FilledButton.icon(
          onPressed: _confirmando
              ? null
              : () async {
                  setState(() => _confirmando = true);
                  Navigator.pop(context, true);
                },
          icon: _confirmando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload_outlined),
          label: const Text('Confirmar e transmitir'),
        ),
      ],
    );
  }

  Widget _abaResumo(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _linhaResumo('Referencia Focus', widget.referencia),
          _linhaResumo('Ambiente', _resumo.ambiente.toUpperCase()),
          _linhaResumo('Emitente', _resumo.emitenteCnpj),
          _linhaResumo('Destinatario', _resumo.destinatarioNome),
          _linhaResumo('Documento', _resumo.destinatarioDocumento),
          _linhaResumo('UF destino', _resumo.destinatarioUf),
          _linhaResumo(
            'Operacao',
            '${_resumo.rotuloLocalDestino} · '
            '${_resumo.consumidorFinal ? "Consumidor final" : "Contribuinte"}',
          ),
          _linhaResumo('Natureza', _resumo.naturezaOperacao),
          _linhaResumo('Frete', _resumo.modalidadeFrete == '0' ? 'CIF' : 'FOB'),
          const Divider(),
          _linhaResumo('Produtos', 'R\$ ${_moeda.format(_resumo.valorProdutos)}'),
          if (_resumo.valorFrete > 0)
            _linhaResumo('Frete', 'R\$ ${_moeda.format(_resumo.valorFrete)}'),
          if (_resumo.valorDesconto > 0)
            _linhaResumo('Desconto', 'R\$ ${_moeda.format(_resumo.valorDesconto)}'),
          _linhaResumo(
            'Total NF-e',
            'R\$ ${_moeda.format(_resumo.valorTotal)}',
            destaque: true,
          ),
          _linhaResumo('Itens', '${_resumo.quantidadeItens}'),
          if (_resumo.temDuplicatas)
            _linhaResumo(
              'Cobranca',
              '${_resumo.quantidadeDuplicatas} duplicata(s)',
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Apos confirmar, a nota sera enviada a Focus NFe e a SEFAZ. '
              'O estoque fisico nao e alterado por esta operacao.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _linhaResumo(String rotulo, String valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              rotulo,
              style: TextStyle(
                fontWeight: destaque ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: destaque ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _abaItens(ThemeData theme) {
    final linhas = widget.preEmissao.linhasFiscais;
    if (linhas.isEmpty) {
      return const Center(child: Text('Sem itens.'));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 12,
          columns: const [
            DataColumn(label: Text('#')),
            DataColumn(label: Text('SKU')),
            DataColumn(label: Text('Descricao')),
            DataColumn(label: Text('CFOP')),
            DataColumn(label: Text('NCM')),
            DataColumn(label: Text('ICMS')),
            DataColumn(label: Text('Total')),
          ],
          rows: linhas.map((l) {
            return DataRow(
              cells: [
                DataCell(Text('${l.numero}')),
                DataCell(Text(l.codigo)),
                DataCell(
                  SizedBox(
                    width: 180,
                    child: Text(l.descricao, overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataCell(Text(l.cfop)),
                DataCell(Text(l.ncm)),
                DataCell(Text(l.icmsCst)),
                DataCell(Text('R\$ ${_moeda.format(l.subtotal)}')),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _abaJson(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _copiarJson,
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('Copiar JSON'),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerColor),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _payloadJson,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _abaDanfe(ThemeData theme) {
    if (_carregandoDanfe) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Gerando DANFe de pre-visualizacao na Focus...'),
          ],
        ),
      );
    }

    final danfe = _danfe;
    if (danfe == null) {
      return const Center(child: Text('Sem resposta.'));
    }

    if (danfe.sucesso && danfe.pdfBytes != null) {
      return PdfPreview(
        build: (_) async => danfe.pdfBytes!,
        allowPrinting: true,
        allowSharing: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
      );
    }

    if (danfe.html != null && danfe.html!.trim().isNotEmpty) {
      return SingleChildScrollView(
        child: SelectableText(
          danfe.html!,
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            danfe.mensagemErro.isNotEmpty
                ? danfe.mensagemErro
                : 'Nao foi possivel gerar a DANFe de pre-visualizacao.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _carregarDanfe,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
          const SizedBox(height: 8),
          Text(
            'Voce ainda pode confirmar a emissao se o checklist estiver verde.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
