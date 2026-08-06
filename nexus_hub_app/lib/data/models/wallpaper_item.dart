/// A single wallpaper sourced from the Bing daily wallpaper API.
class WallpaperItem {
  const WallpaperItem({
    required this.url,
    required this.thumbnailUrl,
    this.title = '',
    this.copyright = '',
    this.date = '',
  });

  /// Full-resolution (4K) image URL used as the desktop background.
  final String url;

  /// Small preview URL used in the wallpaper picker grid.
  final String thumbnailUrl;

  /// Bing's short title for the image (e.g. "生死渡口，勇者的史诗").
  final String title;

  /// Copyright / photographer attribution (e.g. "© Manoj Shah/Getty Images").
  final String copyright;

  /// The Bing start date (yyyyMMdd) identifying the wallpaper.
  final String date;

  /// Builds a [WallpaperItem] from the Bing HPImageArchive `images[]` entry.
  ///
  /// The API returns a relative `urlbase` such as
  /// `/th?id=OHR.MaraCrossing_ZH-CN8816902094`; the high- and low-resolution
  /// variants are derived by appending `_UHD.jpg` and choosing a size via
  /// the `w`/`h` query params.
  factory WallpaperItem.fromBingJson(Map<String, dynamic> json) {
    const baseUrl = 'https://www.bing.com';
    final urlbase = json['urlbase'] as String? ?? '';
    final uhdBase = urlbase.endsWith('_UHD.jpg')
        ? '$baseUrl$urlbase'
        : '$baseUrl${urlbase}_UHD.jpg';

    return WallpaperItem(
      url: '$uhdBase&pid=hp&w=3840&h=2160&rs=1&c=4',
      thumbnailUrl: '$uhdBase&pid=hp&w=400&h=225&rs=1&c=4',
      title: (json['title'] as String?) ?? '',
      copyright: (json['copyright'] as String?) ?? '',
      date: (json['startdate'] as String?) ?? '',
    );
  }

  factory WallpaperItem.fromJson(Map<String, dynamic> json) {
    return WallpaperItem(
      url: json['url'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      title: (json['title'] as String?) ?? '',
      copyright: (json['copyright'] as String?) ?? '',
      date: (json['date'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'thumbnailUrl': thumbnailUrl,
    'title': title,
    'copyright': copyright,
    'date': date,
  };
}
