import 'package:flutter/material.dart';

import '../../../domain/fiscal/fiscal_regime_padrao.dart';
import '../../../services/configuracoes_service.dart';
import '../../../services/fiscal_config_store.dart';
import '../../configuracoes/configuracoes_scope.dart';

/// Alerta de ambiente Focus (homologacao vs producao).
class NfeAmbienteBanner extends StatefulWidget {
  const NfeAmbienteBanner({super.key});

  @override
  State<NfeAmbienteBanner> createState() => _NfeAmbienteBannerState();
}

class _NfeAmbienteBannerState extends State<NfeAmbienteBanner> {
  FiscalConfigDados? _fiscal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    final svc = ConfiguracoesScope.maybeOf(context);
    final cfg = svc != null
        ? await svc.carregarFiscalGlobal()
        : await ConfiguracoesService.resolverFiscalGlobal();
    if (!mounted) return;
    setState(() => _fiscal = cfg);
  }

  @override
  Widget build(BuildContext context) {
    final fiscal = _fiscal;
    if (fiscal == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final homolog = fiscal.homologacao;
    final regime = FiscalRegimePadrao.regimeEfetivo(fiscal);
    final regimeTxt =
        '${FiscalRegimePadrao.rotuloRegime(regime)} · '
        '${FiscalRegimePadrao.resumoPadroesEmissao(regime)}';
    if (!homolog) {
      return Material(
        color: Colors.green.shade50,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.verified_outlined, color: Colors.green.shade800, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PRODUCAO — validade juridica. $regimeTxt',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.green.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Material(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.science_outlined, color: theme.colorScheme.error, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'HOMOLOGACAO — testes, sem validade fiscal. $regimeTxt',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
