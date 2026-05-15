import 'package:flutter/material.dart';

import '../services/print_service.dart';

/// Tela dedicada a impressora padrao (PDF / sistema operacional).
class ConfigImpressoraPage extends StatefulWidget {
  const ConfigImpressoraPage({super.key, required this.printService});

  final PrintService printService;

  @override
  State<ConfigImpressoraPage> createState() => _ConfigImpressoraPageState();
}

class _ConfigImpressoraPageState extends State<ConfigImpressoraPage> {
  List<String> _nomesImpressoras = const [];
  String? _selecionada;
  bool _carregando = true;
  String? _erroLista;

  static const _erpGap16 = 16.0;
  static const _erpGap24 = 24.0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erroLista = null;
    });
    try {
      final impressoras = await widget.printService.listarImpressorasDisponiveis();
      final salva = await widget.printService.obterNomeImpressoraSalva();
      final nomes = impressoras.map((p) => p.name).toList();
      if (!mounted) return;
      setState(() {
        _nomesImpressoras = nomes;
        if (salva.isEmpty) {
          _selecionada = null;
        } else if (nomes.contains(salva)) {
          _selecionada = salva;
        } else {
          _selecionada = null;
        }
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erroLista = 'Falha ao listar impressoras: $e';
      });
    }
  }

  Future<void> _salvar() async {
    final nome = (_selecionada ?? '').trim();
    await widget.printService.salvarImpressoraSelecionada(nome);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nome.isEmpty
              ? 'Configuracao limpa (nenhuma impressora padrao).'
              : 'Impressora padrao salva: $nome',
        ),
      ),
    );
  }

  Future<void> _imprimirTeste() async {
    try {
      final r = await widget.printService.imprimirTeste();
      if (!mounted) return;
      final msg = switch (r) {
        PrintTestOutcome.sentToDefaultPrinter =>
          'Teste enviado para a impressora configurada.',
        PrintTestOutcome.usedSystemDialog =>
          'Impressora salva nao encontrada na lista. Aberto o dialogo do sistema.',
        PrintTestOutcome.noSavedPrinter =>
          'Nenhuma impressora salva — use o dialogo do sistema para imprimir o teste.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao imprimir teste: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Impressora')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(_erpGap24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.75),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(_erpGap24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.print_outlined, color: cs.primary),
                          const SizedBox(width: 10),
                          Text(
                            'Impressora padrao (PDF)',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: _erpGap16),
                      Text(
                        'Em desktop, o sistema lista as impressoras instaladas. '
                        'Em Web ou celular, a lista pode ficar vazia — nesse caso use '
                        '"Imprimir pagina de teste" para abrir o dialogo nativo.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.68),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: _erpGap16),
                      if (_carregando)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        if (_erroLista != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: _erpGap16),
                            child: Text(
                              _erroLista!,
                              style: TextStyle(
                                color: cs.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        Text(
                          'Selecionar impressora',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface.withValues(alpha: 0.72),
                          ),
                        ),
                        const SizedBox(height: 8),
                        InputDecorator(
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: cs.surfaceContainerHighest.withValues(
                              alpha: 0.4,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: cs.outline.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              isExpanded: true,
                              value:
                                  _selecionada != null &&
                                      _nomesImpressoras.contains(_selecionada)
                                  ? _selecionada
                                  : null,
                              hint: Text(
                                _nomesImpressoras.isEmpty
                                    ? 'Nenhuma impressora detectada'
                                    : 'Escolha uma impressora',
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Nenhuma (dialogo ao imprimir)'),
                                ),
                                ..._nomesImpressoras.map(
                                  (n) => DropdownMenuItem<String?>(
                                    value: n,
                                    child: Text(
                                      n,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _selecionada = v),
                            ),
                          ),
                        ),
                        const SizedBox(height: _erpGap16),
                        Wrap(
                          spacing: _erpGap16,
                          runSpacing: 12,
                          alignment: WrapAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _carregando ? null : _carregar,
                              icon: const Icon(Icons.refresh_outlined),
                              label: const Text('Atualizar lista'),
                            ),
                            FilledButton.icon(
                              onPressed: _salvar,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('Salvar configuracao'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _imprimirTeste,
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: const Text('Imprimir pagina de teste'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
