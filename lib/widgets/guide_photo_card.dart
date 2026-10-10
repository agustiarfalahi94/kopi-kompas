import 'package:flutter/material.dart';

import '../data/guide_photo.dart';

/// A guide photograph with its credit attached underneath.
///
/// The credit is part of the widget rather than something each caller
/// remembers to add, because attribution is a licence condition and a caller
/// that forgets it puts the app in breach. There is no way to show the image
/// through this widget without showing the author and licence.
class GuidePhotoCard extends StatelessWidget {
  const GuidePhotoCard({
    super.key,
    required this.photo,
    this.maxHeight = 320,
    this.compact = false,
  });

  final GuidePhoto photo;
  final bool compact;

  /// A ceiling, not a height.
  ///
  /// The photographs run from 0.67 to 1.78 — five portrait, six landscape,
  /// two square — because they were taken by thirteen different people rather
  /// than shot for this app. A fixed height with `BoxFit.cover` cropped every
  /// portrait to a third of itself, which on a French press meant a photo of
  /// the middle of a jug. The image keeps its own shape; this only stops a
  /// tall one from eating the screen.
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: compact && maxHeight > 64 ? 64 : maxHeight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            photo.asset,
            fit: BoxFit.contain,
            semanticLabel: photo.title,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    final credit = Text(
      photo.shortCredit,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 64, child: image),
            const SizedBox(width: 8),
            Expanded(child: credit),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Centred and clipped to the image itself rather than to a fixed box,
        // so a portrait photo is narrower than the column instead of leaving
        // empty bands inside a rounded rectangle.
        image,
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: credit,
        ),
      ],
    );
  }
}
