import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/recado_loja_constantes.dart';
import '../../model/recado_loja.dart';
import '../../model/usuario_sistema.dart';

/// Faixa de recados nao lidos no painel Inicio.
class RecadosLojaFaixa extends StatelessWidget {
  const RecadosLojaFaixa({
    super.key,
    required this.recados,
    required this.usuario,
    required this.onAbrirTodos,
    required this.onMarcarLido,
  });

  final List<RecadoLoja> recados;
  final UsuarioSistema usuario;
  final VoidCallback onAbrirTodos;
  final void Function(RecadoLoja recado) onMarcarLido;

  @override
  Widget build(BuildContext context) {
    if (recados.isEmpty) return const SizedBox.shrink();

    final exibir = recados.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < exibir.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _RecadoCard(
            recado: exibir[i],
            onTap: onAbrirTodos,
            onMarcarLido: () => onMarcarLido(exibir[i]),
          ),
        ],
        if (recados.length > 3) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onAbrirTodos,
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: Text('Ver todos (${recados.length})'),
            ),
          ),
        ],
      ],
    );
  }
}

class _RecadoCard extends StatelessWidget {
  const _RecadoCard({
    required this.recado,
    required this.onTap,
    required this.onMarcarLido,
  });

  final RecadoLoja recado;
  final VoidCallback onTap;
  final VoidCallback onMarcarLido;

  Color _corPrioridade(BuildContext context) {
    switch (recado.prioridade) {
      case RecadoLojaPrioridade.urgente:
        return Colors.red.shade700;
      case RecadoLojaPrioridade.importante:
        return Colors.orange.shade800;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cor = _corPrioridade(context);
    final dataFmt = DateFormat('dd/MM HH:mm', 'pt_BR');
    final autor = recado.criadoPorNome.trim().isNotEmpty
        ? recado.criadoPorNome.trim()
        : recado.criadoPorLogin;
    final destino = RecadoLojaDestino.rotuloTipo(
      recado.destinoTipo,
      recado.destinoPerfil,
    );

    return Material(
      color: cor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: cor.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.campaign_outlined, color: cor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              RecadoLojaPrioridade.rotulo(recado.prioridade),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: cor,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          Text(
                            destino,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        recado.texto,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$autor · ${dataFmt.format(recado.criadoEm.toLocal())}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Marcar como lido',
                  onPressed: onMarcarLido,
                  icon: Icon(Icons.done_all_outlined, color: cor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
