import 'dart:io';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../data/services/image_cache_service.dart';

/// Remote image backed by [ImageCacheService]'s app-local disk cache.
///
/// Drop-in replacement for `Image.network` in the video sub-app: first
/// display downloads the file into the `cache` folder next to the
/// executable, later displays (including after an app restart) decode
/// the local file directly. While the download runs a neutral placeholder
/// is shown; failures fall through to [errorBuilder] like before.
class NexusCachedImage extends StatefulWidget {
  const NexusCachedImage({
    super.key,
    required this.url,
    this.fit,
    this.errorBuilder,
  });

  final String url;
  final BoxFit? fit;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  State<NexusCachedImage> createState() => _NexusCachedImageState();
}

class _NexusCachedImageState extends State<NexusCachedImage> {
  /// Monotonic request counter; completions of superseded loads (the URL
  /// changed while a download was in flight) never update the state.
  int _seq = 0;
  File? _file;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NexusCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    _file = null;
    _error = widget.url.isEmpty ? StateError('空图片地址') : null;
    if (_error != null) return;
    try {
      final file = await ImageCacheService.instance.getImage(widget.url);
      if (!mounted || seq != _seq) return;
      setState(() => _file = file);
    } catch (error) {
      if (!mounted || seq != _seq) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final error = _error;
    if (error != null) {
      return widget.errorBuilder?.call(context, error) ??
          const SizedBox.shrink();
    }
    if (file == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.accent,
      );
    }
    return Image.file(
      file,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (context, _, _) =>
          widget.errorBuilder?.call(context, StateError('图片解码失败')) ??
          const SizedBox.shrink(),
    );
  }
}
