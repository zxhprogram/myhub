import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/github_models.dart';
import '../../data/services/github_api_service.dart';
import '../../data/services/github_auth_service.dart';
import '../../data/services/image_cache_service.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_button.dart';
import '../components/nexus_card.dart';
import '../components/nexus_input.dart';
import '../layout/page_scaffold.dart';

/// GitHub sub-app: OAuth device-flow sign-in plus the signed-in user's
/// profile, repositories and activity feed in a desktop two-column layout.
class GitHubPage extends StatefulWidget {
  const GitHubPage({super.key});

  @override
  State<GitHubPage> createState() => _GitHubPageState();
}

enum _GitHubView { loading, signedOut, signedIn }

enum _RepoFilter { all, public, private, sources, forks }

enum _ContentTab { repositories, activity }

class _GitHubPageState extends State<GitHubPage> {
  final GitHubAuthService _auth = GitHubAuthService.instance;
  final GitHubApiService _api = GitHubApiService();

  _GitHubView _view = _GitHubView.loading;
  GitHubUser? _user;
  List<GitHubRepo> _repos = [];
  List<GitHubEvent> _events = [];
  String? _error;
  bool _isRefreshing = false;

  // Content-pane UI state.
  _ContentTab _tab = _ContentTab.repositories;
  _RepoFilter _filter = _RepoFilter.all;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  /// Tries the persisted token; falls back to the sign-in screen when there
  /// is none or it has been revoked.
  Future<void> _restoreSession() async {
    final token = await _auth.getToken();
    if (token == null || token.isEmpty) {
      setState(() => _view = _GitHubView.signedOut);
      return;
    }
    try {
      final user = await _api.fetchAuthenticatedUser(token);
      if (!mounted) return;
      setState(() {
        _user = user;
        _view = _GitHubView.signedIn;
      });
      await _loadData();
    } on GitHubAuthException {
      if (!mounted) return;
      setState(() {
        _view = _GitHubView.signedOut;
        _error = null;
      });
    }
  }

  Future<void> _loadData() async {
    final token = await _auth.getToken();
    final user = _user;
    if (user == null) return;
    try {
      final results = await Future.wait([
        _api.fetchUserRepos(token),
        _api.fetchUserEvents(token, user.login),
      ]);
      if (!mounted) return;
      setState(() {
        _repos = results[0] as List<GitHubRepo>;
        _events = results[1] as List<GitHubEvent>;
        _error = null;
      });
    } on GitHubAuthException catch (e) {
      if (!mounted) return;
      if (e.message.contains('expired')) {
        await _auth.signOut();
        setState(() {
          _view = _GitHubView.signedOut;
          _user = null;
          _error = e.message;
        });
      } else {
        setState(() => _error = e.message);
      }
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    await _loadData();
    if (!mounted) return;
    setState(() => _isRefreshing = false);
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    setState(() {
      _user = null;
      _repos = [];
      _events = [];
      _view = _GitHubView.signedOut;
    });
  }

  // ---------------------------------------------------------------------------
  // Sign-in flows
  // ---------------------------------------------------------------------------

  /// Device-flow sign-in. Opens a modal with the user code and polls GitHub
  /// until the user finishes authorization in the browser.
  Future<void> _signInWithDeviceFlow() async {
    try {
      final start = await _auth.startDeviceFlow();
      if (!mounted) return;
      final granted = await showOverlay<bool>(
        context,
        DialogConfiguration<bool>(
          barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
          builder: (ctx) => _DeviceFlowDialog(start: start),
        ),
      ).future;
      if (granted != true) return;
      await _restoreSession();
    } on DioException {
      _showSignInError(
        'Could not reach GitHub. Check your network (or proxy) and try again.',
      );
    } on GitHubAuthException catch (e) {
      _showSignInError(e.message);
    }
  }

  Future<void> _signInWithToken(String token) async {
    try {
      final user = await _api.fetchAuthenticatedUser(token);
      await _auth.storeTokenManually(token);
      if (!mounted) return;
      setState(() {
        _user = user;
        _view = _GitHubView.signedIn;
      });
      await _loadData();
    } on GitHubAuthException {
      _showSignInError('The token was rejected by GitHub. Check the value and '
          'its scopes (read:user, repo).');
    } on DioException {
      _showSignInError(
        'Could not reach GitHub. Check your network (or proxy) and try again.',
      );
    }
  }

  void _showSignInError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PageScaffold(
      header: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('GitHub', style: NexusTypography.headlineXl),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                'Your account, repositories and activity',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
          if (_view == _GitHubView.signedIn)
            Row(children: [
              NexusButton(
                label: 'Refresh',
                variant: NexusButtonVariant.outlined,
                icon: LucideIcons.refreshCw,
                isLoading: _isRefreshing,
                onPressed: _refresh,
              ),
            ]),
        ],
      ),
      child: switch (_view) {
        _GitHubView.loading => _buildLoading(),
        _GitHubView.signedOut => _SignInPanel(
            error: _error,
            onDismissError: () => setState(() => _error = null),
            onDeviceFlow: _signInWithDeviceFlow,
            onToken: _signInWithToken,
          ),
        _GitHubView.signedIn => _buildSignedIn(context),
      },
    );
  }

  Widget _buildLoading() {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      child: SizedBox(
        height: 320,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignedIn(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: NexusSpacing.sidebarWidth,
          child: _ProfileSidebar(
            user: _user!,
            onSignOut: _signOut,
          ),
        ),
        const SizedBox(width: NexusSpacing.md),
        Expanded(
          child: _ContentPane(
            repos: _repos,
            events: _events,
            error: _error,
            tab: _tab,
            filter: _filter,
            search: _search,
            onTabChanged: (tab) => setState(() => _tab = tab),
            onFilterChanged: (f) => setState(() => _filter = f),
            onSearchChanged: (s) => setState(() => _search = s),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sign-in panel
// ---------------------------------------------------------------------------

class _SignInPanel extends StatefulWidget {
  const _SignInPanel({
    required this.error,
    required this.onDismissError,
    required this.onDeviceFlow,
    required this.onToken,
  });

  final String? error;
  final VoidCallback onDismissError;
  final Future<void> Function() onDeviceFlow;
  final Future<void> Function(String token) onToken;

  @override
  State<_SignInPanel> createState() => _SignInPanelState();
}

class _SignInPanelState extends State<_SignInPanel> {
  final _tokenController = TextEditingController();
  bool _showTokenEntry = false;
  bool _isSigningIn = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _startDeviceFlow() async {
    setState(() => _isSigningIn = true);
    try {
      await widget.onDeviceFlow();
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: NexusCard(
            padding: const EdgeInsets.all(NexusSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(64 * 0.23),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF4078C0), Color(0xFF24292E)],
                      ),
                    ),
                    child: const Icon(
                      LucideIcons.github,
                      color: Color(0xFFFFFFFF),
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: NexusSpacing.md),
                Center(
                  child: Text(
                    'Sign in to GitHub',
                    style: NexusTypography.headlineSm,
                  ),
                ),
                const SizedBox(height: NexusSpacing.xs),
                Center(
                  child: Text(
                    'Single sign-on via the OAuth device flow — '
                    'no password ever reaches this app.',
                    textAlign: TextAlign.center,
                    style: NexusTypography.bodyMd.copyWith(
                      color: colorScheme.mutedForeground,
                    ),
                  ),
                ),
                const SizedBox(height: NexusSpacing.lg),
                NexusButton(
                  label: 'Sign in with GitHub',
                  icon: LucideIcons.github,
                  isLoading: _isSigningIn,
                  onPressed: _startDeviceFlow,
                ),
                const SizedBox(height: NexusSpacing.xs),
                Text(
                  'A browser window will open at github.com/login/device — '
                  'enter the code shown here to grant access.',
                  textAlign: TextAlign.center,
                  style: NexusTypography.labelSm.copyWith(
                    color: colorScheme.mutedForeground,
                  ),
                ),
                const SizedBox(height: NexusSpacing.md),
                _OrDivider(),
                const SizedBox(height: NexusSpacing.md),
                if (!_showTokenEntry) ...[
                  Button.text(
                    onPressed: () =>
                        setState(() => _showTokenEntry = true),
                    child: const Text('Use a personal access token instead'),
                  ),
                ] else ...[
                  NexusInput(
                    controller: _tokenController,
                    labelText: 'Personal access token',
                    hintText: 'ghp_… (scopes: read:user, repo)',
                    obscureText: true,
                    onSubmitted: widget.onToken,
                  ),
                  const SizedBox(height: NexusSpacing.sm),
                  NexusButton(
                    label: 'Sign in with token',
                    variant: NexusButtonVariant.outlined,
                    onPressed: () => widget.onToken(_tokenController.text),
                  ),
                ],
                if (widget.error != null) ...[
                  const SizedBox(height: NexusSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(NexusSpacing.sm),
                    decoration: BoxDecoration(
                      borderRadius: NexusRadii.mdRadius,
                      color: colorScheme.destructive.withValues(alpha: 0.08),
                      border: Border.all(
                        color: colorScheme.destructive.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          LucideIcons.circleAlert,
                          size: 16,
                          color: colorScheme.destructive,
                        ),
                        const SizedBox(width: NexusSpacing.sm),
                        Expanded(
                          child: Text(
                            widget.error!,
                            style: NexusTypography.labelMd.copyWith(
                              color: colorScheme.destructive,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Container(height: 1, color: colorScheme.border),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.sm),
          child: Text(
            'or',
            style: NexusTypography.labelSm.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
        ),
        Expanded(
          child: Container(height: 1, color: colorScheme.border),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Device flow dialog
// ---------------------------------------------------------------------------

class _DeviceFlowDialog extends StatefulWidget {
  const _DeviceFlowDialog({required this.start});

  final DeviceFlowStart start;

  @override
  State<_DeviceFlowDialog> createState() => _DeviceFlowDialogState();
}

class _DeviceFlowDialogState extends State<_DeviceFlowDialog> {
  final GitHubAuthService _auth = GitHubAuthService.instance;

  Timer? _timer;
  int _interval;
  final DateTime _openedAt = DateTime.now();
  bool _copied = false;
  String? _error;
  bool _done = false;

  _DeviceFlowDialogState() : _interval = 0;

  @override
  void initState() {
    super.initState();
    _interval = widget.start.intervalSeconds;
    _schedulePoll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedulePoll() {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _interval), _poll);
  }

  Future<void> _poll() async {
    if (_done || !mounted) return;
    try {
      final poll = await _auth.pollForToken(widget.start.deviceCode);
      if (_done) return;
      if (poll.granted) {
        _done = true;
        if (mounted) closeOverlay<bool>(context, true);
        return;
      }
      if (poll.slowDown) {
        _interval += 5;
      }
      _schedulePoll();
    } on GitHubAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } on DioException {
      if (!mounted) return;
      setState(() => _error = 'Network error while waiting for GitHub.');
      _schedulePoll();
    }
  }

  Future<void> _openVerificationPage() async {
    final uri = Uri.tryParse(widget.start.verificationUri);
    if (uri == null || !uri.hasScheme) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.start.userCode));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final remaining = widget.start.expiresIn -
        DateTime.now().difference(_openedAt);
    return AlertDialog(
      title: const Text('Authorize this device'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '1. Open github.com/login/device in your browser\n'
              '2. Enter the code below to grant access',
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
            const SizedBox(height: NexusSpacing.md),
            // One-time code to type into the browser.
            GestureDetector(
              onTap: _copyCode,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: NexusSpacing.md,
                  vertical: NexusSpacing.md,
                ),
                decoration: BoxDecoration(
                  borderRadius: NexusRadii.mdRadius,
                  color: colorScheme.muted.withValues(alpha: 0.5),
                  border: Border.all(color: colorScheme.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.start.userCode,
                      style: NexusTypography.headlineSm.copyWith(
                        letterSpacing: 4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: NexusSpacing.sm),
                    Icon(
                      _copied ? LucideIcons.check : LucideIcons.copy,
                      size: 16,
                      color: colorScheme.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: NexusSpacing.md),
            NexusButton(
              label: 'Open github.com/login/device',
              variant: NexusButtonVariant.outlined,
              icon: LucideIcons.externalLink,
              onPressed: _openVerificationPage,
            ),
            const SizedBox(height: NexusSpacing.md),
            if (_error != null)
              Text(
                _error!,
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.destructive,
                ),
              )
            else
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: NexusSpacing.sm),
                  Text(
                    'Waiting for authorization… '
                    '${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: NexusTypography.labelMd.copyWith(
                      color: colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        Button.text(
          onPressed: () {
            _done = true;
            closeOverlay<bool>(context, false);
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _ProfileSidebar extends StatelessWidget {
  const _ProfileSidebar({required this.user, required this.onSignOut});

  final GitHubUser user;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: _ProxyAvatar(
              url: user.avatarUrl,
              login: user.login,
              size: 72,
            ),
          ),
          const SizedBox(height: NexusSpacing.sm),
          Center(
            child: Text(
              user.displayName,
              style: NexusTypography.headlineSm,
              textAlign: TextAlign.center,
            ),
          ),
          Center(
            child: Text(
              '@${user.login}',
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
          ),
          if (user.bio != null && user.bio!.isNotEmpty) ...[
            const SizedBox(height: NexusSpacing.sm),
            Text(
              user.bio!,
              style: NexusTypography.bodyMd,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: NexusSpacing.md),
          // Meta rows: company / location / email / joined.
          for (final (icon, text) in [
            if (user.company != null && user.company!.isNotEmpty)
              (LucideIcons.building2, user.company!),
            if (user.location != null && user.location!.isNotEmpty)
              (LucideIcons.mapPin, user.location!),
            if (user.email != null && user.email!.isNotEmpty)
              (LucideIcons.mail, user.email!),
            if (user.createdAt != null)
              (
                LucideIcons.calendar,
                'Joined ${_monthYear(user.createdAt!)}',
              ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: NexusSpacing.xs),
              child: Row(
                children: [
                  Icon(icon, size: 14, color: colorScheme.mutedForeground),
                  const SizedBox(width: NexusSpacing.sm),
                  Expanded(
                    child: Text(
                      text,
                      style: NexusTypography.labelMd,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: NexusSpacing.sm),
          Container(height: 1, color: colorScheme.border),
          const SizedBox(height: NexusSpacing.sm),
          // Follow stats in a three-column grid.
          Row(
            children: [
              _StatBlock(label: 'Followers', value: user.followers),
              _StatBlock(label: 'Following', value: user.following),
              _StatBlock(label: 'Repos', value: user.publicRepos),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          NexusButton(
            label: 'Sign out',
            variant: NexusButtonVariant.outlined,
            icon: LucideIcons.logOut,
            onPressed: onSignOut,
          ),
        ],
      ),
    );
  }

  static String _monthYear(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: NexusTypography.headlineSm,
          ),
          Text(
            label,
            style: NexusTypography.labelSm.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.login});

  final String login;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.center,
      color: colorScheme.accent,
      child: Text(
        login.isEmpty ? '?' : login.characters.first.toUpperCase(),
        style: NexusTypography.headlineSm.copyWith(
          color: colorScheme.primaryForeground,
        ),
      ),
    );
  }
}

/// Circular avatar loaded through [ImageCacheService], whose download path
/// retries via the system proxy when a direct fetch fails — raw
/// `Image.network` cannot honor the Windows proxy and breaks on networks
/// where GitHub's avatar CDN is only reachable through the proxy.
class _ProxyAvatar extends StatelessWidget {
  const _ProxyAvatar({
    required this.url,
    required this.login,
    this.size = 28,
  });

  final String url;
  final String login;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? _AvatarFallback(login: login)
            : FutureBuilder<File>(
                future: ImageCacheService.instance.getImage(url),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _AvatarFallback(login: login);
                  }
                  final file = snapshot.data;
                  if (file == null) {
                    return _AvatarFallback(login: login);
                  }
                  return Image.file(file, fit: BoxFit.cover);
                },
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Content pane: repositories / activity tabs
// ---------------------------------------------------------------------------

class _ContentPane extends StatelessWidget {
  const _ContentPane({
    required this.repos,
    required this.events,
    required this.error,
    required this.tab,
    required this.filter,
    required this.search,
    required this.onTabChanged,
    required this.onFilterChanged,
    required this.onSearchChanged,
  });

  final List<GitHubRepo> repos;
  final List<GitHubEvent> events;
  final String? error;
  final _ContentTab tab;
  final _RepoFilter filter;
  final String search;
  final ValueChanged<_ContentTab> onTabChanged;
  final ValueChanged<_RepoFilter> onFilterChanged;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tab strip + (for repositories) the search field share one row so
          // the horizontal space of a desktop window is used well.
          Row(
            children: [
              _SegmentedTabs(
                tab: tab,
                repoCount: repos.length,
                eventCount: events.length,
                onChanged: onTabChanged,
              ),
              const Spacer(),
              if (tab == _ContentTab.repositories)
                SizedBox(
                  width: 260,
                  child: TextField(
                    hintText: 'Search repositories…',
                    onChanged: onSearchChanged,
                  ),
                ),
            ],
          ),
          if (tab == _ContentTab.repositories) ...[
            const SizedBox(height: NexusSpacing.sm),
            Wrap(
              spacing: NexusSpacing.xs,
              runSpacing: NexusSpacing.xs,
              children: [
                for (final f in _RepoFilter.values)
                  _SelectableChip(
                    label: switch (f) {
                      _RepoFilter.all => 'All',
                      _RepoFilter.public => 'Public',
                      _RepoFilter.private => 'Private',
                      _RepoFilter.sources => 'Sources',
                      _RepoFilter.forks => 'Forks',
                    },
                    isSelected: filter == f,
                    onTap: () => onFilterChanged(f),
                  ),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: NexusSpacing.sm),
            Text(
              error!,
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.destructive,
              ),
            ),
          ],
          const SizedBox(height: NexusSpacing.sm),
          Expanded(
            child: tab == _ContentTab.repositories
                ? _buildRepos(context)
                : _buildActivity(context),
          ),
        ],
      ),
    );
  }

  List<GitHubRepo> get _filteredRepos {
    final query = search.trim().toLowerCase();
    return repos.where((repo) {
      final matchesFilter = switch (filter) {
        _RepoFilter.all => true,
        _RepoFilter.public => !repo.isPrivate,
        _RepoFilter.private => repo.isPrivate,
        _RepoFilter.sources => !repo.isFork,
        _RepoFilter.forks => repo.isFork,
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;
      return repo.fullName.toLowerCase().contains(query) ||
          (repo.description?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  Widget _buildRepos(BuildContext context) {
    final filtered = _filteredRepos;
    if (filtered.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.folderSearch,
        message: search.isEmpty
            ? 'No repositories match this filter.'
            : 'No repositories match "$search".',
      );
    }
    // Two-column grid uses the wide desktop window; reflows naturally when
    // the user resizes the window narrower.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 1100 ? 2 : 1;
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: NexusSpacing.md),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: NexusSpacing.sm,
            crossAxisSpacing: NexusSpacing.sm,
            childAspectRatio: 3.6,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) =>
              _RepoCard(repo: filtered[index]),
        );
      },
    );
  }

  Widget _buildActivity(BuildContext context) {
    if (events.isEmpty) {
      return const _EmptyState(
        icon: LucideIcons.activity,
        message: 'No recent activity.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: NexusSpacing.md),
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: NexusSpacing.xs),
      itemBuilder: (context, index) => _EventTile(event: events[index]),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({
    required this.tab,
    required this.repoCount,
    required this.eventCount,
    required this.onChanged,
  });

  final _ContentTab tab;
  final int repoCount;
  final int eventCount;
  final ValueChanged<_ContentTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: NexusRadii.mdRadius,
        color: colorScheme.muted.withValues(alpha: 0.4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SegmentedTab(
            icon: LucideIcons.bookMarked,
            label: 'Repositories ($repoCount)',
            isSelected: tab == _ContentTab.repositories,
            onTap: () => onChanged(_ContentTab.repositories),
          ),
          _SegmentedTab(
            icon: LucideIcons.activity,
            label: 'Activity ($eventCount)',
            isSelected: tab == _ContentTab.activity,
            onTap: () => onChanged(_ContentTab.activity),
          ),
        ],
      ),
    );
  }
}

class _SegmentedTab extends StatelessWidget {
  const _SegmentedTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          borderRadius: NexusRadii.smRadius,
          color: isSelected ? colorScheme.card : const Color(0x00000000),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? colorScheme.foreground
                  : colorScheme.mutedForeground,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: NexusTypography.labelMd.copyWith(
                color: isSelected
                    ? colorScheme.foreground
                    : colorScheme.mutedForeground,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepoCard extends StatelessWidget {
  const _RepoCard({required this.repo});

  final GitHubRepo repo;

  static const _languageColors = <String, Color>{
    'Dart': Color(0xFF00B4AB),
    'TypeScript': Color(0xFF3178C6),
    'JavaScript': Color(0xFFF1E05A),
    'Python': Color(0xFF3572A5),
    'Java': Color(0xFFB07219),
    'Go': Color(0xFF00ADD8),
    'Rust': Color(0xFFDEA584),
    'C': Color(0xFF555555),
    'C++': Color(0xFFF34B7D),
    'C#': Color(0xFF178600),
    'Kotlin': Color(0xFFA97BFF),
    'Swift': Color(0xFFF05138),
    'Ruby': Color(0xFF701516),
    'PHP': Color(0xFF4F5D95),
    'Shell': Color(0xFF89E051),
    'HTML': Color(0xFFE34C26),
    'CSS': Color(0xFF563D7C),
    'Vue': Color(0xFF41B883),
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      onTap: () => _openRepo(context),
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                repo.isPrivate ? LucideIcons.lock : LucideIcons.bookOpen,
                size: 14,
                color: colorScheme.mutedForeground,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  repo.fullName,
                  style: NexusTypography.labelMd.copyWith(
                    color: colorScheme.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (repo.isArchived) ...[
                const SizedBox(width: NexusSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: NexusRadii.fullRadius,
                    border: Border.all(
                      color: colorScheme.border,
                    ),
                  ),
                  child: Text(
                    'Archived',
                    style: NexusTypography.labelSm.copyWith(
                      fontSize: 9,
                      color: colorScheme.mutedForeground,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (repo.hasDescription) ...[
            const SizedBox(height: NexusSpacing.xs),
            Text(
              repo.description!,
              style: NexusTypography.bodyMd,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const Spacer(),
          Row(
            children: [
              if (repo.language != null) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _languageColors[repo.language!] ??
                        colorScheme.mutedForeground,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(repo.language!, style: NexusTypography.labelSm),
                const SizedBox(width: NexusSpacing.md),
              ],
              _IconStat(icon: LucideIcons.star, text: repo.formattedStars),
              const SizedBox(width: NexusSpacing.md),
              _IconStat(icon: LucideIcons.gitFork, text: repo.formattedForks),
              const Spacer(),
              Text(
                repo.updatedAt == null
                    ? ''
                    : 'Updated ${_relativeTime(repo.updatedAt!)}',
                style: NexusTypography.labelSm.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openRepo(BuildContext context) async {
    final uri = Uri.tryParse(repo.htmlUrl);
    if (uri == null || !uri.hasScheme) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _IconStat extends StatelessWidget {
  const _IconStat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colorScheme.mutedForeground),
        const SizedBox(width: 4),
        Text(text, style: NexusTypography.labelSm),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final GitHubEvent event;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(NexusSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: NexusRadii.mdRadius,
        border: Border.all(color: colorScheme.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProxyAvatar(url: event.actorAvatarUrl, login: event.actorLogin),
          const SizedBox(width: NexusSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.summary,
                  style: NexusTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (event.detail != null &&
                    event.type != 'PushEvent' &&
                    event.detail!.length < 200) ...[
                  const SizedBox(height: 2),
                  Text(
                    event.detail!,
                    style: NexusTypography.labelMd.copyWith(
                      color: colorScheme.mutedForeground,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  '${event.repoName} · ${_relativeTime(event.createdAt)}',
                  style: NexusTypography.labelSm.copyWith(
                    color: colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: NexusSpacing.sm),
          _EventIcon(type: event.type),
        ],
      ),
    );
  }
}

class _EventIcon extends StatelessWidget {
  const _EventIcon({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (type) {
      'PushEvent' => (LucideIcons.gitCommitHorizontal, const Color(0xFF30D158)),
      'CreateEvent' => (LucideIcons.filePlus2, const Color(0xFF30D158)),
      'DeleteEvent' => (LucideIcons.trash2, const Color(0xFFFF453A)),
      'WatchEvent' => (LucideIcons.star, const Color(0xFFFF9F0A)),
      'ForkEvent' => (LucideIcons.gitFork, const Color(0xFF64D2FF)),
      'IssuesEvent' => (LucideIcons.circleAlert, const Color(0xFFFF9F0A)),
      'IssueCommentEvent' => (LucideIcons.messageSquare, const Color(0xFF0A84FF)),
      'PullRequestEvent' => (LucideIcons.gitPullRequest, const Color(0xFFBF5AF2)),
      'PullRequestReviewEvent' => (
        LucideIcons.gitPullRequestArrow,
        const Color(0xFFBF5AF2),
      ),
      'PullRequestReviewCommentEvent' => (
        LucideIcons.messageSquare,
        const Color(0xFFBF5AF2),
      ),
      'ReleaseEvent' => (LucideIcons.tag, const Color(0xFF30D158)),
      'PublicEvent' => (LucideIcons.eye, const Color(0xFF30D158)),
      'MemberEvent' => (LucideIcons.userPlus, const Color(0xFF0A84FF)),
      'GollumEvent' => (LucideIcons.bookOpen, const Color(0xFF0A84FF)),
      _ => (LucideIcons.dot, colorScheme.mutedForeground),
    };
    return Icon(icon, size: 16, color: color);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: colorScheme.mutedForeground),
          const SizedBox(height: NexusSpacing.sm),
          Text(
            message,
            style: NexusTypography.bodyMd.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectableChip extends StatelessWidget {
  const _SelectableChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
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
          borderRadius: NexusRadii.fullRadius,
          color: isSelected ? colorScheme.primary : const Color(0x00000000),
          border: Border.all(
            color: isSelected
                ? const Color(0x00000000)
                : colorScheme.border.withValues(alpha: 0.6),
          ),
        ),
        child: Text(
          label,
          style: NexusTypography.labelSm.copyWith(
            color: isSelected
                ? colorScheme.primaryForeground
                : colorScheme.mutedForeground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _relativeTime(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).round()}mo ago';
  return '${(diff.inDays / 365).round()}y ago';
}
