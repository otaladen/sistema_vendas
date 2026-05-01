import 'package:shared_preferences/shared_preferences.dart';

class EmpresaConfig {
  const EmpresaConfig({
    this.nomeLoja = 'LOJA DE MATERIAIS',
    this.telefone = '',
    this.endereco = '',
    this.pastaPadraoPdf = '',
    this.impressoraPadrao = '',
    this.modeloPdf = 'cupom',
    this.rodapeNota = 'Documento nao fiscal',
    this.rodapeOrcamento = 'Este orcamento nao possui valor fiscal.',
    this.logoPath = '',
    this.limiteDivergenciaCaixa = 20,
  });

  final String nomeLoja;
  final String telefone;
  final String endereco;
  final String pastaPadraoPdf;
  final String impressoraPadrao;
  final String modeloPdf; // cupom | a4
  final String rodapeNota;
  final String rodapeOrcamento;
  final String logoPath;
  final double limiteDivergenciaCaixa;
}

class AppConfigRepository {
  static const _kNomeLoja = 'config_nome_loja';
  static const _kTelefone = 'config_telefone_loja';
  static const _kEndereco = 'config_endereco_loja';
  static const _kPastaPadraoPdf = 'config_pasta_padrao_pdf';
  static const _kImpressoraPadrao = 'config_impressora_padrao';
  static const _kModeloPdf = 'config_modelo_pdf';
  static const _kRodapeDocumento = 'config_rodape_documento'; // legado
  static const _kRodapeNota = 'config_rodape_nota';
  static const _kRodapeOrcamento = 'config_rodape_orcamento';
  static const _kLogoPath = 'config_logo_path';
  static const _kLimiteDivergenciaCaixa = 'config_limite_divergencia_caixa';

  Future<EmpresaConfig> carregarEmpresaConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return EmpresaConfig(
      nomeLoja: prefs.getString(_kNomeLoja) ?? 'LOJA DE MATERIAIS',
      telefone: prefs.getString(_kTelefone) ?? '',
      endereco: prefs.getString(_kEndereco) ?? '',
      pastaPadraoPdf: prefs.getString(_kPastaPadraoPdf) ?? '',
      impressoraPadrao: prefs.getString(_kImpressoraPadrao) ?? '',
      modeloPdf: prefs.getString(_kModeloPdf) ?? 'cupom',
      rodapeNota:
          prefs.getString(_kRodapeNota) ??
          prefs.getString(_kRodapeDocumento) ??
          'Documento nao fiscal',
      rodapeOrcamento:
          prefs.getString(_kRodapeOrcamento) ??
          'Este orcamento nao possui valor fiscal.',
      logoPath: prefs.getString(_kLogoPath) ?? '',
      limiteDivergenciaCaixa: prefs.getDouble(_kLimiteDivergenciaCaixa) ?? 20,
    );
  }

  Future<void> salvarEmpresaConfig(EmpresaConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNomeLoja, config.nomeLoja.trim().isEmpty ? 'LOJA DE MATERIAIS' : config.nomeLoja.trim());
    await prefs.setString(_kTelefone, config.telefone.trim());
    await prefs.setString(_kEndereco, config.endereco.trim());
    await prefs.setString(_kPastaPadraoPdf, config.pastaPadraoPdf.trim());
    await prefs.setString(_kImpressoraPadrao, config.impressoraPadrao.trim());
    await prefs.setString(_kModeloPdf, config.modeloPdf.trim().isEmpty ? 'cupom' : config.modeloPdf.trim());
    final rodapeNota = config.rodapeNota.trim().isEmpty
        ? 'Documento nao fiscal'
        : config.rodapeNota.trim();
    final rodapeOrcamento = config.rodapeOrcamento.trim().isEmpty
        ? 'Este orcamento nao possui valor fiscal.'
        : config.rodapeOrcamento.trim();
    await prefs.setString(_kRodapeNota, rodapeNota);
    await prefs.setString(_kRodapeOrcamento, rodapeOrcamento);
    await prefs.setString(_kRodapeDocumento, rodapeNota);
    await prefs.setString(_kLogoPath, config.logoPath.trim());
    await prefs.setDouble(
      _kLimiteDivergenciaCaixa,
      config.limiteDivergenciaCaixa < 0 ? 0 : config.limiteDivergenciaCaixa,
    );
  }
}
