import 'package:flutter/material.dart';

import '../strings.dart';

/// What an edit did to the score.
///
/// A pure value so the wording rules — which message, and whether the rubric
/// caveat applies — are testable without a widget.
class ScoreChange {
  const ScoreChange({
    required this.before,
    required this.after,
    required this.beforeRubric,
    required this.afterRubric,
    required this.reasons,
    this.failed = false,
  });

  final int? before;
  final int? after;
  final String? beforeRubric;
  final String? afterRubric;
  final List<String> reasons;

  /// True when the model could not be reached. The old number survives, and
  /// saying nothing would let someone believe it had been re-checked.
  final bool failed;

  bool get moved => !failed && before != after;

  /// True when the brew was last scored under a different rubric.
  ///
  /// Then part of any difference is the scale rather than the edit, and
  /// claiming otherwise would be a confident lie — r2 marked a pressurised
  /// basket down for skipping WDT and r3 does not, so an untouched shot can
  /// move fourteen points on its own.
  bool get rubricMoved =>
      !failed &&
      beforeRubric != null &&
      afterRubric != null &&
      beforeRubric != afterRubric;

  String get title => failed
      ? AppStrings.scoreRetryFailed
      : moved
      ? AppStrings.scoreChangedTitle
      : AppStrings.scoreSameTitle;

  String get body => failed
      ? AppStrings.scoreRetryFailed
      : moved
      ? AppStrings.scoreChangedWhy
      : AppStrings.scoreSameWhy;
}

/// Announces the re-score. Deliberately a dialog rather than a snack bar: the
/// number on the previous screen has already changed by the time this shows,
/// and a message that can be missed is no better than the silence it replaces.
Future<void> showScoreChange(BuildContext context, ScoreChange change) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text(change.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!change.failed && change.before != null && change.after != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Text(
                      '${change.before}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.disabledColor,
                        decoration: change.moved
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (change.moved) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward, size: 18),
                      ),
                      Text(
                        '${change.after}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            Text(change.body),
            if (change.rubricMoved) ...[
              const SizedBox(height: 12),
              Text(
                AppStrings.scoreRubricMoved,
                style: theme.textTheme.bodySmall,
              ),
            ],
            for (final reason in change.reasons.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('— $reason', style: theme.textTheme.bodySmall),
              ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppStrings.ok),
          ),
        ],
      );
    },
  );
}
