import 'dart:io';

import 'package:flutter/material.dart';

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
}) async {
  final recebidoCtrl = TextEditingController(text: recebidoPorInicial?.trim() ?? '');
  final svc = podService ?? EntregaPodService();
  String? fotoPath;
  String? fotoServidor;

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
                  if (fotoPath != null && File(fotoPath!).existsSync())
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(fotoPath!),
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final origem = await svc.selecionarFoto();
                      if (origem == null) return;
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
                      setLocal(() {
                        fotoPath = salvo;
                        fotoServidor = svc.caminhoRelativoServidorDe(salvo);
                      });
                    },
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(
                      fotoPath == null ? 'Anexar foto (opcional)' : 'Trocar foto',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
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
