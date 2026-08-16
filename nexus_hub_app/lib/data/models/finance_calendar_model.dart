/// One economic indicator or key event scraped from the fx678 weekly
/// financial calendar (https://rl.fx678.com/Index_week.html).
class FinanceCalendarEvent {
  FinanceCalendarEvent({
    required this.time,
    required this.countryCode,
    required this.name,
    required this.previousValue,
    required this.surveyValue,
    required this.actualValue,
    required this.importance,
    required this.detailUrl,
    this.isKeyEvent = false,
  });

  factory FinanceCalendarEvent.fromJson(Map<String, dynamic> json) {
    return FinanceCalendarEvent(
      time: json['time'] as String,
      countryCode: json['countryCode'] as String,
      name: json['name'] as String,
      previousValue: json['previousValue'] as String,
      surveyValue: json['surveyValue'] as String,
      actualValue: json['actualValue'] as String,
      importance: json['importance'] as String,
      detailUrl: json['detailUrl'] as String,
      isKeyEvent: (json['isKeyEvent'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'time': time,
      'countryCode': countryCode,
      'name': name,
      'previousValue': previousValue,
      'surveyValue': surveyValue,
      'actualValue': actualValue,
      'importance': importance,
      'detailUrl': detailUrl,
      'isKeyEvent': isKeyEvent,
    };
  }

  /// Scheduled clock time, e.g. `07:50`.
  final String time;

  /// Raw country flag class code from the source page, e.g. `usa`.
  final String countryCode;

  /// Localized country name, e.g. `美国`; empty when the source shows a
  /// placeholder flag (`null_flags`) for country-less rows.
  String get countryName =>
      FinanceCalendarCountry.names[countryCode] ?? countryCode;

  /// Indicator / event name, e.g. `美国 8月10日 SPDR黄金持仓-每日更新 (吨)`.
  final String name;

  /// 前值 (previous release), empty when unavailable.
  final String previousValue;

  /// 预测值 (survey/consensus), empty when unavailable.
  final String surveyValue;

  /// 公布值 (actual release), empty when not yet published.
  final String actualValue;

  /// Importance label: `高` for highlighted rows, empty otherwise.
  final String importance;

  /// Whether the entry has been released already (公布值 present).
  bool get isPublished => actualValue.isNotEmpty;

  /// Link to the indicator detail page on rl.fx678.com.
  final String detailUrl;

  /// `data-type="0"` rows are key events/holidays rather than indicators.
  final bool isKeyEvent;

  bool get isImportant => importance.contains('高');
}

/// One day of the weekly calendar: a date header plus its rows.
class FinanceCalendarDay {
  FinanceCalendarDay({required this.dateLabel, required this.weekday, required this.events});

  factory FinanceCalendarDay.fromJson(Map<String, dynamic> json) {
    return FinanceCalendarDay(
      dateLabel: json['dateLabel'] as String,
      weekday: json['weekday'] as String,
      events: (json['events'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(FinanceCalendarEvent.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dateLabel': dateLabel,
      'weekday': weekday,
      'events': events.map((e) => e.toJson()).toList(),
    };
  }

  /// `2026-08-10`
  final String dateLabel;

  /// `周一`
  final String weekday;

  final List<FinanceCalendarEvent> events;

  DateTime? get date => DateTime.tryParse(dateLabel);
}

/// Maps the flag CSS classes used on rl.fx678.com (`c_usa circle_flag`)
/// to display names. Keys follow the site's spelling, including its quirks:
/// `indea` for India, a capitalized `Norwegian`, and the `null_flags`
/// placeholder which maps to an empty (hidden) label.
abstract final class FinanceCalendarCountry {
  static const names = <String, String>{
    'usa': '美国',
    'china': '中国',
    'japan': '日本',
    'uk': '英国',
    'britain': '英国',
    'euro': '欧元区',
    'eu': '欧元区',
    'european_union': '欧元区',
    'germany': '德国',
    'france': '法国',
    'italy': '意大利',
    'spain': '西班牙',
    'portugal': '葡萄牙',
    'ireland': '爱尔兰',
    'greece': '希腊',
    'austria': '奥地利',
    'netherlands': '荷兰',
    'belgium': '比利时',
    'finland': '芬兰',
    'switzerland': '瑞士',
    'sweden': '瑞典',
    'norway': '挪威',
    'Norwegian': '挪威',
    'denmark': '丹麦',
    'poland': '波兰',
    'russia': '俄罗斯',
    'ukraine': '乌克兰',
    'canada': '加拿大',
    'australia': '澳大利亚',
    'newzealand': '新西兰',
    'new_zealand': '新西兰',
    'india': '印度',
    'indea': '印度',
    'brazil': '巴西',
    'mexico': '墨西哥',
    'singapore': '新加坡',
    'thailand': '泰国',
    'taiwan': '台湾地区',
    'hongkong': '香港',
    'hong_kong': '香港',
    'korea': '韩国',
    'southkorea': '韩国',
    'korea_south': '韩国',
    'turkey': '土耳其',
    'southafrica': '南非',
    'south_africa': '南非',
    'indonesia': '印度尼西亚',
    'malaysia': '马来西亚',
    'vietnam': '越南',
    'philippines': '菲律宾',
    'pakistan': '巴基斯坦',
    'saudiarabia': '沙特',
    'israel': '以色列',
    'uae': '阿联酋',
    'null_flags': '',
  };
}
