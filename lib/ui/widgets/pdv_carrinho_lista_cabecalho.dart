import 'package:flutter/material.dart';

import 'pdv_carrinho_linha_colunas.dart';
import 'pdv_mobile_ui.dart';

/// Cabecalho fino das colunas do carrinho PDV (padrao tabela ERP).
class PdvCarrinhoListaCabecalho extends StatelessWidget {
  const PdvCarrinhoListaCabecalho({
    super.key,
    this.alvosTouchAmplos = false,
    this.exibirColunaUnitario = false,
  });

  static const double altura = 26;

  final bool alvosTouchAmplos;
  final bool exibirColunaUnitario;

  TextStyle _estiloColuna(ThemeData theme, ColorScheme scheme) {
    return theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: PdvTipografia.listaCabecalho,
          height: 1.0,
          letterSpacing: 0.55,
          color: scheme.onSurface.withValues(alpha: 0.62),
        ) ??
        TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: PdvTipografia.listaCabecalho,
          height: 1.0,
          letterSpacing: 0.55,
          color: scheme.onSurface.withValues(alpha: 0.62),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final estilo = _estiloColuna(theme, scheme);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.62),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: SizedBox(
        height: altura,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PdvCarrinhoLinhaColunas.paddingHorizontal,
          ),
          child: PdvCarrinhoLinhaColunas.linha(
            entrega: Text('ENT.', style: estilo),
            codigo: Text(
              'CÓD.',
              style: estilo,
              textAlign: TextAlign.center,
            ),
            unidadeMedida: Text(
              'UNID.',
              style: estilo,
              textAlign: TextAlign.center,
            ),
            produto: Text('PRODUTO', style: estilo),
            unitario: exibirColunaUnitario
                ? Text(
                    'UNIT.',
                    style: estilo,
                    textAlign: TextAlign.right,
                  )
                : null,
            subtotal: Text(
              'SUBTOTAL',
              style: estilo,
              textAlign: TextAlign.right,
            ),
            grupoQuantidade: SizedBox(
              width: PdvCarrinhoLinhaColunas.larguraGrupoQuantidade(
                alvosTouchAmplos: alvosTouchAmplos,
              ),
              child: Center(
                child: Text('QTD', style: estilo, textAlign: TextAlign.center),
              ),
            ),
            tabelaPreco: Text(
              'TAB.',
              style: estilo,
              textAlign: TextAlign.center,
            ),
            acoes: PdvCarrinhoLinhaColunas.acoesCabecalhoDe(
              alvosTouchAmplos: alvosTouchAmplos,
              rotulo: Text(
                'AÇÕES',
                style: estilo,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
