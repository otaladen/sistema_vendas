import 'dart:io';

import 'package:flutter/foundation.dart';

/// Leitor por camera disponivel apenas em celular/tablet (Android/iOS).
bool get pdvLeitorCameraDisponivel =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
