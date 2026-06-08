import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/nfe_inutilizacao_store.dart';
import '../../domain/fiscal/nfe_inutilizacao_xml_local_service.dart';
import '../../services/focus_nfe_service.dart';

Future<void> showNfeInutilizacaoHistoricoDialog(
  BuildContext context,
  NfeInutilizacaoStore store, {
  FocusNfeService? focusNfe,
}) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => _NfeInutilizacaoHistoricoDialog(
      store: store,
      focusNfe: focusNfe,
    ),
  );
}

class _NfeInutilizacaoHistoricoDialog extends StatefulWidget {
  const _NfeInutilizacaoHistoricoDialog({
    required this.store,
    this.focusNfe,
  });

  final NfeInutilizacaoStore store;
  final FocusNfeService? focusNfe;

  @override
  State<_NfeInutilizacaoHistoricoDialog> createState() =>
      _NfeInutilizacaoHistoricoDialogState();
}

class _NfeInutilizacaoHistoricoDialogState
    extends State<_NfeInutilizacaoHistoricoDialog> {
  static final _fmt = DateFormat('dd/MM/yyyy HH:mm');

  late List<NfeInutilizacaoRegistro> _lista;
  final Set<String> _baixandoIds = {};
  bool _baixandoLote = false;

  @override
  void initState() {
    super.initState();
    _lista = widget.store.listar();
  }

  void _recarregar() {
    setState(() => _lista = widget.store.listar());
  }

  bool _temXmlLocal(NfeInutilizacaoRegistro r) {
    return NfeInutilizacaoXmlLocalService.possuiXmlLocal(
      storeDirectoryPath: widget.store.storeDirectoryPath,
      registroId: r.id,
    );
  }

  int get _faltantesComUrl => _lista
      .where(
        (r) =>
            r.sucesso &&
            !_temXmlLocal(r) &&
            r.urlXml.trim().isNotEmpty,
      )
      .length;

  Future<void> _baixarUm(NfeInutilizacaoRegistro r) async {
    if (_baixandoIds.contains(r.id)) return;
    setState(() => _baixandoIds.add(r.id));
    try {
      final res = await NfeInutilizacaoXmlLocalService.recuperarXml(
        storeDirectoryPath: widget.store.storeDirectoryPath,
        registro: r,
        focusNfe: widget.focusNfe,
      );
      if (!mounted) return;
      _recarregar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.mensagem),
          backgroundColor: res.sucesso ? null : Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _baixandoIds.remove(r.id));
      }
    }
  }

  Future<void> _baixarTodosFaltantes() async {
    if (_baixandoLote) return;
    final fila = _lista
        .where(
          (r) =>
              r.sucesso &&
              !_temXmlLocal(r) &&
              r.urlXml.trim().isNotEmpty,
        )
        .toList();
    if (fila.isEmpty) return;

    setState(() => _baixandoLote = true);
    var ok = 0;
    var falha = 0;
    try {
      for (final r in fila) {
        final res = await NfeInutilizacaoXmlLocalService.recuperarXml(
          storeDirectoryPath: widget.store.storeDirectoryPath,
          registro: r,
          focusNfe: widget.focusNfe,
        );
        if (res.sucesso && !res.jaExistia) ok++;
        if (!res.sucesso) falha++;
      }
      if (!mounted) return;
      _recarregar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            falha == 0
                ? '$ok XML(s) baixado(s).'
                : '$ok baixado(s); $falha falha(s). Verifique token Focus.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _baixandoLote = false);
    }
  }

  Widget _trailingXml(NfeInutilizacaoRegistro r) {
    if (!r.sucesso) {
      return Icon(Icons.close, color: Colors.red.shade400, size: 20);
    }
    if (_temXmlLocal(r)) {
      return Tooltip(
        message: 'XML arquivado neste PC',
        child: Icon(Icons.task_alt, color: Colors.green.shade700, size: 22),
      );
    }
    if (r.urlXml.trim().isEmpty) {
      return Tooltip(
        message: 'URL do XML nao salva (registro antigo)',
        child: Icon(Icons.link_off, color: Colors.grey.shade600, size: 20),
      );
    }
    final baixando = _baixandoIds.contains(r.id) || _baixandoLote;
    return OutlinedButton(
      onPressed: baixando ? null : () => _baixarUm(r),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: baixando
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Baixar XML'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Historico de inutilizacoes'),
      content: SizedBox(
        width: 560,
        height: 440,
        child: _lista.isEmpty
            ? const Center(
                child: Text('Nenhuma inutilizacao registrada neste computador.'),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_faltantesComUrl > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed:
                            _baixandoLote ? null : _baixarTodosFaltantes,
                        icon: _baixandoLote
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_download_outlined),
                        label: Text(
                          'Baixar $_faltantesComUrl XML(s) faltante(s)',
                        ),
                      ),
                    ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _lista.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = _lista[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            r.sucesso
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            color: r.sucesso
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                          title: Text(
                            'Serie ${r.serie}: ${r.numeroInicial} a ${r.numeroFinal}',
                          ),
                          subtitle: Text(
                            '${_fmt.format(r.registradaEm.toLocal())}'
                            '${r.usuarioLogin.isNotEmpty ? ' · ${r.usuarioLogin}' : ''}'
                            '${r.protocolo.isNotEmpty ? '\nProt. ${r.protocolo}' : ''}'
                            '\n${r.justificativa}',
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                          trailing: _trailingXml(r),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
