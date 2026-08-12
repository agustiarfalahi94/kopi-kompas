import 'package:flutter/material.dart';

import '../data/brew_guide.dart';
import '../data/brew_schema.dart';
import '../strings.dart';

/// Every guide, grouped by the same five categories as the method picker.
class GuideListScreen extends StatelessWidget {
  const GuideListScreen({
    super.key,
    required this.schema,
    required this.guides,
  });

  final BrewSchema schema;
  final BrewGuides guides;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppStrings.guidesTitle)),
    body: ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(AppStrings.guidesIntro),
        ),
        for (final category in schema.categories) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              category.label,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final id in category.methodIds)
            ListTile(
              title: Text(schema.method(id).label),
              subtitle: Text(
                guides.forMethod(id)?.what ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GuideScreen(
                    method: schema.method(id),
                    guide: guides.forMethod(id),
                  ),
                ),
              ),
            ),
        ],
      ],
    ),
  );
}

/// How to brew one method, and what to do when it goes wrong.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key, required this.method, required this.guide});

  final MethodSpec method;
  final BrewGuide? guide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = guide;

    return Scaffold(
      appBar: AppBar(title: Text(method.label)),
      body: g == null
          ? Center(child: Text(AppStrings.guideMissing))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(g.what, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 24),

                // Straight from the schema, which is also where the scorer
                // gets them. Restating them here would let the two drift.
                if (method.targets case final t?) ...[
                  _heading(theme, AppStrings.guideTargets),
                  _target(theme, AppStrings.guideRatio, '1:${t.ratio.text}'),
                  _target(theme, AppStrings.guideTime, t.time.text),
                  _target(theme, AppStrings.guideTemp, t.temp.text),
                  _target(theme, AppStrings.guideGrind, t.grind),
                  const SizedBox(height: 24),
                ],

                _heading(theme, AppStrings.guideHow),
                for (var i = 0; i < g.steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${i + 1}.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(child: Text(g.steps[i])),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                _heading(theme, AppStrings.guideFaults),
                for (final f in g.faults)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.symptom,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(f.cause, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                _heading(theme, AppStrings.guideGear),
                for (final t in g.gear)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.tier,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(t.what, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),

                if (g.notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _heading(theme, AppStrings.guideNotes),
                  for (final n in g.notes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(child: Text(n)),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _heading(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.primary,
      ),
    ),
  );

  Widget _target(ThemeData theme, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: Text(label)),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
