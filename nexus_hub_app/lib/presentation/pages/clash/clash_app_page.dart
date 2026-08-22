import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../states/clash_state.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_button.dart';
import '../../layout/page_scaffold.dart';
import 'clash_connections_view.dart';
import 'clash_dashboard_view.dart';
import 'clash_logs_view.dart';
import 'clash_profiles_view.dart';
import 'clash_proxies_view.dart';
import 'clash_settings_view.dart';

/// Sidebar entry of the Clash console, ported from FlClash's
/// `Navigation.getItems()` (dashboard / proxies / profiles / connections /
/// logs).
class _ClashNavItem {
  const _ClashNavItem({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

const _navItems = [
  _ClashNavItem(label: '概览', icon: LucideIcons.gauge),
  _ClashNavItem(label: '代理', icon: LucideIcons.layers),
  _ClashNavItem(label: '订阅', icon: LucideIcons.cloudDownload),
  _ClashNavItem(label: '连接', icon: LucideIcons.cable),
  _ClashNavItem(label: '日志', icon: LucideIcons.list),
  _ClashNavItem(label: '设置', icon: LucideIcons.settings),
];

/// The Clash virtual app: a console for a running Clash/mihomo core.
///
/// The core functionality (proxies, connections, logs, traffic, mode
/// switching) is ported from FlClash; instead of FlClash's in-process core
/// bridge it drives an external core over the standard external controller
/// API, so any core (mihomo, FlClash's own, Clash Verge …) can be attached.
class ClashAppPage extends StatefulWidget {
  const ClashAppPage({super.key});

  @override
  State<ClashAppPage> createState() => _ClashAppPageState();
}

class _ClashAppPageState extends State<ClashAppPage> {
  int _viewIndex = 0;

  @override
  void initState() {
    super.initState();
    ClashState.instance.ensureAutoConnect();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PageScaffold(
      header: Row(
        children: [
          Icon(
            LucideIcons.shield,
            size: 22,
            color: colorScheme.primary,
          ),
          const SizedBox(width: NexusSpacing.sm),
          Text('Clash 控制台', style: NexusTypography.headlineSm),
          const SizedBox(width: NexusSpacing.md),
          const _ClashStatusBadge(),
          const Spacer(),
          const _ClashConnectButton(),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNavRail(context),
          const SizedBox(width: NexusSpacing.md),
          Expanded(child: _buildView()),
        ],
      ),
    );
  }

  Widget _buildNavRail(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 112,
      padding: const EdgeInsets.all(NexusSpacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _navItems.length; i++) ...[
            if (i > 0) const SizedBox(height: NexusSpacing.xs),
            _buildNavItem(context, i),
          ],
        ],
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = _navItems[index];
    final selected = _viewIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _viewIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.sm,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 16,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.mutedForeground,
            ),
            const SizedBox(width: NexusSpacing.sm),
            Expanded(
              child: Text(
                item.label,
                style: NexusTypography.labelMd.copyWith(
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.mutedForeground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildView() {
    return switch (_viewIndex) {
      0 => ClashDashboardView(onOpenSettings: () => setState(() => _viewIndex = 5)),
      1 => const ClashProxiesView(),
      2 => ClashProfilesView(onOpenProxies: () => setState(() => _viewIndex = 1)),
      3 => const ClashConnectionsView(),
      4 => const ClashLogsView(),
      _ => const ClashSettingsView(),
    };
  }
}

/// Live connection status indicator in the page header.
class _ClashStatusBadge extends StatelessWidget {
  const _ClashStatusBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final status = ClashState.instance.status.value;
      final message = ClashState.instance.statusMessage.value;

      final (label, color) = switch (status) {
        ClashStatus.connected => ('已连接', const Color(0xFF22C55E)),
        ClashStatus.connecting => ('连接中', const Color(0xFFF59E0B)),
        ClashStatus.error => ('连接失败', colorScheme.destructive),
        ClashStatus.disconnected => ('未连接', colorScheme.mutedForeground),
      };

      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.sm,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              message.isEmpty ? label : '$label：$message',
              style: NexusTypography.labelSm.copyWith(
                color: colorScheme.foreground,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    });
  }
}

/// Connect / disconnect action in the page header.
class _ClashConnectButton extends StatelessWidget {
  const _ClashConnectButton();

  @override
  Widget build(BuildContext context) {
    return Watch((_) {
      final state = ClashState.instance;
      final status = state.status.value;
      final connected = status == ClashStatus.connected;
      final connecting = status == ClashStatus.connecting;

      return NexusButton(
        label: connected ? '断开' : (connecting ? '连接中' : '连接'),
        icon: connected ? LucideIcons.x : LucideIcons.plug,
        isLoading: connecting,
        variant: connected
            ? NexusButtonVariant.outlined
            : NexusButtonVariant.filled,
        onPressed: connecting
            ? null
            : () {
                if (connected) {
                  state.disconnect();
                } else {
                  state.connect();
                }
              },
      );
    });
  }
}
