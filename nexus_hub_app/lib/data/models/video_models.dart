// Data models for the video streaming sub-app.
//
// Data is scraped from netflixgc.com, a MacCMS V10 video site. The browse
// list comes from the site's JSON endpoint; detail and play pages are
// parsed out of the server-rendered HTML (see VideoSiteService).

/// One series entry in the browse/search list.
class VideoSeries {
  const VideoSeries({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.remarks,
    required this.blurb,
  });

  /// MacCMS vod id, e.g. `4631`.
  final int id;

  final String title;

  final String coverUrl;

  /// Broadcast state shown on the poster corner, e.g. `已完结` / `更新至12集`.
  final String remarks;

  /// Short synopsis (may be empty).
  final String blurb;

  factory VideoSeries.fromJson(Map<String, dynamic> json) {
    return VideoSeries(
      id: (json['vod_id'] as num?)?.toInt() ?? 0,
      title: (json['vod_name'] as String?) ?? '',
      coverUrl: (json['vod_pic'] as String?) ?? '',
      remarks: (json['vod_remarks'] as String?) ?? '',
      blurb: (json['vod_blurb'] as String?) ?? '',
    );
  }
}

/// Paged result wrapper for the browse list.
class VideoSeriesPage {
  const VideoSeriesPage({
    required this.items,
    required this.page,
    required this.pageCount,
    required this.total,
  });

  final List<VideoSeries> items;
  final int page;
  final int pageCount;
  final int total;
}

/// One playable episode inside a [VideoSource].
class VideoEpisode {
  const VideoEpisode({
    required this.index,
    required this.label,
    required this.playPath,
  });

  /// 1-based episode position within its source.
  final int index;

  /// Label as shown by the site, e.g. `1`, `第01集`.
  final String label;

  /// Site-relative play page path, e.g. `/vodplay/4631-5-1.html`.
  final String playPath;
}

/// One playback source ("播放源") of a series, e.g. `蓝光-1` or `1080P-2`.
class VideoSource {
  const VideoSource({required this.name, required this.episodes});

  final String name;
  final List<VideoEpisode> episodes;
}

/// Full detail of a series, scraped from its `/voddetail/{id}.html` page.
class VideoDetail {
  const VideoDetail({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.synopsis,
    required this.remarks,
    required this.year,
    required this.area,
    required this.actors,
    required this.genres,
    required this.score,
    required this.sources,
  });

  final int id;
  final String title;
  final String coverUrl;

  /// Full synopsis from the page's meta description.
  final String synopsis;

  final String remarks;

  /// Release year, e.g. `2003` (empty when unknown).
  final String year;

  /// Production region, e.g. `韩国` (empty when unknown).
  final String area;

  /// Actor list as a single display string.
  final String actors;

  /// Genre names, e.g. `剧情, 传记, 历史`.
  final String genres;

  /// Site rating out of 10 (null when unrated).
  final double? score;

  final List<VideoSource> sources;

  bool get hasEpisodes => sources.any((s) => s.episodes.isNotEmpty);
}

/// Resolved playback information for one episode.
///
/// The site encrypts the raw resource URL in each play page and hands it to a
/// cloud "parse" player that streams it back. [playerUrl] is the final
/// embeddable player address loaded inside the in-app WebView.
class VideoPlayInfo {
  const VideoPlayInfo({
    required this.title,
    required this.episodeLabel,
    required this.rawUrl,
    required this.playerUrl,
    required this.nextPlayPath,
  });

  /// Series name from the play page payload.
  final String title;

  /// Episode label to show in the player header.
  final String episodeLabel;

  /// Decrypted resource reference, e.g. `NBY-XMYAES20...|af3bd...`.
  final String rawUrl;

  /// Cloud parse player URL that actually plays [rawUrl].
  final String playerUrl;

  /// Site play path of the next episode within the same source, if any.
  final String? nextPlayPath;
}
