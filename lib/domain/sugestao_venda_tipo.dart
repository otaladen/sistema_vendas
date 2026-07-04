/// Tipo de sugestao de venda (produto agregado).
enum SugestaoVendaTipo {
  complementar,
  acessorio,
  upsell;

  String get codigo => name;

  String get rotulo => switch (this) {
        SugestaoVendaTipo.complementar => 'Complementar',
        SugestaoVendaTipo.acessorio => 'Acessorio',
        SugestaoVendaTipo.upsell => 'Upsell',
      };

  static SugestaoVendaTipo fromCodigo(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'acessorio' => SugestaoVendaTipo.acessorio,
      'upsell' => SugestaoVendaTipo.upsell,
      _ => SugestaoVendaTipo.complementar,
    };
  }
}
