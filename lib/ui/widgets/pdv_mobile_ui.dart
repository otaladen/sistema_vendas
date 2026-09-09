import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// UI do PDV otimizada para telefone — nao altera o fluxo desktop/Windows.
bool get pdvPlataformaCelular =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Atalho com [BuildContext] (mesmo criterio da plataforma).
bool pdvUiCelular(BuildContext context) => pdvPlataformaCelular;

/// Escala tipografica densa do PDV (padrao ERP material de construcao).
abstract final class PdvTipografia {
  PdvTipografia._();

  static const double campoBusca = 12;
  static const double listaNome = 12;
  static const double listaValor = 12;
  static const double listaQuantidade = 12;
  static const double listaSecundario = 11;
  static const double listaMeta = 11;
  static const double listaCabecalho = 10;
  static const double listaPrecoInativo = 10;

  static const double alturaLinhaLista = 34;
}
