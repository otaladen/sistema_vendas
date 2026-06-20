import 'package:flutter/material.dart';

import '../../domain/dashboard_alertas.dart';
import '../../domain/filtro_contas_pagar.dart';
import '../../domain/filtro_contas_receber.dart';
import '../../domain/main_menu_destino.dart';
import '../theme/app_modulo_cores.dart';

/// Faixa de alertas acionaveis no dashboard.
class DashboardAlertasStrip extends StatelessWidget {
  const DashboardAlertasStrip({
    super.key,
    required this.alertas,
    required this.onAlertaTap,
  });

  final List<DashboardAlerta> alertas;
  final void Function(DashboardAlerta alerta) onAlertaTap;

  @override
  Widget build(BuildContext context) {
    if (alertas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < alertas.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _AlertaCard(
            alerta: alertas[i],
            onTap: () => onAlertaTap(alertas[i]),
          ),
        ],
      ],
    );
  }
}

class _AlertaCard extends StatelessWidget {
  const _AlertaCard({required this.alerta, required this.onTap});

  final DashboardAlerta alerta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cor = alerta.corTema(context);
    return Material(
      color: cor.withValues(alpha: 0.1),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(alerta.icone, color: cor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alerta.titulo,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cor,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        alerta.detalhe,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cor.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Navegacao padrao ao tocar em um alerta do dashboard.
void navegarDashboardAlerta(
  BuildContext context, {
  required DashboardAlerta alerta,
  required void Function(MainMenuDestino destino) irModulo,
  required void Function(FiltroContasReceber filtro) irContasReceber,
  void Function(FiltroContasPagar filtro)? irContasPagar,
}) {
  if (alerta.filtroContasReceber != null) {
    irContasReceber(alerta.filtroContasReceber!);
    return;
  }
  if (alerta.filtroContasPagar != null && irContasPagar != null) {
    irContasPagar(alerta.filtroContasPagar!);
    return;
  }
  if (alerta.destino != null) {
    irModulo(alerta.destino!);
  }
}
