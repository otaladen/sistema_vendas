class MensagemTemplate {
  const MensagemTemplate({
    required this.id,
    required this.nome,
    required this.canal,
    required this.evento,
    required this.textoBase,
    this.metaTemplateName = '',
    this.idioma = 'pt_BR',
    this.ativo = true,
    required this.criadoEm,
  });

  final String id;
  final String nome;
  final String canal; // whatsapp | sms
  final String evento; // manual | venda_finalizada
  final String textoBase;
  final String metaTemplateName;
  final String idioma;
  final bool ativo;
  final DateTime criadoEm;

  MensagemTemplate copyWith({
    String? id,
    String? nome,
    String? canal,
    String? evento,
    String? textoBase,
    String? metaTemplateName,
    String? idioma,
    bool? ativo,
    DateTime? criadoEm,
  }) {
    return MensagemTemplate(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      canal: canal ?? this.canal,
      evento: evento ?? this.evento,
      textoBase: textoBase ?? this.textoBase,
      metaTemplateName: metaTemplateName ?? this.metaTemplateName,
      idioma: idioma ?? this.idioma,
      ativo: ativo ?? this.ativo,
      criadoEm: criadoEm ?? this.criadoEm,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'canal': canal,
      'evento': evento,
      'textoBase': textoBase,
      'metaTemplateName': metaTemplateName,
      'idioma': idioma,
      'ativo': ativo,
      'criadoEm': criadoEm.toIso8601String(),
    };
  }

  factory MensagemTemplate.fromMap(Map<String, dynamic> map) {
    return MensagemTemplate(
      id: map['id'] as String? ?? '',
      nome: map['nome'] as String? ?? '',
      canal: map['canal'] as String? ?? 'whatsapp',
      evento: map['evento'] as String? ?? 'manual',
      textoBase: map['textoBase'] as String? ?? '',
      metaTemplateName: map['metaTemplateName'] as String? ?? '',
      idioma: map['idioma'] as String? ?? 'pt_BR',
      ativo: map['ativo'] as bool? ?? true,
      criadoEm:
          DateTime.tryParse(map['criadoEm'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
