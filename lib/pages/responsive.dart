import 'package:flutter/material.dart';

class Breakpoints {
  static const double tablet = 800;   // กว้างตั้งแต่ 800px ขึ้นไป = แท็บเล็ต
  static const double desktop = 1200; // เผื่ออนาคตถ้าจะทำเว็บ/เดสก์ท็อป
}

bool isTablet(BuildContext context) =>
    MediaQuery.of(context).size.width >= Breakpoints.tablet;

double maxBodyWidth(BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  if (w >= Breakpoints.desktop) return 1000;
  if (w >= Breakpoints.tablet) return 900;
  return w; // มือถือใช้เต็มจอ
}

EdgeInsets responsivePagePadding(BuildContext context) {
  final tablet = isTablet(context);
  return EdgeInsets.symmetric(horizontal: tablet ? 24 : 16, vertical: 16);
}

/// ครอบ body ให้กว้างไม่เกิน และจัดกึ่งกลาง
class CenteredBody extends StatelessWidget {
  final Widget child;
  const CenteredBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBodyWidth(context)),
        child: child,
      ),
    );
  }
}
