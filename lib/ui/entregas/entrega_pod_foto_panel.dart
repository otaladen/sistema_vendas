import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/app_config_repository.dart';
import '../../model/venda.dart';
import '../../services/entrega_pod_lan_service.dart';

/// Exibe dados do POD e foto (local, cache ou download LAN).
class EntregaPodFotoPanel extends StatefulWidget {
  const EntregaPodFotoPanel({
    super.key,
    required this.venda,
    this.configRepository,
    this.podeEditar = false,
    this.onEditar,
  });

  final Venda venda;
  final AppConfigRepository? configRepository;
  final bool podeEditar;
  final VoidCallback? onEditar;

  @override
  State<EntregaPodFotoPanel> createState() => _EntregaPodFotoPanelState();
}

class _EntregaPodFotoPanelState extends State<EntregaPodFotoPanel> {
  String? _caminhoFoto;
  bool _carregando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _resolverFoto();
  }

  @override
  void didUpdateWidget(covariant EntregaPodFotoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.venda.podRecebidoPor != widget.venda.podRecebidoPor ||
        oldWidget.venda.podFotoPath != widget.venda.podFotoPath ||
        oldWidget.venda.podFotoPathServidor != widget.venda.podFotoPathServidor ||
        oldWidget.venda.podRegistradoEm != widget.venda.podRegistradoEm) {
      _resolverFoto();
    }
  }

  Future<void> _resolverFoto() async {
    final v = widget.venda;
    if (v.podRecebidoPor.trim().isEmpty) return;

    final local = v.podFotoPath.trim();
    if (local.isNotEmpty && File(local).existsSync()) {
      setState(() {
        _caminhoFoto = local;
        _erro = null;
        _carregando = false;
      });
      return;
    }

    final servidor = v.podFotoPathServidor.trim();
    if (servidor.isEmpty) {
      setState(() {
        _caminhoFoto = null;
        _erro = null;
        _carregando = false;
      });
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    final lan = EntregaPodLanService();
    final path = await lan.baixarParaCache(
      podFotoPathServidor: servidor,
      podFotoPathLocal: local,
    );

    if (!mounted) return;
    setState(() {
      _carregando = false;
      if (path != null && File(path).existsSync()) {
        _caminhoFoto = path;
      } else if (servidor.isNotEmpty) {
        _erro =
            'Foto nao encontrada. Verifique a rede ou se a retencao ja removeu o arquivo.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.venda;
    if (v.podRecebidoPor.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final quando = v.podRegistradoEm != null
        ? fmt.format(v.podRegistradoEm!.toLocal())
        : null;

    return Card(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Prova de entrega (POD)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                if (widget.podeEditar && widget.onEditar != null)
                  TextButton.icon(
                    onPressed: widget.onEditar,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Alterar'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Recebido por: ${v.podRecebidoPor}'),
            if (v.podRegistradoPor.trim().isNotEmpty)
              Text(
                'Registrado por: ${v.podRegistradoPor}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (quando != null)
              Text(
                'Em: $quando',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (_carregando) ...[
              const SizedBox(height: 12),
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _erro!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),
            if (_caminhoFoto != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(_caminhoFoto!),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _carregando ? null : _resolverFoto,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Recarregar foto'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
