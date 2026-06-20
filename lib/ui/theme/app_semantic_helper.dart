import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';

extension AppSemanticColorsContext on BuildContext {
  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>() ?? AppSemanticColors.claro;
}
