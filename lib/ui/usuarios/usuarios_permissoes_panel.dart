import 'package:flutter/material.dart';

import '../../domain/permissao_usuario.dart';
import 'usuario_form_state.dart';

class UsuariosPermissoesPanel extends StatefulWidget {
  const UsuariosPermissoesPanel({
    super.key,
    required this.form,
    required this.onChanged,
  });

  final UsuarioFormState form;
  final VoidCallback onChanged;

  @override
  State<UsuariosPermissoesPanel> createState() => _UsuariosPermissoesPanelState();
}

class _UsuariosPermissoesPanelState extends State<UsuariosPermissoesPanel> {
  final _expandidos = <PermissaoGrupo, bool>{
    for (final g in PermissaoUsuarioCatalogo.ordemGrupos) g: true,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final travado = widget.form.permissoesTravadas;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (travado)
          Card(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Administrador (Dono) possui todas as permissoes. '
                'Desative "Acesso total" para ajustar permissoes individuais.',
              ),
            ),
          ),
        for (final grupo in PermissaoUsuarioCatalogo.ordemGrupos)
          _buildGrupo(context, grupo, travado),
      ],
    );
  }

  Widget _buildGrupo(BuildContext context, PermissaoGrupo grupo, bool travado) {
    final itens = PermissaoUsuarioCatalogo.porGrupo(grupo);
    final marcados = itens.where((i) => widget.form.lerPermissao(i.chave)).length;
    final expandido = _expandidos[grupo] ?? true;

    return Card(
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Icon(grupo.icone, color: Theme.of(context).colorScheme.primary),
            title: Text(grupo.titulo),
            subtitle: Text('$marcados de ${itens.length} ativas'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!travado) ...[
                  TextButton(
                    onPressed: () {
                      for (final info in itens) {
                        widget.form.definirPermissao(info.chave, true);
                      }
                      widget.onChanged();
                      setState(() {});
                    },
                    child: const Text('Todas'),
                  ),
                  TextButton(
                    onPressed: () {
                      for (final info in itens) {
                        widget.form.definirPermissao(info.chave, false);
                      }
                      widget.onChanged();
                      setState(() {});
                    },
                    child: const Text('Nenhuma'),
                  ),
                ],
                Icon(expandido ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: () => setState(() => _expandidos[grupo] = !expandido),
          ),
          if (expandido)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: itens.map((info) {
                  final valor = widget.form.lerPermissao(info.chave);
                  return CheckboxListTile(
                    value: valor,
                    onChanged: travado
                        ? null
                        : (v) {
                            widget.form.definirPermissao(info.chave, v ?? false);
                            widget.onChanged();
                            setState(() {});
                          },
                    title: Text(info.titulo),
                    subtitle: Text(
                      info.descricao +
                          (info.dependeDe != null
                              ? '\nRecomendado com: ${_rotuloDep(info.dependeDe!)}'
                              : ''),
                    ),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _rotuloDep(PermissaoUsuario p) {
    return PermissaoUsuarioCatalogo.itens
        .firstWhere((i) => i.chave == p)
        .titulo;
  }
}
