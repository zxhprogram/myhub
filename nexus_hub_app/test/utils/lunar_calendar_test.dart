import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/utils/lunar_calendar.dart';

void main() {
  group('solarToLunar', () {
    test('2024 Spring Festival', () {
      final lunar = solarToLunar(DateTime(2024, 2, 10))!;
      expect(lunar.year, 2024);
      expect(lunar.month, 1);
      expect(lunar.day, 1);
      expect(lunar.isLeapMonth, false);
      expect(lunar.ganzhiYear, '甲辰');
      expect(lunar.zodiac, '龙');
      expect(lunarFestival(lunar), '春节');
    });

    test('2024 Dragon Boat Festival', () {
      final lunar = solarToLunar(DateTime(2024, 6, 10))!;
      expect(lunar.month, 5);
      expect(lunar.day, 5);
      expect(lunarFestival(lunar), '端午节');
    });

    test('2024 Mid-Autumn Festival', () {
      final lunar = solarToLunar(DateTime(2024, 9, 17))!;
      expect(lunar.month, 8);
      expect(lunar.day, 15);
      expect(lunarFestival(lunar), '中秋节');
    });

    test('2025 Spring Festival', () {
      final lunar = solarToLunar(DateTime(2025, 1, 29))!;
      expect(lunar.year, 2025);
      expect(lunar.month, 1);
      expect(lunar.day, 1);
      expect(lunar.ganzhiYear, '乙巳');
      expect(lunar.zodiac, '蛇');
    });

    test('2023 Spring Festival', () {
      final lunar = solarToLunar(DateTime(2023, 1, 22))!;
      expect(lunar.year, 2023);
      expect(lunar.ganzhiYear, '癸卯');
      expect(lunar.zodiac, '兔');
    });

    test('2023 leap month (闰二月)', () {
      // 2023 has a leap second month. 2023-03-22 is the 1st day of 闰二月.
      final lunar = solarToLunar(DateTime(2023, 3, 22))!;
      expect(lunar.month, 2);
      expect(lunar.isLeapMonth, true);
      expect(lunar.day, 1);
    });

    test('short day names for first of month', () {
      final lunar = solarToLunar(DateTime(2024, 3, 10))!;
      // 2024-03-10 is lunar 2024-02-01.
      expect(lunar.month, 2);
      expect(lunar.day, 1);
      expect(lunar.shortLabel, '二月');
    });

    test('regular day short label', () {
      final lunar = solarToLunar(DateTime(2024, 2, 24))!;
      // 2024-02-24 is lunar 2024-01-15 (元宵节).
      expect(lunar.day, 15);
      expect(lunar.shortLabel, '十五');
      expect(lunarFestival(lunar), '元宵节');
    });

    test('out-of-range date returns null', () {
      expect(solarToLunar(DateTime(1899, 12, 31)), isNull);
    });
  });

  group('solarFestival', () {
    test('national day', () {
      expect(solarFestival(DateTime(2024, 10, 1)), '国庆节');
    });

    test('new year', () {
      expect(solarFestival(DateTime(2024, 1, 1)), '元旦');
    });

    test('non-festival day', () {
      expect(solarFestival(DateTime(2024, 8, 9)), isNull);
    });
  });
}
