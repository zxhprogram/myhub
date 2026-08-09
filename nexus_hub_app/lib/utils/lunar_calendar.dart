/// Lunar (Chinese traditional) calendar utilities.
///
/// Self-contained conversion between Gregorian dates and the lunisolar
/// Chinese calendar, using the canonical 1900-2099 data table. No external
/// dependencies. Each year's entry encodes:
///
/// - bits 4-15  : size of months 1-12 (1 = 30 days, 0 = 29 days)
/// - bits 0-3   : leap month index (0 = no leap month)
/// - bit 16     : size of the leap month (1 = 30 days, 0 = 29 days)
class LunarDate {
  const LunarDate({
    required this.year,
    required this.month,
    required this.day,
    required this.isLeapMonth,
  });

  /// Lunar year, e.g. 2024.
  final int year;

  /// Lunar month, 1-12. When [isLeapMonth] is true this is the leap month
  /// following the same-numbered regular month.
  final int month;

  /// Lunar day, 1-30.
  final int day;

  /// Whether this date falls in the leap month of the year.
  final bool isLeapMonth;

  /// Ganzhi year string, e.g. "甲辰".
  String get ganzhiYear => _ganzhiYear(year);

  /// Chinese zodiac animal, e.g. "龙".
  String get zodiac => _zodiac(year);

  /// Full display string, e.g. "甲辰年腊月十五".
  String get display => '$ganzhiYear年$monthName$dayName';

  /// Month name including leap prefix, e.g. "闰六月" or "正月".
  String get monthName =>
      isLeapMonth ? '闰${_monthNames[month - 1]}' : _monthNames[month - 1];

  /// Day name, e.g. "初一", "十五", "三十".
  String get dayName => _dayNames[day - 1];

  /// Short day label used inside calendar cells, e.g. "初一", "十五".
  /// For the first day of a month the month name is returned instead so the
  /// calendar can highlight month boundaries.
  String get shortLabel => day == 1 ? monthName : dayName;

  static const List<String> _monthNames = [
    '正月',
    '二月',
    '三月',
    '四月',
    '五月',
    '六月',
    '七月',
    '八月',
    '九月',
    '十月',
    '冬月',
    '腊月',
  ];

  static const List<String> _dayNames = [
    '初一',
    '初二',
    '初三',
    '初四',
    '初五',
    '初六',
    '初七',
    '初八',
    '初九',
    '初十',
    '十一',
    '十二',
    '十三',
    '十四',
    '十五',
    '十六',
    '十七',
    '十八',
    '十九',
    '二十',
    '廿一',
    '廿二',
    '廿三',
    '廿四',
    '廿五',
    '廿六',
    '廿七',
    '廿八',
    '廿九',
    '三十',
  ];

  static const List<String> _ganzhi = [
    '甲',
    '乙',
    '丙',
    '丁',
    '戊',
    '己',
    '庚',
    '辛',
    '壬',
    '癸',
  ];
  static const List<String> _branches = [
    '子',
    '丑',
    '寅',
    '卯',
    '辰',
    '巳',
    '午',
    '未',
    '申',
    '酉',
    '戌',
    '亥',
  ];
  static const List<String> _zodiacs = [
    '鼠',
    '牛',
    '虎',
    '兔',
    '龙',
    '蛇',
    '马',
    '羊',
    '猴',
    '鸡',
    '狗',
    '猪',
  ];

  /// Ganzhi year. The 60-year cycle is anchored so that year 4 CE is 甲子.
  static String _ganzhiYear(int year) {
    final i = (year - 4) % 60;
    return '${_ganzhi[i % 10]}${_branches[i % 12]}';
  }

  static String _zodiac(int year) => _zodiacs[(year - 4) % 12];

  @override
  String toString() => 'LunarDate($year-$month${isLeapMonth ? 'L' : ''}-$day)';
}

/// Converts a Gregorian [date] to its lunar equivalent.
///
/// Returns null for dates outside the supported 1900-01-31 .. 2099 range.
LunarDate? solarToLunar(DateTime date) {
  // Base epoch: 1900-01-31 corresponds to lunar 1900-01-01 (正月初一).
  final base = DateTime(1900, 1, 31);
  final offset = date.difference(base).inDays;
  if (offset < 0) return null;

  int year = 1900;
  int remaining = offset;
  int yearDays = _lunarYearDays(year);
  while (remaining >= yearDays) {
    remaining -= yearDays;
    year++;
    if (year > 2099) return null;
    yearDays = _lunarYearDays(year);
  }

  final leap = _leapMonth(year);
  bool isLeap = false;
  int month = 1;
  int monthDays = _monthDays(year, month);
  // Walk forward month by month. When a leap month exists for this year it
  // is inserted after its regular counterpart.
  while (remaining >= monthDays) {
    remaining -= monthDays;
    if (leap == month && !isLeap) {
      // Re-enter the same month number as a leap month.
      isLeap = true;
      monthDays = _leapDays(year);
    } else {
      isLeap = false;
      month++;
      if (month > 12) break;
      monthDays = _monthDays(year, month);
    }
  }

  return LunarDate(
    year: year,
    month: month,
    day: remaining + 1,
    isLeapMonth: isLeap,
  );
}

/// Returns the name of a traditional lunar festival for the given lunar date,
/// or null if the date is not a festival.
String? lunarFestival(LunarDate lunar) {
  if (lunar.isLeapMonth) return null;
  final key = '${lunar.month}-${lunar.day}';
  final fixed = _lunarFestivals[key];
  if (fixed != null) return fixed;
  // 除夕 falls on the last day of 腊月 (12th month). When 腊月 is a short
  // (29-day) month there is no 12-30, so 除夕 lands on 12-29 instead.
  if (lunar.month == 12 &&
      lunar.day == 29 &&
      _monthDays(lunar.year, 12) == 29) {
    return '除夕';
  }
  return null;
}

/// Returns the name of a solar term / public festival for a Gregorian date,
/// or null. Covers the fixed-date Gregorian festivals commonly shown on
/// Chinese calendars.
String? solarFestival(DateTime date) {
  final key = '${date.month}-${date.day}';
  return _solarFestivals[key];
}

const Map<String, String> _lunarFestivals = {
  '1-1': '春节',
  '1-15': '元宵节',
  '2-2': '龙抬头',
  '5-5': '端午节',
  '7-7': '七夕节',
  '7-15': '中元节',
  '8-15': '中秋节',
  '9-9': '重阳节',
  '12-8': '腊八节',
  '12-23': '小年',
  '12-30': '除夕',
  // Last day of the year is sometimes 29 (小月); treat 12-29 as a fallback
  //除夕 only when there is no 12-30, handled by caller.
};

const Map<String, String> _solarFestivals = {
  '1-1': '元旦',
  '2-14': '情人节',
  '3-8': '妇女节',
  '3-12': '植树节',
  '4-1': '愚人节',
  '5-1': '劳动节',
  '5-4': '青年节',
  '6-1': '儿童节',
  '7-1': '建党节',
  '8-1': '建军节',
  '9-10': '教师节',
  '10-1': '国庆节',
  '12-25': '圣诞节',
};

// --- Lunar data table and helpers ------------------------------------------

/// Lunar calendar data for 1900-2099. See class doc for the bit layout.
const List<int> _lunarInfo = [
  0x04bd8,
  0x04ae0,
  0x0a570,
  0x054d5,
  0x0d260,
  0x0d950,
  0x16554,
  0x056a0,
  0x09ad0,
  0x055d2, // 1900
  0x04ae0,
  0x0a5b6,
  0x0a4d0,
  0x0d250,
  0x1d255,
  0x0b540,
  0x0d6a0,
  0x0ada2,
  0x095b0,
  0x14977, // 1910
  0x04970,
  0x0a4b0,
  0x0b4b5,
  0x06a50,
  0x06d40,
  0x1ab54,
  0x02b60,
  0x09570,
  0x052f2,
  0x04970, // 1920
  0x06566,
  0x0d4a0,
  0x0ea50,
  0x06e95,
  0x05ad0,
  0x02b60,
  0x186e3,
  0x092e0,
  0x1c8d7,
  0x0c950, // 1930
  0x0d4a0,
  0x1d8a6,
  0x0b550,
  0x056a0,
  0x1a5b4,
  0x025d0,
  0x092d0,
  0x0d2b2,
  0x0a950,
  0x0b557, // 1940
  0x06ca0,
  0x0b550,
  0x15355,
  0x04da0,
  0x0a5b0,
  0x14573,
  0x052b0,
  0x0a9a8,
  0x0e950,
  0x06aa0, // 1950
  0x0aea6,
  0x0ab50,
  0x04b60,
  0x0aae4,
  0x0a570,
  0x05260,
  0x0f263,
  0x0d950,
  0x05b57,
  0x056a0, // 1960
  0x096d0,
  0x04dd5,
  0x04ad0,
  0x0a4d0,
  0x0d4d4,
  0x0d250,
  0x0d558,
  0x0b540,
  0x0b6a0,
  0x195a6, // 1970
  0x095b0,
  0x049b0,
  0x0a974,
  0x0a4b0,
  0x0b27a,
  0x06a50,
  0x06d40,
  0x0af46,
  0x0ab60,
  0x09570, // 1980
  0x04af5,
  0x04970,
  0x064b0,
  0x074a3,
  0x0ea50,
  0x06b58,
  0x055c0,
  0x0ab60,
  0x096d5,
  0x092e0, // 1990
  0x0c960,
  0x0d954,
  0x0d4a0,
  0x0da50,
  0x07552,
  0x056a0,
  0x0abb7,
  0x025d0,
  0x092d0,
  0x0cab5, // 2000
  0x0a950,
  0x0b4a0,
  0x0baa4,
  0x0ad50,
  0x055d9,
  0x04ba0,
  0x0a5b0,
  0x15176,
  0x052b0,
  0x0a930, // 2010
  0x07954,
  0x06aa0,
  0x0ad50,
  0x05b52,
  0x04b60,
  0x0a6e6,
  0x0a4e0,
  0x0d260,
  0x0ea65,
  0x0d530, // 2020
  0x05aa0,
  0x076a3,
  0x096d0,
  0x04afb,
  0x04ad0,
  0x0a4d0,
  0x1d0b6,
  0x0d250,
  0x0d520,
  0x0dd45, // 2030
  0x0b5a0,
  0x056d0,
  0x055b2,
  0x049b0,
  0x0a577,
  0x0a4b0,
  0x0aa50,
  0x1b255,
  0x06d20,
  0x0ada0, // 2040
  0x14b63,
  0x09370,
  0x049f8,
  0x04970,
  0x064b0,
  0x168a6,
  0x0ea50,
  0x06b20,
  0x1a6c4,
  0x0aae0, // 2050
  0x0a2e0,
  0x0d2e3,
  0x0c960,
  0x0d557,
  0x0d4a0,
  0x0da50,
  0x05d55,
  0x056a0,
  0x0a6d0,
  0x055d4, // 2060
  0x052d0,
  0x0a9b8,
  0x0a950,
  0x0b4a0,
  0x0b6a6,
  0x0ad50,
  0x055a0,
  0x0aba4,
  0x0a5b0,
  0x052b0, // 2070
  0x0b273,
  0x06930,
  0x07337,
  0x06aa0,
  0x0ad50,
  0x14b55,
  0x04b60,
  0x0a570,
  0x054e4,
  0x0d160, // 2080
  0x0e968,
  0x0d520,
  0x0daa0,
  0x16aa6,
  0x056d0,
  0x04ae0,
  0x0a9d4,
  0x0a2d0,
  0x0d150,
  0x0f252, // 2090
  0x0d520, // 2099
];

int _leapMonth(int year) => _lunarInfo[year - 1900] & 0xf;

int _leapDays(int year) {
  if (_leapMonth(year) == 0) return 0;
  return (_lunarInfo[year - 1900] & 0x10000) != 0 ? 30 : 29;
}

int _monthDays(int year, int month) {
  return (_lunarInfo[year - 1900] & (0x10000 >> month)) != 0 ? 30 : 29;
}

int _lunarYearDays(int year) {
  var sum = 348; // 12 months, base 29 days each = 348.
  // Add the extra day for each big (30-day) month.
  for (int i = 0x8000; i > 0x8; i >>= 1) {
    if ((_lunarInfo[year - 1900] & i) != 0) sum++;
  }
  return sum + _leapDays(year);
}
