import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/entrega_pod_lan_service.dart';
import '../../services/entrega_pod_service.dart';

/// Dados coletados ao concluir entrega com POD.
class PodEntregaFormResult {
  const PodEntregaFormResult({
    required this.recebidoPor,
    this.fotoPathLocal,
    this.fotoPathServidor,
  });

  final String recebidoPor;
  final String? fotoPathLocal;
  final String? fotoPathServidor;
}

/// Dialogo: recebido por (obrigatorio) + foto opcional.
Future<PodEntregaFormResult?> showPodEntregaDialog({
  required BuildContext context,
  required int vendaId,
  EntregaPodService? podService,
  String? recebidoPorInicial,
  bool modoEdicao = false,
  bool podComplemento = false,
  String origemMercadoriaRotulo = '',
}) async {
  final recebidoCtrl = TextEditingController(text: recebidoPorInicial?.trim() ?? '');
  final svc = podService ?? EntregaPodService();
  String? fotoPath;
  String? fotoServidor;
  var enviandoFoto = false;

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text(
              podComplemento
                  ? 'POD do complemento'
                  : modoEdicao
                      ? 'Alterar prova de entrega'
                      : 'Prova de entrega',
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  Text(
                    podComplemento
                        ? 'Segunda viagem: informe quem recebeu o complemento. A foto e opcional.'
                        : modoEdicao
                            ? 'Atualize quem recebeu ou troque a foto. O registro anterior sera substituido.'
                            : 'Informe quem recebeu o material. A foto e opcional.',
                  ),
                  if (origemMercadoriaRotulo.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Origem da mercadoria: $origemMercadoriaRotulo',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: recebidoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Recebido por *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.words,
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    EntregaPodService.cameraDisponivel
                        ? 'Foto opcional: tire agora ou escolha uma ja salva na galeria.'
                        : 'Foto opcional: escolha um arquivo de imagem.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (fotoPath != null && File(fotoPath!).existsSync()) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(fotoPath!),
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (enviandoFoto) ...[
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: LinearProgressIndicator(),
                    ),
                    Text(
                      'Enviando foto ao PC servidor…',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                  ],
                  _botoesFotoPod(
                    ctx: ctx,
                    temFoto: fotoPath != null,
                    habilitado: !enviandoFoto,
                    onOrigem: (origem) async {
                      setLocal(() => enviandoFoto = true);
                      try {
                        final salvo = await svc.processarESalvarFotoPod(
                          vendaId: vendaId,
                          sourceImagePath: origem,
                        );
                        if (salvo == null) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Nao foi possivel salvar a foto.'),
                              ),
                            );
                          }
                          return;
                        }
                        String? noServidor;
                        try {
                          noServidor = await EntregaPodLanService()
                              .enviarFotoSeRedeAtiva(arquivoLocal: salvo);
                        } catch (_) {}
                        if (!ctx.mounted) return;
                        setLocal(() {
                          fotoPath = salvo;
                          fotoServidor = noServidor;
                        });
                        if (noServidor == null && ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Foto salva no celular. '
                                'Sera enviada ao PC na sincronizacao.',
                              ),
                            ),
                          );
                        }
                      } finally {
                        if (ctx.mounted) {
                          setLocal(() => enviandoFoto = false);
                        }
                      }
                    },
                    onRemover: () => setLocal(() {
                      fotoPath = null;
                      fotoServidor = null;
                    }),
                    svc: svc,
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
                onPressed: enviandoFoto
                    ? null
                    : () {
                  if (recebidoCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Informe quem recebeu a entrega.'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      );
    },
  );

  final recebidoPor = recebidoCtrl.text.trim();
  recebidoCtrl.dispose();
  if (ok != true) return null;
  return PodEntregaFormResult(
    recebidoPor: recebidoPor,
    fotoPathLocal: fotoPath,
    fotoPathServidor: fotoServidor,
  );
}

Widget _botoesFotoPod({
  required BuildContext ctx,
  required bool temFoto,
  required Future<void> Function(String origem) onOrigem,
  required VoidCallback onRemover,
  required EntregaPodService svc,
  bool habilitado = true,
}) {
  Future<void> aplicar(Future<String?> Function() escolher) async {
    final origem = await escolher();
    if (origem == null) return;
    await onOrigem(origem);
  }

  if (!EntregaPodService.cameraDisponivel) {
    return OutlinedButton.icon(
      onPressed: habilitado ? () => aplicar(svc.selecionarFotoGaleria) : null,
      icon: const Icon(Icons.folder_open),
      label: Text(temFoto ? 'Trocar arquivo' : 'Escolher arquivo (opcional)'),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed:
                  habilitado ? () => aplicar(svc.capturarFotoCamera) : null,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Tirar foto'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: habilitado
                  ? () => aplicar(svc.selecionarFotoGaleria)
                  : null,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Galeria'),
            ),
          ),
        ],
      ),
      if (temFoto)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onRemover,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Remover foto'),
          ),
        ),
    ],
  );
}
