import 'package:flutter/material.dart';

import '../data/guide_photo.dart';

/// A guide photograph with its credit attached underneath.
///
/// The credit is part of the widget rather than something each caller
/// remembers to add, because attribution is a licence condition and a caller
/// that forgets it puts the app in breach. There is no way to show the image
/// through this widget without showing the author and licence.
class GuidePhotoCard extends StatelessWidget {
  const GuidePhotoCard({super.key, required this.photo, this.height = 180});

  final GuidePhoto photo;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            photo.asset,
            height: height,
            fit: BoxFit.cover,
            // A missing asset must not take the screen down with it. The
            // guide is the point; the photograph is decoration.
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
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
