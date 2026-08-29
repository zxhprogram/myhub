import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_card.dart';
import '../components/nexus_diff_viewer.dart';
import '../components/nexus_input.dart';
import '../components/nexus_json_formatter.dart';

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
        return const NexusJsonFormatter();
      case 7:
        return const NexusDiffViewer();
      default:
        return _PlaceholderToolCard(title: _tools[_selectedIndex].title);
    }
  }

  /// The JSON Formatter and Diff Viewer fill the available height with their
  /// own internal scrolling, so they must not be wrapped in a
  /// SingleChildScrollView.
  Widget _buildScrollableContent() {
    final content = _buildContent();
    if (_selectedIndex == 0 || _selectedIndex == 7) return content;
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
