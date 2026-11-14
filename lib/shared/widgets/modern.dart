/// Building blocks of the "Aurora" redesign: gradient hero, icon bubbles,
/// illustrations and per-accident-type visuals.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/constants/accident_types.dart';
import '../../core/theme/app_theme.dart';

/// Bundled vector illustration from `assets/illustrations/<name>.svg`.
class Illustration extends StatelessWidget {
  const Illustration(this.name, {super.key, this.height = 160});

  final String name;
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.asset('assets/illustrations/$name.svg', height: height),
  );
}

/// Rounded brand-gradient panel with soft decorative orbs.
class GradientHero extends StatelessWidget {
  const GradientHero({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.gradient = AppGradients.brand,
    this.radius = 28,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient gradient;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppTheme.softShadow(AppColors.violet),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          const PositionedDirectional(top: -60, end: -40, child: _Orb(170)),
          const PositionedDirectional(
            bottom: -70,
            start: -50,
            child: _Orb(150),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb(this.size);

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: 0.08),
    ),
  );
}

/// Colored rounded-square icon badge.
class IconBubble extends StatelessWidget {
  const IconBubble({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
    this.solid = false,
  });

  final IconData icon;
  final Color color;
  final double size;

  /// Solid gradient fill with a white glyph instead of a soft tint.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: solid ? AppGradients.tile(color) : null,
        color: solid ? null : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Icon(icon, size: size * 0.52, color: solid ? Colors.white : color),
    );
  }
}

/// Section title with a leading icon bubble.
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.icon,
    required this.title,
    this.color = AppColors.indigo,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconBubble(icon: icon, color: color, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Icon + color for a stored accident type (any unknown value → generic car).
abstract final class AccidentVisual {
  static IconData icon(String? stored) =>
      switch (AccidentTypes.match(stored)?.en) {
        'Najem' => Icons.star_rounded,
        'Moroor' => Icons.traffic_rounded,
        'Police' => Icons.local_police_rounded,
        'Glass' => Icons.broken_image_rounded,
        'MTR' => Icons.car_repair_rounded,
        'Civil Defense' => Icons.local_fire_department_rounded,
        _ => Icons.car_crash_rounded,
      };

  static Color color(String? stored) =>
      switch (AccidentTypes.match(stored)?.en) {
        'Najem' => AppColors.amber,
        'Moroor' => AppColors.mint,
        'Police' => AppColors.sky,
        'Glass' => const Color(0xFF06B6D4),
        'MTR' => AppColors.violet,
        'Civil Defense' => AppColors.rose,
        _ => AppColors.indigo,
      };
}
