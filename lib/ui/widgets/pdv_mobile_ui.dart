import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// UI do PDV otimizada para telefone — nao altera o fluxo desktop/Windows.
bool get pdvPlataformaCelular =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Atalho com [BuildContext] (mesmo criterio da plataforma).
bool pdvUiCelular(BuildContext context) => pdvPlataformaCelular;
