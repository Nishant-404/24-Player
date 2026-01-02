import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:spotiflac_android/providers/theme_provider.dart';
import 'package:spotiflac_android/theme/app_theme.dart';

/// Wrapper widget that provides dynamic color support from device wallpaper
class DynamicColorWrapper extends ConsumerWidget {
  final Widget Function(ThemeData light, ThemeData dark, ThemeMode mode) builder;

  const DynamicColorWrapper({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // Determine which color scheme to use
        ColorScheme lightScheme;
        ColorScheme darkScheme;

        if (themeSettings.useDynamicColor && lightDynamic != null && darkDynamic != null) {
          // Use dynamic colors from wallpaper (Android 12+)
          lightScheme = lightDynamic;
          darkScheme = darkDynamic;
        } else {
          // Fallback to seed color
          final seedColor = themeSettings.seedColor;
          lightScheme = ColorScheme.fromSeed(
            seedColor: seedColor,
            brightness: Brightness.light,
          );
          darkScheme = ColorScheme.fromSeed(
            seedColor: seedColor,
            brightness: Brightness.dark,
          );
        }

        // Build themes
        final lightTheme = AppTheme.light(dynamicScheme: lightScheme);
        final darkTheme = AppTheme.dark(dynamicScheme: darkScheme);

        return builder(lightTheme, darkTheme, themeSettings.themeMode);
      },
    );
  }
}
