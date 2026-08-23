import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// UI density for the desktop shell.
enum NexusDensity { comfortable, compact }

/// Global density signal, persistence and resolved layout metrics.
///
/// Components read the static getters below inside a signals [Watch] scope;
/// because every getter reads [density], toggling the mode rebuilds exactly
/// the widgets that depend on it.
abstract final class NexusDensityController {
  static final density = signal<NexusDensity>(NexusDensity.comfortable);

  static const _storageKey = 'nexus_density_v1';

  /// Loads the persisted density. Storage failures keep the default.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_storageKey) == NexusDensity.compact.name) {
        density.value = NexusDensity.compact;
      }
    } catch (_) {
      // Persistence unavailable (e.g. tests); stay comfortable.
    }
  }

  static Future<void> set(NexusDensity value) async {
    density.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, value.name);
    } catch (_) {
      // Persistence is best-effort.
    }
  }

  static void toggle() => set(
        density.value == NexusDensity.compact
            ? NexusDensity.comfortable
            : NexusDensity.compact,
      );

  static bool get isCompact => density.value == NexusDensity.compact;

  // ---- Resolved metrics (compact / comfortable) ----

  /// Inner padding of cards and module surfaces.
  static double get cardPadding => isCompact ? 12 : 16;

  /// Corner radius of cards.
  static double get cardRadius => isCompact ? 10 : 16;

  /// Outer padding around window page content.
  static double get pagePadding => isCompact ? 12 : 16;

  /// Vertical gap between sections/cards in a page column.
  static double get sectionGap => isCompact ? 10 : 16;

  /// Height of in-page toolbars (mail toolbar etc.).
  static double get toolbarHeight => isCompact ? 48 : 64;

  /// Height of list section headers inside a page.
  static double get listHeaderHeight => isCompact ? 44 : 56;

  /// Vertical padding of dense list rows.
  static double get rowPadV => isCompact ? 5 : 8;
}
