import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../components/nexus_toast.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../layout/page_scaffold.dart';

/// Camera capture page.
///
/// Discovers the connected webcams, shows a live preview of the selected one
/// and supports taking photos and recording videos. Captures are saved into a
/// `NexusCamera` folder inside the documents directory and the folder contents
/// are listed on the right so previous captures stay reachable.
///
/// Uses the official `camera` plugin plus the community Windows backend
/// (`camera_windows`, which is not endorsed, so must be listed in pubspec).
class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

/// Capture mode of the page: photo or video.
enum _CaptureMode { photo, video }

class _CameraCapturePageState extends State<CameraCapturePage> {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  final List<CameraDescription> _cameras = [];
  final List<_CaptureEntry> _captures = [];
  int _selectedIndex = 0;
  _CaptureMode _mode = _CaptureMode.photo;
  bool _recording = false;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Loads previous captures, then discovers cameras and starts the preview.
  Future<void> _init() async {
    await _loadCaptures();

    List<CameraDescription> cameras;
    try {
      cameras = await _permissionSafeCameras();
      if (!mounted) return;
      setState(() {
        _cameras
          ..clear()
          ..addAll(cameras);
      });
    } catch (e) {
      if (mounted) _showError('无法获取摄像头列表：$e');
      return;
    }
    if (_cameras.isEmpty) {
      if (mounted) _showError('未检测到摄像头');
      return;
    }
    await _selectCamera(0);
  }

  /// Loads the current contents of the capture folder (newest first).
  Future<void> _loadCaptures() async {
    try {
      final dir = await _captureDirectory();
      if (!await dir.exists()) return;
      final files = await dir.list().toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      for (final file in files.whereType<File>()) {
        final name = p.basename(file.path).toLowerCase();
        final isPhoto =
            name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png');
        final isVideo = name.endsWith('.mp4') || name.endsWith('.mov');
        if (!isPhoto && !isVideo) continue;
        _captures.add(_CaptureEntry(path: file.path, video: isVideo));
      }
    } catch (_) {
      // The capture folder may not exist yet on a first run.
    }
  }

  /// Wraps native camera enumeration in a permission-aware call.
  Future<List<CameraDescription>> _permissionSafeCameras() async {
    try {
      return await availableCameras();
    } on CameraException catch (e) {
      // CameraException('cameraPermission', ...) is thrown on Android/iOS when
      // access was denied. On Windows the list simply comes back empty until
      // the Media Foundation webcam capability is granted.
      if (e.code == 'cameraPermission') {
        if (mounted) _showError('摄像头权限被拒绝，请在系统设置中允许访问摄像头');
      }
      rethrow;
    }
  }

  Future<void> _selectCamera(int index) async {
    if (index < 0 || index >= _cameras.length || _recording) return;
    setState(() {
      _selectedIndex = index;
      _switching = true;
    });

    final description = _cameras[index];
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: true,
    );
    final future = controller.initialize();
    _initializeFuture = future;
    try {
      await future;
    } catch (e) {
      if (mounted) {
        setState(() => _switching = false);
        _showError('摄像头初始化失败：$e');
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _controller = controller;
      _switching = false;
    });
  }

  /// Directory where photo/video captures are saved.
  Future<Directory> _captureDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'NexusCamera'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final xFile = await controller.takePicture();
      final dir = await _captureDirectory();
      final target = p.join(
        dir.path,
        'IMG_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.jpg',
      );
      await xFile.saveTo(target);
      if (mounted) {
        setState(() => _captures.insert(0, _CaptureEntry(path: target)));
        _showSnack('照片已保存');
      }
    } on CameraException catch (e) {
      if (mounted) _showError('拍照失败：${e.description}');
    }
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_recording) {
      try {
        final xFile = await controller.stopVideoRecording();
        final dir = await _captureDirectory();
        final target = p.join(
          dir.path,
          'VID_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.mp4',
        );
        await xFile.saveTo(target);
        if (mounted) {
          setState(() {
            _recording = false;
            _captures.insert(0, _CaptureEntry(path: target, video: true));
          });
          _showSnack('视频已保存');
        }
      } on CameraException catch (e) {
        setState(() => _recording = false);
        if (mounted) _showError('录制失败：${e.description}');
      }
    } else {
      try {
        await controller.startVideoRecording();
        if (mounted) setState(() => _recording = true);
      } on CameraException catch (e) {
        if (mounted) _showError('无法开始录制：${e.description}');
      }
    }
  }

  /// Selects a capture file in the system file manager.
  Future<void> _openInFolder(String path) async {
    if (!kIsWeb && Platform.isWindows) {
      await Process.start('explorer', ['/select,', path]);
    }
  }

  @override
  void dispose() {
    _initializeFuture?.ignore();
    _controller?.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    nexusToast(context, message, isError: true);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    nexusToast(context, message);
  }

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
              Text('Camera', style: NexusTypography.headlineXl),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                'Capture photos and videos from your webcam',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
          const _CameraBadge(),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCameraBar(),
          const SizedBox(height: NexusSpacing.md),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildPreviewPane()),
                const SizedBox(width: NexusSpacing.lg),
                SizedBox(width: 320, child: _buildCaptureList()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Row of camera selection chips and the photo/video mode toggle.
  Widget _buildCameraBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: NexusSpacing.sm,
      runSpacing: NexusSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, cam) in _cameras.indexed) ...[
          GestureDetector(
  onTap: () => _selectCamera(i),
  child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                horizontal: NexusSpacing.md,
                vertical: NexusSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: i == _selectedIndex
                    ? colorScheme.secondary
                    : colorScheme.accent,
                borderRadius: NexusRadii.mdRadius,
              ),
              child: Text(
                cam.name.isNotEmpty ? cam.name : 'Camera ${i + 1}',
                style: NexusTypography.labelMd.copyWith(
                  color: i == _selectedIndex
                      ? colorScheme.secondaryForeground
                      : colorScheme.mutedForeground,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
),
        ],
        const SizedBox(width: NexusSpacing.xs),
        _ModeToggle(
          mode: _mode,
          enabled: !_recording,
          onChanged: (mode) {
            if (!_recording) setState(() => _mode = mode);
          },
        ),
      ],
    );
  }

  Widget _buildPreviewPane() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.muted,
        borderRadius: NexusRadii.lgRadius,
        border: Border.all(color: colorScheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(child: _buildPreview()),
          _buildPreviewFooter(),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const _CenteredStatus(label: '正在启动摄像头…', busy: true);
    }
    if (_switching) {
      return const _CenteredStatus(label: '切换摄像头中…', busy: false);
    }
    return Center(child: CameraPreview(controller));
  }

  /// Bottom bar with the mode-aware capture button, state hint and folder link.
  Widget _buildPreviewFooter() {
    final colorScheme = Theme.of(context).colorScheme;
    final ready = _controller?.value.isInitialized ?? false;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.md,
        vertical: NexusSpacing.sm,
      ),
      color: colorScheme.card,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _mode == _CaptureMode.photo ? '拍照模式' : '录像模式',
              style: NexusTypography.labelMd,
            ),
          ),
          _CaptureButton(
            mode: _mode,
            recording: _recording,
            enabled: ready && !_switching,
            onTap: _mode == _CaptureMode.photo ? _takePhoto : _toggleRecording,
          ),
          const SizedBox(width: NexusSpacing.md),
          IconButton.ghost(
  onPressed: () async {
              final dir = await _captureDirectory();
              await _openInFolder(dir.path);
            },
  icon: const Icon(LucideIcons.folderOpen),
),
        ],
      ),
    );
  }

  Widget _buildCaptureList() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_captures.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        decoration: BoxDecoration(
          color: colorScheme.muted,
          borderRadius: NexusRadii.lgRadius,
        ),
        child: Column(
          children: [
            Icon(
              LucideIcons.images,
              size: 32,
              color: colorScheme.mutedForeground,
            ),
            const SizedBox(height: NexusSpacing.sm),
            Text('尚无捕获', style: NexusTypography.bodyMd),
            const SizedBox(height: NexusSpacing.xs),
            Text(
              '拍摄的照片和视频会保存在此文件夹',
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.muted,
        borderRadius: NexusRadii.lgRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: NexusSpacing.md,
              vertical: NexusSpacing.sm,
            ),
            color: colorScheme.accent,
            child: Text(
              '捕获记录 (${_captures.length})',
              style: NexusTypography.labelMd,
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(NexusSpacing.sm),
              itemCount: _captures.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: NexusSpacing.xs),
              itemBuilder: (context, index) => _CaptureTile(
                entry: _captures[index],
                onTap: () => _openInFolder(_captures[index].path),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A photo or video saved in the capture folder.
class _CaptureEntry {
  final String path;
  final bool video;

  const _CaptureEntry({required this.path, this.video = false});

  String get name => p.basename(path);

  IconData get icon => video ? LucideIcons.video : LucideIcons.image;
}

/// A single capture listed in the history panel.
class _CaptureTile extends StatelessWidget {
  const _CaptureTile({required this.entry, required this.onTap});

  final _CaptureEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
  onTap: onTap,
  child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.sm,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: colorScheme.card,
          borderRadius: NexusRadii.mdRadius,
          border: Border.all(color: colorScheme.border),
        ),
        child: Row(
          children: [
            Icon(entry.icon, size: 18, color: colorScheme.mutedForeground),
            const SizedBox(width: NexusSpacing.sm),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NexusTypography.labelMd,
              ),
            ),
            Icon(
              LucideIcons.folderOpen,
              size: 16,
              color: colorScheme.mutedForeground,
            ),
          ],
        ),
      ),
);
  }
}

/// Placeholder shown while the camera is initializing or unavailable.
class _CenteredStatus extends StatelessWidget {
  const _CenteredStatus({required this.label, required this.busy});

  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(height: NexusSpacing.sm),
          Text(label, style: NexusTypography.labelMd),
        ],
      ),
    );
  }
}

/// Segmented pill toggling between photo and video capture modes.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final _CaptureMode mode;
  final bool enabled;
  final ValueChanged<_CaptureMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(NexusSpacing.xs),
      decoration: BoxDecoration(
        color: colorScheme.accent,
        borderRadius: NexusRadii.fullRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeChip(
            label: '照片',
            icon: LucideIcons.camera,
            selected: mode == _CaptureMode.photo,
            enabled: enabled,
            onTap: () => onChanged(_CaptureMode.photo),
          ),
          const SizedBox(width: NexusSpacing.xs),
          _ModeChip(
            label: '视频',
            icon: LucideIcons.video,
            selected: mode == _CaptureMode.video,
            enabled: enabled,
            onTap: () => onChanged(_CaptureMode.video),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
  onTap: enabled && !selected ? onTap : null,
  child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.md,
          vertical: NexusSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.card
              : const Color(0x00000000),
          borderRadius: NexusRadii.fullRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.mutedForeground,
            ),
            const SizedBox(width: NexusSpacing.xs),
            Text(
              label,
              style: NexusTypography.labelMd.copyWith(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.mutedForeground,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
);
  }
}

/// Big shutter button; turns into a red rounded square while recording.
class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    required this.mode,
    required this.recording,
    required this.enabled,
    required this.onTap,
  });

  final _CaptureMode mode;
  final bool recording;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPhotoMode = mode == _CaptureMode.photo;
    final accent = isPhotoMode
        ? colorScheme.secondary
        : const Color(0xFFE23C3C);
    final color = recording ? const Color(0xFFE23C3C) : accent;
    return GestureDetector(
  onTap: enabled ? onTap : null,
  child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: enabled ? color : colorScheme.accent,
          shape: recording ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: recording ? BorderRadius.circular(10) : null,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Icon(
          recording
              ? LucideIcons.circleStop
              : isPhotoMode
              ? LucideIcons.camera
              : RadixIcons.dotFilled,
          color: enabled ? colorScheme.secondaryForeground : colorScheme.mutedForeground,
          size: 22,
        ),
      ),
);
  }
}

/// Decorative header badge showing the camera context.
class _CameraBadge extends StatelessWidget {
  const _CameraBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.md,
        vertical: NexusSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.secondary,
        borderRadius: NexusRadii.fullRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.camera, size: 16),
          const SizedBox(width: NexusSpacing.xs),
          Text('相机', style: NexusTypography.labelMd),
        ],
      ),
    );
  }
}
