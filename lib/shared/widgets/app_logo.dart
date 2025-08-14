import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double height;
  final EdgeInsetsGeometry? padding;
  final bool? forceDarkBackground; // true => usa logo branca

  const AppLogo({
    super.key,
    this.height = 28,
    this.padding,
    this.forceDarkBackground,
  });

  @override
  Widget build(BuildContext context) {
    final isDark =
        forceDarkBackground ?? Theme.of(context).brightness == Brightness.dark;
    final asset =
        isDark ? 'assets/brand/logo_white.png' : 'assets/brand/logo_black.png';
    final img = Image.asset(asset, height: height, fit: BoxFit.contain);
    if (padding != null) return Padding(padding: padding!, child: img);
    return img;
  }
}
