import 'package:flutter/material.dart';

import '../data/guide_photo.dart';
import '../strings.dart';

/// Who took the photographs and under what licence.
///
/// Not an "about" page being polite. Every Creative Commons licence used here
/// requires the author and the licence to be named wherever the work is
/// distributed, and an app that ships the photo without this screen is in
/// breach of thirteen licences at once.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key, required this.photos});

  final GuidePhotos photos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = photos.all;

    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.creditsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(AppStrings.creditsIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          for (final p in all)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      p.asset,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(width: 64),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.title, style: theme.textTheme.bodyMedium),
                        Text(
                          '${p.author} · ${p.licence}',
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          p.source,
                          style: theme.textTheme.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
