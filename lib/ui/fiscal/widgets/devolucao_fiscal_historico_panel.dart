import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/devolucao_fiscal_store.dart';
import '../../../model/registro_devolucao.dart';
import '../../../model/venda.dart';
import '../../../services/venda_fiscal_service.dart';
import '../abrir_documento_fiscal.dart';

/// Monta mapa registroId -> fiscal para exibir no painel.
Map<int, DevolucaoFiscalRegistro> mapaFiscalPorRegistro(
  VendaFiscalService fiscalSvc,
  List<RegistroDevolucao> registros,
) {
  final map = <int, DevolucaoFiscalRegistro>{};
  for (final r in registros) {
    final f = fiscalSvc.devolucaoFiscalPorRegistro(r.id);
    if (f != null) map[r.id] = f;
  }
  return map;
}

/// Banner quando a venda possui NFC-e/NF-e e exigira NF-e de devolucao.
class DevolucaoFiscalAvisoBanner extends StatelessWidget {
  const DevolucaoFiscalAvisoBanner({super.key, required this.venda});

  final Venda venda;

  @override
  Widget build(BuildContext context) {
    final exige = venda.nfceAutorizadaAtiva || venda.nfe55Autorizada;
    if (!exige) return const SizedBox.shrink();

    final tema = Theme.of(context);
    final doc = venda.nfe55Autorizada
        ? 'NF-e ${venda.nfeNumero.isNotEmpty ? venda.nfeNumero : "55"}'
        : 'NFC-e ${venda.nfceNumero.isNotEmpty ? venda.nfceNumero : ""}';

    return Card(
      margin: EdgeInsets.zero,
      color: tema.colorScheme.primaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: tema.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Venda com $doc autorizada. Ao registrar devolucao, sera emitida '
                'NF-e de devolucao (finalidade 4) na SEFAZ referenciando a nota '
                'original. Cliente precisa ter endereco e CEP validos.',
                style: tema.textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Historico de devolucoes/trocas com NF-e de devolucao (DANFE).
class DevolucaoFiscalHistoricoPanel extends StatelessWidget {
  const DevolucaoFiscalHistoricoPanel({
    super.key,
    required this.registros,
    required this.fiscaisPorRegistro,
  });

  final List<RegistroDevolucao> registros;
  final Map<int, DevolucaoFiscalRegistro> fiscaisPorRegistro;

  @override
  Widget build(BuildContext context) {
    if (registros.isEmpty) return const SizedBox.shrink();

    final tema = Theme.of(context);
    final dataFmt = DateFormat('dd/MM/yyyy HH:mm');

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: 20, color: tema.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Historico de devolucoes',
                  style: tema.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < registros.length; i++) ...[
              if (i > 0) const Divider(height: 20),
              _LinhaHistoricoDevolucao(
                registro: registros[i],
                fiscal: fiscaisPorRegistro[registros[i].id],
                dataFmt: dataFmt,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinhaHistoricoDevolucao extends StatelessWidget {
  const _LinhaHistoricoDevolucao({
    required this.registro,
    required this.fiscal,
    required this.dataFmt,
  });

  final RegistroDevolucao registro;
  final DevolucaoFiscalRegistro? fiscal;
  final DateFormat dataFmt;

  @override
  Widget build(BuildContext context) {
    final tipo = registro.tipo == 'troca' ? 'Troca' : 'Devolucao';
    final qtdItens = registro.linhasEntrada.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$tipo · ${dataFmt.format(registro.data.toLocal())}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '$qtdItens item(ns) · ${registro.motivo}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (registro.observacaoFinanceira.trim().isNotEmpty)
          Text(
            registro.observacaoFinanceira.trim(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (fiscal != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                avatar: const Icon(Icons.receipt_long, size: 16),
                label: Text(
                  fiscal!.numero.isNotEmpty
                      ? 'NF-e dev. ${fiscal!.numero}'
                      : 'NF-e devolucao',
                ),
                visualDensity: VisualDensity.compact,
              ),
              if (fiscal!.urlDanfe.trim().isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => abrirUrlDocumentoFiscal(
                    context,
                    fiscal!.urlDanfe,
                    mensagemSeVazio: 'DANFE da devolucao indisponivel.',
                  ),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Abrir DANFE'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

Future<void> mostrarDialogoDevolucaoFiscalSucesso(
  BuildContext context, {
  required VendaFiscalOperacaoResultado resultado,
}) async {
  if (!resultado.nfeDevolucaoAutorizada &&
      resultado.urlDanfeDevolucao.trim().isEmpty) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('NF-e de devolucao'),
      content: Text(
        resultado.mensagem.isNotEmpty
            ? resultado.mensagem
            : 'Devolucao fiscal registrada na SEFAZ.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'),
        ),
        if (resultado.urlDanfeDevolucao.trim().isNotEmpty)
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              abrirUrlDocumentoFiscal(
                context,
                resultado.urlDanfeDevolucao,
                mensagemSeVazio: 'DANFE indisponivel.',
              );
            },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Abrir DANFE'),
          ),
      ],
    ),
  );
}

Future<void> mostrarDialogoListaDevolucoesFiscais(
  BuildContext context, {
  required List<DevolucaoFiscalRegistro> fiscais,
}) async {
  if (fiscais.isEmpty) return;
  final dataFmt = DateFormat('dd/MM/yyyy HH:mm');

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('NF-e de devolucao'),
      content: SizedBox(
        width: 420,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: fiscais.length,
          separatorBuilder: (_, _) => const Divider(height: 16),
          itemBuilder: (_, i) {
            final f = fiscais[i];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  f.numero.isNotEmpty
                      ? 'Nota ${f.numero}${f.serie.isNotEmpty ? " · serie ${f.serie}" : ""}'
                      : 'Registro #${f.registroDevolucaoId}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  dataFmt.format(f.emitidaEm.toLocal()),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                if (f.motivo.trim().isNotEmpty)
                  Text(f.motivo.trim(), style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 8),
                if (f.urlDanfe.trim().isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      abrirUrlDocumentoFiscal(context, f.urlDanfe);
                    },
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('Abrir DANFE'),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}
