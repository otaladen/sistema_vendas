import 'package:shared_preferences/shared_preferences.dart';

import '../config/fiscal_config.dart';

/// Dados efetivos da API Focus (SharedPreferences sobrescreve [FiscalConfig]).
class FiscalConfigDados {
  const FiscalConfigDados({
    required this.apiBaseUrl,
    required this.apiToken,
    required this.cnpjEmitente,
    required this.inscricaoEstadualEmitente,
    required this.regimeTributarioEmitente,
    required this.ufEmitente,
    required this.ambiente,
    this.razaoSocialEmitente = FiscalConfig.razaoSocialEmitente,
  });

  factory FiscalConfigDados.fromConstantes() {
    return FiscalConfigDados(
      apiBaseUrl: FiscalConfig.apiBaseUrl,
      apiToken: FiscalConfig.apiToken,
      cnpjEmitente: FiscalConfig.cnpjEmitente,
      inscricaoEstadualEmitente: FiscalConfig.inscricaoEstadualEmitente,
      regimeTributarioEmitente: FiscalConfig.regimeTributarioEmitente,
      ufEmitente: FiscalConfig.ufEmitente,
      ambiente: FiscalConfig.ambiente,
    );
  }

  final String apiBaseUrl;
  final String apiToken;
  final String cnpjEmitente;
  final String inscricaoEstadualEmitente;
  final int regimeTributarioEmitente;
  final String ufEmitente;
  final String ambiente;
  final String razaoSocialEmitente;

  bool get homologacao => ambiente.trim().toLowerCase() != 'producao';

  bool get configurado {
    final cnpj = cnpjEmitente.replaceAll(RegExp(r'\D'), '');
    final ie = inscricaoEstadualEmitente.replaceAll(RegExp(r'\D'), '');
    return apiBaseUrl.trim().isNotEmpty &&
        apiToken.trim().isNotEmpty &&
        !apiToken.contains('SEU_TOKEN') &&
        cnpj.length == 14 &&
        cnpj != '00000000000000' &&
        ie.isNotEmpty;
  }
}

/// Persistencia da configuracao fiscal (token/ambiente) fora do codigo-fonte.
abstract final class FiscalConfigStore {
  FiscalConfigStore._();

  static const _kToken = 'fiscal_focus_api_token_v1';
  static const _kAmbiente = 'fiscal_focus_ambiente_v1';
  static const _kCnpj = 'fiscal_focus_cnpj_v1';
  static const _kIe = 'fiscal_focus_ie_v1';
  static const _kRegime = 'fiscal_focus_regime_v1';

  static FiscalConfigDados? _cache;

  static FiscalConfigDados get efetivo => _cache ?? FiscalConfigDados.fromConstantes();

  static Future<FiscalConfigDados> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final padrao = FiscalConfigDados.fromConstantes();
    final token = prefs.getString(_kToken)?.trim();
    final ambiente = prefs.getString(_kAmbiente)?.trim();
    final cnpj = prefs.getString(_kCnpj)?.replaceAll(RegExp(r'\D'), '');
    final ie = prefs.getString(_kIe)?.replaceAll(RegExp(r'\D'), '');
    final regimeSalvo = prefs.getInt(_kRegime);

    _cache = FiscalConfigDados(
      apiBaseUrl: padrao.apiBaseUrl,
      apiToken: (token != null && token.isNotEmpty) ? token : padrao.apiToken,
      cnpjEmitente: (cnpj != null && cnpj.length == 14) ? cnpj : padrao.cnpjEmitente,
      inscricaoEstadualEmitente:
          (ie != null && ie.isNotEmpty) ? ie : padrao.inscricaoEstadualEmitente,
      regimeTributarioEmitente:
          (regimeSalvo != null && regimeSalvo >= 1 && regimeSalvo <= 3)
              ? regimeSalvo
              : padrao.regimeTributarioEmitente,
      ufEmitente: padrao.ufEmitente,
      ambiente: (ambiente == 'producao' || ambiente == 'homologacao')
          ? ambiente!
          : padrao.ambiente,
    );
    return _cache!;
  }

  static Future<void> salvar({
    required String apiToken,
    required String ambiente,
    String? cnpjEmitente,
    String? inscricaoEstadualEmitente,
    int? regimeTributarioEmitente,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = apiToken.trim();
    if (token.isEmpty) {
      await prefs.remove(_kToken);
    } else {
      await prefs.setString(_kToken, token);
    }

    final amb = ambiente.trim().toLowerCase();
    await prefs.setString(
      _kAmbiente,
      amb == 'producao' ? 'producao' : 'homologacao',
    );

    final cnpj = (cnpjEmitente ?? '').replaceAll(RegExp(r'\D'), '');
    if (cnpj.length == 14) {
      await prefs.setString(_kCnpj, cnpj);
    }

    final ie = (inscricaoEstadualEmitente ?? '').replaceAll(RegExp(r'\D'), '');
    if (ie.isNotEmpty) {
      await prefs.setString(_kIe, ie);
    }

    if (regimeTributarioEmitente != null) {
      await prefs.setInt(
        _kRegime,
        regimeTributarioEmitente.clamp(1, 3),
      );
    }

    await carregar();
  }

  /// Aplica regime vindo da [EmpresaConfig] sincronizada na LAN.
  static Future<void> aplicarRegimeEmpresa(int regime) async {
    final r = regime.clamp(1, 3);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kRegime, r);
    await carregar();
  }

  static Future<void> limparToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await carregar();
  }

  /// Configuracao pronta para emissao (preferir apos [carregar] no boot).
  static bool get configurado => efetivo.configurado;
}
