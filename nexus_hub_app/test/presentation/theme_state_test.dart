// import 'package:flutter/material.dart';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:nexus_hub/presentation/states/theme_state.dart';
// import 'package:shared_preferences/shared_preferences.dart';
//
// void main() {
//   TestWidgetsFlutterBinding.ensureInitialized();
//
//   setUp(() async {
//     SharedPreferences.setMockInitialValues({});
//     await ThemeState.instance.init();
//   });
//
//   test('defaults to system when no preference is stored', () {
//     expect(ThemeState.instance.themeMode.value, ThemeMode.system);
//   });
//
//   test('setThemeMode updates signal and persists value', () async {
//     await ThemeState.instance.setThemeMode(ThemeMode.dark);
//     expect(ThemeState.instance.themeMode.value, ThemeMode.dark);
//
//     final prefs = await SharedPreferences.getInstance();
//     expect(prefs.getString('nexus_theme_mode_v1'), 'dark');
//   });
//
//   test('toggle cycles through light, dark, system', () async {
//     ThemeState.instance.themeMode.value = ThemeMode.light;
//
//     await ThemeState.instance.toggle();
//     expect(ThemeState.instance.themeMode.value, ThemeMode.dark);
//
//     await ThemeState.instance.toggle();
//     expect(ThemeState.instance.themeMode.value, ThemeMode.system);
//
//     await ThemeState.instance.toggle();
//     expect(ThemeState.instance.themeMode.value, ThemeMode.light);
//   });
// }
