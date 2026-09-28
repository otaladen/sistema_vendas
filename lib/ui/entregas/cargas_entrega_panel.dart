import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entregas/agenda_carreto_ocupacao.dart';
import '../../domain/entregas/carga_atual_venda.dart';
import '../../domain/entregas/cargas_entrega.dart';
import '../../model/venda.dart';
import '../../services/entrega_pod_lan_service.dart';

/// Viagens do plano de cargas com o comprovante de cada uma.
class CargasEntregaPanel extends StatelessWidget {
  const CargasEntregaPanel({super.key, required this.venda});

  final Venda venda;

  @override
  Widget build(BuildContext context) {
    final cargas = CargaAtualVenda.cargas(venda);
    if (cargas.isEmpty) return const SizedBox.shrink();
    final atual = CargaAtualVenda.atual(venda);
    final feitas = cargas.where((c) => c.entregue).length;
    return Card(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Cargas da entrega ($feitas/${cargas.length} entregues)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            for (final c in cargas) ...[
              const Divider(height: 16),
              _LinhaCarga(
                carga: c,
                total: cargas.length,
                emAndamento: atual?.numero == c.numero,
                statusVenda: venda.statusEntrega,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinhaCarga extends StatelessWidget {
  const _LinhaCarga({
    required this.carga,
    required this.total,
    required this.emAndamento,
    required this.statusVenda,
  });

  final CargaEntrega carga;
  final int total;
  final bool emAndamento;
  final String statusVenda;

  static final _fmtDia = DateFormat('dd/MM/yyyy');
  static final _fmtHora = DateFormat('dd/MM/yyyy HH:mm');
  static final _fmtQtd = NumberFormat('#,##0.###', 'pt_BR');

  String _situacao() {
    if (carga.entregue) return 'Entregue';
    if (!emAndamento) return 'Aguardando';
    return AgendaCarretoOcupacaoHelper.rotuloStatus(statusVenda);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final data = carga.data;
    final janela = carga.janela == 'nao_definida'
        ? ''
        : ' · ${AgendaCarretoOcupacaoHelper.rotuloJanela(carga.janela)}';
    final cor = carga.entregue
        ? Colors.green.shade700
        : emAndamento
            ? scheme.primary
            : scheme.onSurfaceVariant;
    final temFoto = carga.podFotoPath.isNotEmpty ||
        carga.podFotoPathServidor.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              carga.entregue
                  ? Icons.check_circle
                  : emAndamento
                      ? Icons.local_shipping
                      : Icons.schedule,
              size: 18,
              color: cor,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Carga ${carga.numero}/$total · '
                '${data == null ? 'Sem data' : _fmtDia.format(data)}$janela',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              _situacao(),
              style: theme.textTheme.labelMedium?.copyWith(color: cor),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 24, top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                carga.linhas
                    .map((l) =>
                        '${_fmtQtd.format(l.quantidade)} ${l.nomeProduto}')
                    .join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              if (carga.entregue) ...[
                if (carga.recebidoPor.isNotEmpty)
                  Text('Recebido por: ${carga.recebidoPor}'),
                Text(
                  [
                    if (carga.entregueEm != null)
                      'Em ${_fmtHora.format(carga.entregueEm!.toLocal())}',
                    if (carga.motorista.isNotEmpty)
                      'Motorista: ${carga.motorista}',
                    if (carga.veiculo.isNotEmpty) 'Veiculo: ${carga.veiculo}',
                    if (carga.podRegistradoPor.isNotEmpty)
                      'Registrado por: ${carga.podRegistradoPor}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                if (temFoto)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _mostrarFoto(context),
                    icon: const Icon(Icons.photo_outlined, size: 18),
                    label: const Text('Ver foto do comprovante'),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _mostrarFoto(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Comprovante · Carga ${carga.numero}/$total'),
        content: SizedBox(
          width: 480,
          child: _FotoCarga(carga: carga),
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
}

class _FotoCarga extends StatefulWidget {
  const _FotoCarga({required this.carga});

  final CargaEntrega carga;

  @override
  State<_FotoCarga> createState() => _FotoCargaState();
}

class _FotoCargaState extends State<_FotoCarga> {
  late final Future<String?> _caminho = _resolver();

  Future<String?> _resolver() async {
    final local = widget.carga.podFotoPath.trim();
    if (local.isNotEmpty && File(local).existsSync()) return local;
    final servidor = widget.carga.podFotoPathServidor.trim();
    if (servidor.isEmpty) return null;
    final path = await EntregaPodLanService().baixarParaCache(
      podFotoPathServidor: servidor,
      podFotoPathLocal: local,
    );
    return path != null && File(path).existsSync() ? path : null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _caminho,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final path = snap.data;
        if (path == null) {
          return Text(
            'Foto nao encontrada. Verifique a rede ou se a retencao ja '
            'removeu o arquivo.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(File(path), fit: BoxFit.contain),
        );
      },
    );
  }
}
