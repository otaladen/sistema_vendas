import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/app_config_repository.dart';

/// Cliente em modo terminal leve (sem ObjectBox local): Windows, Android ou iOS.
///
/// Arquitetura definitiva:
/// - PC1 servidor: ObjectBox + LanApi :8788 (+ hub 8787 legado/opcional).
/// - Terminais (PC ou celular): so HTTP/WS na API :8788; sem banco local,
///   sem SyncService. Se o servidor cair, o terminal para.
bool modoTerminalLeveAtivo(EmpresaConfig config) {
  if (kIsWeb) return false;
  if (!(Platform.isWindows || Platform.isAndroid || Platform.isIOS)) {
    return false;
  }
  if (!config.redeSincronizacaoAtiva) return false;
  if (config.redeModoServidor) return false;
  return true;
}

/// ERP completo via API (P0–P3): libera todos os destinos do menu no terminal.
bool destinoPermitidoNoTerminalLeve(String destinoName) {
  switch (destinoName) {
    case 'inicio':
    case 'vendas':
    case 'pdv':
    case 'caixa':
    case 'estoque':
    case 'notasFiscais':
    case 'entregas':
    case 'financeiro':
    case 'cadastros':
    case 'configuracoes':
    case 'motorista':
      return true;
    default:
      return false;
  }
}

/// Todos os submenus liberados no terminal (API completa).
bool subCadastroPermitidoNoTerminalLeve(String subName) => true;

bool subDestinoPermitidoNoTerminalLeve(String subName) => true;
