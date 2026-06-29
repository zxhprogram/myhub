import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_card.dart';
import '../components/nexus_input.dart';
import '../layout/page_scaffold.dart';

class DevToolsPage extends StatelessWidget {
  const DevToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = [
      ('JSON Formatter', Icons.data_object),
      ('JWT Decoder', Icons.vpn_key_outlined),
      ('Base64 Encode/Decode', Icons.integration_instructions),
      ('RegEx Tester', Icons.rule),
      ('Password Generator', Icons.password),
      ('Color Converter', Icons.palette_outlined),
      ('URL Parser', Icons.http),
      ('Diff Viewer', Icons.difference_outlined),
    ];

    return PageScaffold(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DevTools', style: NexusTypography.headlineXl),
          const SizedBox(height: NexusSpacing.xs),
          Text(
            'Handy utilities for everyday development',
            style: NexusTypography.bodyMd.copyWith(
              color: NexusColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          const NexusInput(
            hintText: 'Find a tool...',
            prefixIcon: Icon(Icons.search, size: 20),
          ),
          const SizedBox(height: NexusSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 900 ? 4 : 2;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: NexusSpacing.md,
                mainAxisSpacing: NexusSpacing.md,
                childAspectRatio: 1.4,
                children: tools
                    .map((tool) => _ToolCard(title: tool.$1, icon: tool.$2))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: NexusSpacing.md),
          const _JsonFormatterCard(),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return NexusCard(
      onTap: () {},
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: NexusColors.surfaceContainer,
              borderRadius: NexusRadii.lgRadius,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 24, color: NexusColors.secondary),
          ),
          const SizedBox(height: NexusSpacing.sm),
          Text(
            title,
            style: NexusTypography.bodyMd,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _JsonFormatterCard extends StatelessWidget {
  const _JsonFormatterCard();

  @override
  Widget build(BuildContext context) {
    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('JSON Formatter', style: NexusTypography.headlineSm),
          const SizedBox(height: NexusSpacing.md),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: NexusInput(
                  labelText: 'Input',
                  hintText: 'Paste JSON here...',
                  maxLines: 8,
                ),
              ),
              SizedBox(width: NexusSpacing.md),
              Expanded(
                child: NexusInput(
                  labelText: 'Formatted',
                  hintText: 'Result will appear here...',
                  maxLines: 8,
                ),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          Row(
            children: [
              FilledButton(onPressed: () {}, child: const Text('Format')),
              const SizedBox(width: NexusSpacing.sm),
              OutlinedButton(onPressed: () {}, child: const Text('Minify')),
            ],
          ),
        ],
      ),
    );
  }
}
