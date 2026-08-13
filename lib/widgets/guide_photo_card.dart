import 'package:flutter/material.dart';

import '../data/guide_photo.dart';

/// A guide photograph with its credit attached underneath.
///
/// The credit is part of the widget rather than something each caller
/// remembers to add, because attribution is a licence condition and a caller
/// that forgets it puts the app in breach. There is no way to show the image
/// through this widget without showing the author and licence.
class GuidePhotoCard extends StatelessWidget {
  const GuidePhotoCard({super.key, required this.photo, this.maxHeight = 320});

  final GuidePhoto photo;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Centred and clipped to the image itself rather than to a fixed box,
        // so a portrait photo is narrower than the column instead of leaving
        // empty bands inside a rounded rectangle.
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                photo.asset,
                fit: BoxFit.contain,
                // A missing asset must not take the screen down with it. The
                // guide is the point; the photograph is decoration.
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            photo.shortCredit,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}
