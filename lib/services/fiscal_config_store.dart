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
    this.emailContador = '',
    this.smtpHost = '',
    this.smtpPort = 587,
    this.smtpUser = '',
    this.smtpPassword = '',
    this.smtpFromEmail = '',
    this.smtpSsl = false,
    this.tokenConfiguradoNoServidor = false,
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
  final String emailContador;
  final String smtpHost;
  final int smtpPort;
  final String smtpUser;
  final String smtpPassword;
  final String smtpFromEmail;
  final bool smtpSsl;

  /// Terminal leve: token Focus existe no PC servidor (nao replica o segredo localmente).
  final bool tokenConfiguradoNoServidor;

  bool get homologacao => ambiente.trim().toLowerCase() != 'producao';

  bool get emailContadorConfigurado {
    final e = emailContador.trim();
    return e.contains('@') && e.length >= 5;
  }

  bool get smtpConfigurado {
    final host = smtpHost.trim();
    final from = smtpFromEmail.trim().isNotEmpty
        ? smtpFromEmail.trim()
        : smtpUser.trim();
    return host.isNotEmpty &&
        smtpPort > 0 &&
        smtpUser.trim().isNotEmpty &&
        smtpPassword.isNotEmpty &&
        from.contains('@');
  }

  bool get podeEnviarFechamentoEmail =>
      emailContadorConfigurado && smtpConfigurado;

  bool get configurado {
    final cnpj = cnpjEmitente.replaceAll(RegExp(r'\D'), '');
    final ie = inscricaoEstadualEmitente.replaceAll(RegExp(r'\D'), '');
    final tokenOk = tokenConfiguradoNoServidor ||
        (apiToken.trim().isNotEmpty && !apiToken.contains('SEU_TOKEN'));
    return apiBaseUrl.trim().isNotEmpty &&
        tokenOk &&
        cnpj.length == 14 &&
        cnpj != '00000000000000' &&
        ie.isNotEmpty;
  }

  /// Resposta de `GET /api/empresa/fiscal` (terminal leve).
  factory FiscalConfigDados.fromApiRemoto(
    Map<String, dynamic> raw, {
    int? regimeEmpresaConfig,
  }) {
    final padrao = FiscalConfigDados.fromConstantes();
    final cnpj =
        (raw['cnpjEmitente'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    final ie = (raw['inscricaoEstadualEmitente'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');
    final regimeApi = (raw['regimeTributarioEmitente'] as num?)?.toInt();
    final regime = regimeApi ?? regimeEmpresaConfig ?? padrao.regimeTributarioEmitente;
    final amb = (raw['ambiente'] ?? padrao.ambiente).toString().trim().toLowerCase();
    return FiscalConfigDados(
      apiBaseUrl: (raw['apiBaseUrl'] ?? padrao.apiBaseUrl).toString(),
      apiToken: '',
      cnpjEmitente:
          cnpj.length == 14 ? cnpj : padrao.cnpjEmitente,
      inscricaoEstadualEmitente:
          ie.isNotEmpty ? ie : padrao.inscricaoEstadualEmitente,
      regimeTributarioEmitente: regime.clamp(1, 3),
      ufEmitente: (raw['ufEmitente'] ?? padrao.ufEmitente).toString(),
      ambiente: amb == 'producao' ? 'producao' : 'homologacao',
      razaoSocialEmitente:
          (raw['razaoSocialEmitente'] ?? padrao.razaoSocialEmitente).toString(),
      tokenConfiguradoNoServidor: raw['tokenConfigurado'] == true,
    );
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
  static const _kEmailContador = 'fiscal_email_contador_v1';
  static const _kSmtpHost = 'fiscal_smtp_host_v1';
  static const _kSmtpPort = 'fiscal_smtp_port_v1';
  static const _kSmtpUser = 'fiscal_smtp_user_v1';
  static const _kSmtpPassword = 'fiscal_smtp_password_v1';
  static const _kSmtpFrom = 'fiscal_smtp_from_v1';
  static const _kSmtpSsl = 'fiscal_smtp_ssl_v1';

  static FiscalConfigDados? _cache;

  static FiscalConfigDados get efetivo =>
      _cache ?? FiscalConfigDados.fromConstantes();

  static Future<FiscalConfigDados> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final padrao = FiscalConfigDados.fromConstantes();
    final token = prefs.getString(_kToken)?.trim();
    final ambiente = prefs.getString(_kAmbiente)?.trim();
    final cnpj = prefs.getString(_kCnpj)?.replaceAll(RegExp(r'\D'), '');
    final ie = prefs.getString(_kIe)?.replaceAll(RegExp(r'\D'), '');
    final regimeSalvo = prefs.getInt(_kRegime);
    final port = prefs.getInt(_kSmtpPort) ?? 587;

    _cache = FiscalConfigDados(
      apiBaseUrl: padrao.apiBaseUrl,
      apiToken: (token != null && token.isNotEmpty) ? token : '',
      cnpjEmitente:
          (cnpj != null && cnpj.length == 14) ? cnpj : padrao.cnpjEmitente,
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
      emailContador: prefs.getString(_kEmailContador)?.trim() ?? '',
      smtpHost: prefs.getString(_kSmtpHost)?.trim() ?? '',
      smtpPort: port > 0 ? port : 587,
      smtpUser: prefs.getString(_kSmtpUser)?.trim() ?? '',
      smtpPassword: prefs.getString(_kSmtpPassword) ?? '',
      smtpFromEmail: prefs.getString(_kSmtpFrom)?.trim() ?? '',
      smtpSsl: prefs.getBool(_kSmtpSsl) ?? false,
    );
    return _cache!;
  }

  static Future<void> salvar({
    required String apiToken,
    required String ambiente,
    String? cnpjEmitente,
    String? inscricaoEstadualEmitente,
    int? regimeTributarioEmitente,
    String? emailContador,
    String? smtpHost,
    int? smtpPort,
    String? smtpUser,
    String? smtpPassword,
    String? smtpFromEmail,
    bool? smtpSsl,
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

    if (emailContador != null) {
      final e = emailContador.trim();
      if (e.isEmpty) {
        await prefs.remove(_kEmailContador);
      } else {
        await prefs.setString(_kEmailContador, e);
      }
    }
    if (smtpHost != null) {
      final h = smtpHost.trim();
      if (h.isEmpty) {
        await prefs.remove(_kSmtpHost);
      } else {
        await prefs.setString(_kSmtpHost, h);
      }
    }
    if (smtpPort != null && smtpPort > 0) {
      await prefs.setInt(_kSmtpPort, smtpPort);
    }
    if (smtpUser != null) {
      final u = smtpUser.trim();
      if (u.isEmpty) {
        await prefs.remove(_kSmtpUser);
      } else {
        await prefs.setString(_kSmtpUser, u);
      }
    }
    if (smtpPassword != null) {
      if (smtpPassword.isEmpty) {
        await prefs.remove(_kSmtpPassword);
      } else {
        await prefs.setString(_kSmtpPassword, smtpPassword);
      }
    }
    if (smtpFromEmail != null) {
      final f = smtpFromEmail.trim();
      if (f.isEmpty) {
        await prefs.remove(_kSmtpFrom);
      } else {
        await prefs.setString(_kSmtpFrom, f);
      }
    }
    if (smtpSsl != null) {
      await prefs.setBool(_kSmtpSsl, smtpSsl);
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

  /// Atualiza cache em memoria (ex.: snapshot da API no terminal leve).
  static void aplicarCache(FiscalConfigDados dados) {
    _cache = dados;
  }
}
