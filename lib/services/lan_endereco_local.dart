/// Tipo da placa de rede detectada neste PC (API :8788 em 0.0.0.0).
enum LanInterfaceTipo {
  ethernet,
  wifi,
  tailscale,
  outra,
}

/// IPv4 de uma interface ativa, com URL ja no formato http://IP:8788.
class LanEnderecoLocal {
  const LanEnderecoLocal({
    required this.nomeInterface,
    required this.ip,
    required this.tipo,
    required this.url,
    this.recomendadoPcs = false,
  });

  final String nomeInterface;
  final String ip;
  final LanInterfaceTipo tipo;
  final String url;
  final bool recomendadoPcs;

  String get rotuloTipo {
    switch (tipo) {
      case LanInterfaceTipo.ethernet:
        return 'Rede Cabeada (Ethernet / Principal para PCs da loja)';
      case LanInterfaceTipo.wifi:
        return 'Wi-Fi (Para celulares e tablets na loja)';
      case LanInterfaceTipo.tailscale:
        return 'VPN / Tailscale (Para acesso externo/remoto)';
      case LanInterfaceTipo.outra:
        return 'Outra rede';
    }
  }

  String get emoji {
    switch (tipo) {
      case LanInterfaceTipo.ethernet:
        return '🔌';
      case LanInterfaceTipo.wifi:
        return '📶';
      case LanInterfaceTipo.tailscale:
        return '🌐';
      case LanInterfaceTipo.outra:
        return '💻';
    }
  }

  String get rotuloCurto {
    switch (tipo) {
      case LanInterfaceTipo.ethernet:
        return 'Rede Cabeada';
      case LanInterfaceTipo.wifi:
        return 'Wi-Fi';
      case LanInterfaceTipo.tailscale:
        return 'VPN / Tailscale';
      case LanInterfaceTipo.outra:
        return 'Outra rede';
    }
  }
}
