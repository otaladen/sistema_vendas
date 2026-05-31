import 'package:flutter/material.dart';

import '../../../model/funcionario.dart';

import 'funcionario_sidebar_kpis.dart';

/// Lista lateral de funcionarios (master-detail).
class FuncionarioListaSidebar extends StatelessWidget {
  const FuncionarioListaSidebar({
    super.key,
    required this.funcionarios,
    required this.selectedId,
    required this.filtroController,
    required this.somenteAtivos,
    required this.onSomenteAtivosChanged,
    required this.onFiltroChanged,
    required this.onSelect,
    required this.resumoRh,
    this.scrollController,
    this.compact = false,
    this.mostrarKpisEquipe = false,
    this.totalCadastrados = 0,
    this.totalAtivos = 0,
    this.folhaBaseAtivos = 0,
  });

  final List<Funcionario> funcionarios;
  final int? selectedId;
  final TextEditingController filtroController;
  final bool somenteAtivos;
  final ValueChanged<bool> onSomenteAtivosChanged;
  final VoidCallback onFiltroChanged;
  final void Function(Funcionario) onSelect;
  final String Function(Funcionario) resumoRh;
  final ScrollController? scrollController;
  final bool compact;
  final bool mostrarKpisEquipe;
  final int totalCadastrados;
  final int totalAtivos;
  final double folhaBaseAtivos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 12 : 14, compact ? 10 : 12, compact ? 12 : 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Equipe (${funcionarios.length})',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: filtroController,
                  onChanged: (_) => onFiltroChanged(),
                  decoration: InputDecoration(
                    labelText: 'Buscar na lista',
                    hintText: 'Nome, codigo, setor...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 6),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Somente ativos'),
                  selected: somenteAtivos,
                  onSelected: (v) => onSomenteAtivosChanged(v),
                ),
              ],
            ),
          ),
          if (mostrarKpisEquipe)
            FuncionarioSidebarKpis(
              totalCadastrados: totalCadastrados,
              totalAtivos: totalAtivos,
              folhaBaseAtivos: folhaBaseAtivos,
            ),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
          Expanded(
            child: funcionarios.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Nenhum funcionario encontrado.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    itemCount: funcionarios.length,
                    itemBuilder: (context, index) {
                      final f = funcionarios[index];
                      final selecionado = f.id == selectedId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color: selecionado
                              ? scheme.primaryContainer.withValues(alpha: 0.55)
                              : scheme.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: selecionado
                                  ? scheme.primary.withValues(alpha: 0.45)
                                  : scheme.outlineVariant.withValues(alpha: 0.55),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => onSelect(f),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: f.ativo
                                        ? scheme.primary.withValues(alpha: 0.12)
                                        : scheme.errorContainer.withValues(alpha: 0.35),
                                    child: Text(
                                      f.nomeCompleto.isNotEmpty
                                          ? f.nomeCompleto.trim()[0].toUpperCase()
                                          : '?',
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: f.ativo ? scheme.primary : scheme.error,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          f.nomeCompleto,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${f.codigoInterno} · ${resumoRh(f)}'
                                          '${f.ativo ? '' : ' · inativo'}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selecionado)
                                    Icon(Icons.check_circle, size: 18, color: scheme.primary),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
