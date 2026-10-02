import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/nfe_revisao_preco.dart';

enum NfeRevisaoMargemAlerta { ok, abaixoMinimo, prejuizo }

/// Estado editavel da revisao de precos pos-NF-e (preco 1/2/3).
class NfeRevisaoPrecificacaoStore extends ChangeNotifier {
  NfeRevisaoPrecificacaoStore({
    required List<NfeRevisaoPrecoItem> itens,
    required this.margemMinimaLoja,
  }) : itens = List.unmodifiable(itens) {
    _preco1 = [
      for (final item in itens) _ctrlInicial(item.precoVendaSugerido, item.precoVendaAtual),
    ];
    _preco2 = [
      for (final item in itens) _ctrlInicial(item.preco2Sugerido, item.preco2Atual),
    ];
    _preco3 = [
      for (final item in itens) _ctrlInicial(item.preco3Sugerido, item.preco3Atual),
    ];
    for (var i = 0; i < itens.length; i++) {
      _preco1[i].addListener(_onCamposAlterados);
      _preco2[i].addListener(_onCamposAlterados);
      _preco3[i].addListener(_onCamposAlterados);
    }
  }

  static final NumberFormat _nfMoeda = NumberFormat('#,##0.00', 'pt_BR');
  static final NumberFormat _nfPct = NumberFormat('#,##0.0', 'pt_BR');

  final List<NfeRevisaoPrecoItem> itens;
  final double margemMinimaLoja;

  late final List<TextEditingController> _preco1;
  late final List<TextEditingController> _preco2;
  late final List<TextEditingController> _preco3;

  bool mostrarPreco2Preco3 = true;

  TextEditingController controllerPreco1(int i) => _preco1[i];
  TextEditingController controllerPreco2(int i) => _preco2[i];
  TextEditingController controllerPreco3(int i) => _preco3[i];

  void _onCamposAlterados() => notifyListeners();

  void setMostrarTabelasExtras(bool v) {
    if (mostrarPreco2Preco3 == v) return;
    mostrarPreco2Preco3 = v;
    notifyListeners();
  }

  static TextEditingController _ctrlInicial(double sugerido, double atual) {
    final v = sugerido > 0 ? sugerido : atual;
    return TextEditingController(text: _nfMoeda.format(v));
  }

  static String formatarMoeda(double v) => _nfMoeda.format(v);

  static String formatarReais(double v) => 'R\$ ${_nfMoeda.format(v)}';

  static String formatarVariacaoCusto(double? pct) {
    if (pct == null || !pct.isFinite) return '—';
    final sinal = pct > 0 ? '+' : '';
    return '$sinal${_nfPct.format(pct)}%';
  }

  static double? parseMoeda(String texto) {
    var valor = texto.trim();
    if (valor.isEmpty) return null;
    valor = valor
        .replaceAll('\u00A0', '')
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll(RegExp(r'r\$', caseSensitive: false), '');
    if (valor.isEmpty) return null;
    final direto = double.tryParse(valor);
    if (direto != null) return direto;
    final limpo = valor.replaceAll(RegExp(r'[^\d.,+\-eE]'), '');
    if (limpo.isEmpty) return null;
    final ultVirg = limpo.lastIndexOf(',');
    final ultPonto = limpo.lastIndexOf('.');
    if (ultVirg > ultPonto) {
      return double.tryParse(limpo.replaceAll('.', '').replaceAll(',', '.'));
    }
    return double.tryParse(limpo.replaceAll(',', '.'));
  }

  double? preco1Parsed(int i) => parseMoeda(_preco1[i].text);
  double? preco2Parsed(int i) => parseMoeda(_preco2[i].text);
  double? preco3Parsed(int i) => parseMoeda(_preco3[i].text);

  double margemPreco1Reativa(int i) {
    final preco = preco1Parsed(i);
    if (preco == null || preco <= 0) return 0;
    return NfeRevisaoPrecoCalculo.margemSobreVenda(preco, itens[i].custoNovo);
  }

  NfeRevisaoMargemAlerta alertaMargemPreco1(int i) {
    final preco = preco1Parsed(i);
    final custo = itens[i].custoNovo;
    if (preco == null || preco <= 0) return NfeRevisaoMargemAlerta.ok;
    if (custo > 0 && preco < custo - 0.0001) {
      return NfeRevisaoMargemAlerta.prejuizo;
    }
    final margem = NfeRevisaoPrecoCalculo.margemSobreVenda(preco, custo);
    if (margemMinimaLoja > 0 && margem + 0.05 < margemMinimaLoja) {
      return NfeRevisaoMargemAlerta.abaixoMinimo;
    }
    return NfeRevisaoMargemAlerta.ok;
  }

  void aplicarSugeridoEmTodos() {
    for (var i = 0; i < itens.length; i++) {
      final item = itens[i];
      _preco1[i].text = formatarMoeda(
        item.precoVendaSugerido > 0 ? item.precoVendaSugerido : item.precoVendaAtual,
      );
      _preco2[i].text = formatarMoeda(
        item.preco2Sugerido > 0 ? item.preco2Sugerido : item.preco2Atual,
      );
      _preco3[i].text = formatarMoeda(
        item.preco3Sugerido > 0 ? item.preco3Sugerido : item.preco3Atual,
      );
    }
    notifyListeners();
  }

  void repassarAumentoExatoEmTodos() {
    for (var i = 0; i < itens.length; i++) {
      final item = itens[i];
      _preco1[i].text = formatarMoeda(
        item.precoRepassandoAumentoCusto(item.precoVendaAtual),
      );
      _preco2[i].text = formatarMoeda(
        item.precoRepassandoAumentoCusto(item.preco2Atual),
      );
      _preco3[i].text = formatarMoeda(
        item.precoRepassandoAumentoCusto(item.preco3Atual),
      );
    }
    notifyListeners();
  }

  bool linhasValidas() {
    for (var i = 0; i < itens.length; i++) {
      final p1 = preco1Parsed(i);
      if (p1 == null || p1 < 0) return false;
      final p2 = preco2Parsed(i);
      if (p2 == null || p2 < 0) return false;
      final p3 = preco3Parsed(i);
      if (p3 == null || p3 < 0) return false;
    }
    return true;
  }

  List<
      ({
        NfeRevisaoPrecoItem item,
        double preco1,
        double preco2,
        double preco3,
      })> linhasParaAplicar() {
    final out =
        <
            ({
              NfeRevisaoPrecoItem item,
              double preco1,
              double preco2,
              double preco3,
            })>[];
    for (var i = 0; i < itens.length; i++) {
      final p1 = preco1Parsed(i);
      final p2 = preco2Parsed(i);
      final p3 = preco3Parsed(i);
      if (p1 == null || p2 == null || p3 == null) continue;
      out.add((item: itens[i], preco1: p1, preco2: p2, preco3: p3));
    }
    return out;
  }

  @override
  void dispose() {
    for (final c in _preco1) {
      c.dispose();
    }
    for (final c in _preco2) {
      c.dispose();
    }
    for (final c in _preco3) {
      c.dispose();
    }
    super.dispose();
  }
}
