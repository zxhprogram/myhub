import 'dart:convert';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../components/nexus_toast.dart';
import 'package:flutter/services.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_button.dart';
import '../components/nexus_card.dart';
import '../components/nexus_diff_viewer.dart';
import '../components/nexus_input.dart';

class DevToolsPage extends StatefulWidget {
  const DevToolsPage({super.key});

  @override
  State<DevToolsPage> createState() => _DevToolsPageState();
}

class _DevToolsPageState extends State<DevToolsPage> {
  final _searchController = TextEditingController();
  int _selectedIndex = 0;
  bool _sidebarExpanded = true;

  static const _tools = [
    _ToolDef('JSON Formatter', LucideIcons.braces),
    _ToolDef('JWT Decoder', LucideIcons.keyRound),
    _ToolDef('Base64 Encode/Decode', LucideIcons.code),
    _ToolDef('RegEx Tester', LucideIcons.listChecks),
    _ToolDef('Password Generator', LucideIcons.keyRound),
    _ToolDef('Color Converter', LucideIcons.palette),
    _ToolDef('URL Parser', LucideIcons.globe),
    _ToolDef('Diff Viewer', LucideIcons.gitCompare),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MapEntry<int, _ToolDef>> get _filteredToolEntries {
    final query = _searchController.text.trim().toLowerCase();
    return _tools.asMap().entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.value.title.toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return const _JsonFormatterCard();
      case 7:
        return const NexusDiffViewer();
      default:
        return _PlaceholderToolCard(title: _tools[_selectedIndex].title);
    }
  }

  /// The Diff Viewer fills the available height with its own internal
  /// scrolling, so it must not be wrapped in a SingleChildScrollView.
  Widget _buildScrollableContent() {
    final content = _buildContent();
    if (_selectedIndex == 7) return content;
    return SingleChildScrollView(child: content);
  }

  void _selectTool(int index) => setState(() => _selectedIndex = index);

  void _toggleSidebar() => setState(() => _sidebarExpanded = !_sidebarExpanded);

  void _onSearchChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.background,
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DevTools', style: NexusTypography.headlineXl),
          const SizedBox(height: NexusSpacing.xs),
          Text(
            'Handy utilities for everyday development',
            style: NexusTypography.bodyMd.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: NexusSpacing.md),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                final toolEntries = _filteredToolEntries;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ToolSidebar(
                        toolEntries: toolEntries,
                        selectedIndex: _selectedIndex,
                        expanded: _sidebarExpanded,
                        searchController: _searchController,
                        onSearchChanged: _onSearchChanged,
                        onToggleExpand: _toggleSidebar,
                        onSelect: _selectTool,
                      ),
                      const SizedBox(width: NexusSpacing.md),
                      Expanded(child: _buildScrollableContent()),
                    ],
                  );
                }
                return Column(
                  children: [
                    _ToolToolbar(
                      toolEntries: toolEntries,
                      selectedIndex: _selectedIndex,
                      searchController: _searchController,
                      onSearchChanged: _onSearchChanged,
                      onSelect: _selectTool,
                    ),
                    const SizedBox(height: NexusSpacing.md),
                    Expanded(child: _buildScrollableContent()),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolDef {
  const _ToolDef(this.title, this.icon);

  final String title;
  final IconData icon;
}

class _ToolSidebar extends StatelessWidget {
  const _ToolSidebar({
    required this.toolEntries,
    required this.selectedIndex,
    required this.expanded,
    required this.searchController,
    required this.onSearchChanged,
    required this.onToggleExpand,
    required this.onSelect,
  });

  final List<MapEntry<int, _ToolDef>> toolEntries;
  final int selectedIndex;
  final bool expanded;
  final TextEditingController searchController;
  final VoidCallback onSearchChanged;
  final VoidCallback onToggleExpand;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final width = expanded ? 220.0 : 64.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: width,
      child: NexusCard(
        padding: const EdgeInsets.all(NexusSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (expanded) ...[
              NexusInput(
                controller: searchController,
                hintText: 'Find a tool...',
                prefixIcon: const Icon(RadixIcons.magnifyingGlass, size: 18),
                onChanged: (_) => onSearchChanged(),
              ),
              const SizedBox(height: NexusSpacing.sm),
            ] else ...[
              IconButton.ghost(
  icon: const Icon(RadixIcons.magnifyingGlass, size: 20),
  onPressed: onToggleExpand,
),
              const SizedBox(height: NexusSpacing.sm),
            ],
            ...toolEntries.map((entry) {
              final index = entry.key;
              final tool = entry.value;
              return _SidebarItem(
                tool: tool,
                selected: index == selectedIndex,
                expanded: expanded,
                onTap: () => onSelect(index),
              );
            }),
            const SizedBox(height: NexusSpacing.sm),
            Align(
              alignment: expanded ? Alignment.centerRight : Alignment.center,
              child: IconButton.ghost(
  icon: Icon(
                  expanded ? RadixIcons.chevronLeft : RadixIcons.chevronRight,
                  size: 20,
                ),
  onPressed: onToggleExpand,
),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.tool,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final _ToolDef tool;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = GestureDetector(
  onTap: onTap,
  child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.sm),
          child: Row(
            children: [
              Icon(
                tool.icon,
                size: 20,
                color: selected ? colorScheme.primary : colorScheme.foreground,
              ),
              if (expanded) ...[
                const SizedBox(width: NexusSpacing.sm),
                Expanded(
                  child: Text(
                    tool.title,
                    style: NexusTypography.bodyMd.copyWith(
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.foreground,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
);
    if (expanded) return item;
    return Tooltip(
  tooltip: (context) => Text(tool.title),
  child: item,
);
  }
}

class _ToolToolbar extends StatelessWidget {
  const _ToolToolbar({
    required this.toolEntries,
    required this.selectedIndex,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSelect,
  });

  final List<MapEntry<int, _ToolDef>> toolEntries;
  final int selectedIndex;
  final TextEditingController searchController;
  final VoidCallback onSearchChanged;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      padding: const EdgeInsets.all(NexusSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: toolEntries.map((entry) {
                final index = entry.key;
                final tool = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(right: NexusSpacing.xs),
                  child: _ToolbarItem(
                    tool: tool,
                    selected: index == selectedIndex,
                    onTap: () => onSelect(index),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: NexusSpacing.sm),
          NexusInput(
            controller: searchController,
            hintText: 'Find a tool...',
            prefixIcon: const Icon(RadixIcons.magnifyingGlass, size: 18),
            onChanged: (_) => onSearchChanged(),
          ),
        ],
      ),
    );
  }
}

class _ToolbarItem extends StatelessWidget {
  const _ToolbarItem({
    required this.tool,
    required this.selected,
    required this.onTap,
  });

  final _ToolDef tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
  onTap: onTap,
  child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.sm,
            vertical: NexusSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tool.icon,
                size: 18,
                color: selected ? colorScheme.primary : colorScheme.foreground,
              ),
              const SizedBox(width: NexusSpacing.xs),
              Text(
                tool.title,
                style: NexusTypography.bodyMd.copyWith(
                  color: selected ? colorScheme.primary : colorScheme.foreground,
                ),
              ),
            ],
          ),
        ),
);
  }
}

class _PlaceholderToolCard extends StatelessWidget {
  const _PlaceholderToolCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      child: SizedBox(
        height: 320,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.hammer,
                size: 48,
                color: colorScheme.mutedForeground,
              ),
              const SizedBox(height: NexusSpacing.md),
              Text(title, style: NexusTypography.headlineSm),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                'This tool is not yet implemented.',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JsonFormatterCard extends StatefulWidget {
  const _JsonFormatterCard();

  @override
  State<_JsonFormatterCard> createState() => _JsonFormatterCardState();
}

class _JsonFormatterCardState extends State<_JsonFormatterCard> {
  final _inputController = TextEditingController();
  final _outputController = TextEditingController();
  String? _error;
  String _indent = '  ';

  static const _maxInputLength = 10 * 1024 * 1024;

  @override
  void dispose() {
    _inputController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  void _format({bool minify = false}) {
    final input = _inputController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _error = null;
        _outputController.text = '';
      });
      return;
    }

    if (input.length > _maxInputLength) {
      setState(() {
        _error = 'Input exceeds 10 MB limit.';
        _outputController.text = '';
      });
      return;
    }

    try {
      final dynamic decoded = jsonDecode(input);
      final encoder = minify
          ? const JsonEncoder()
          : JsonEncoder.withIndent(_indent);
      setState(() {
        _error = null;
        _outputController.text = encoder.convert(decoded);
      });
    } on FormatException catch (e) {
      setState(() {
        _error = 'Invalid JSON: ${e.message}';
        _outputController.text = '';
      });
    }
  }

  Future<void> _copyOutput() async {
    final text = _outputController.text;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      nexusToast(context, 'Copied to clipboard');
    }
  }

  Future<void> _pasteInput() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _inputController.text = text;
    _format();
  }

  void _clear() {
    _inputController.clear();
    _outputController.clear();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('JSON Formatter', style: NexusTypography.headlineSm),
          const SizedBox(height: NexusSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              final input = NexusInput(
                controller: _inputController,
                labelText: 'Input',
                hintText: 'Paste JSON here...',
                maxLines: 10,
              );
              final output = NexusInput(
                controller: _outputController,
                labelText: 'Formatted',
                hintText: 'Result will appear here...',
                maxLines: 10,
                enabled: false,
              );
              return isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: input),
                        const SizedBox(width: NexusSpacing.md),
                        Expanded(child: output),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 260, child: input),
                        const SizedBox(height: NexusSpacing.md),
                        SizedBox(height: 260, child: output),
                      ],
                    );
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: NexusSpacing.sm),
            Text(
              _error!,
              style: NexusTypography.labelSm.copyWith(color: colorScheme.destructive),
            ),
          ],
          const SizedBox(height: NexusSpacing.md),
          Wrap(
            spacing: NexusSpacing.sm,
            runSpacing: NexusSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              NexusButton(label: 'Format', onPressed: () => _format()),
              NexusButton(
                label: 'Minify',
                variant: NexusButtonVariant.outlined,
                onPressed: () => _format(minify: true),
              ),
              NexusButton(
                label: 'Paste',
                variant: NexusButtonVariant.text,
                onPressed: _pasteInput,
              ),
              NexusButton(
                label: 'Copy',
                variant: NexusButtonVariant.text,
                onPressed: _copyOutput,
              ),
              _IndentSelector(
                value: _indent,
                onChanged: (value) {
                  setState(() => _indent = value);
                  if (_outputController.text.isNotEmpty) {
                    _format();
                  }
                },
              ),
              const SizedBox(width: NexusSpacing.sm),
              NexusButton(
                label: 'Clear',
                variant: NexusButtonVariant.text,
                onPressed: _clear,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IndentSelector extends StatelessWidget {
  const _IndentSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Indent:', style: NexusTypography.labelSm),
        const SizedBox(width: NexusSpacing.xs),
        _IndentChip(
          label: '2',
          selected: value == '  ',
          onTap: () => onChanged('  '),
        ),
        const SizedBox(width: NexusSpacing.xs),
        _IndentChip(
          label: '4',
          selected: value == '    ',
          onTap: () => onChanged('    '),
        ),
      ],
    );
  }
}

class _IndentChip extends StatelessWidget {
  const _IndentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
  onTap: onTap,
  child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.sm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.border,
            ),
            borderRadius: NexusRadii.smRadius,
          ),
          child: Text(
            label,
            style: NexusTypography.labelSm.copyWith(
              color: selected ? colorScheme.primary : colorScheme.foreground,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
);
  }
}
