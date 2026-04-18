import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// A shimmer-effect loading skeleton that matches the shape of content
/// being loaded. Use before data arrives to avoid jarring blank screens.
class LoadingSkeleton extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const LoadingSkeleton({
    super.key,
    this.width  = double.infinity,
    this.height = 16,
    this.borderRadius = 8,
  });

  /// A skeleton shaped like a card (e.g. for report/prescription list items).
  factory LoadingSkeleton.card({Key? key}) => LoadingSkeleton(
        key: key,
        height: 88,
        borderRadius: 16,
      );

  /// A skeleton shaped like a short text line.
  factory LoadingSkeleton.textLine({Key? key, double width = 180}) =>
      LoadingSkeleton(key: key, width: width, height: 14, borderRadius: 6);

  /// A full dashboard skeleton with multiple cards.
  static Widget dashboard() => const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor:  isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
      highlightColor: isDark ? const Color(0xFF334155) : const Color(0xFFF8FAFC),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LoadingSkeleton.textLine(width: 120),
          const SizedBox(height: 8),
          LoadingSkeleton.textLine(width: 200),
          const SizedBox(height: 28),
          const LoadingSkeleton(height: 120, borderRadius: 20),
          const SizedBox(height: 16),
          LoadingSkeleton.textLine(width: 140),
          const SizedBox(height: 12),
          LoadingSkeleton.card(),
          const SizedBox(height: 8),
          LoadingSkeleton.card(),
          const SizedBox(height: 8),
          LoadingSkeleton.card(),
        ],
      ),
    );
  }
}
