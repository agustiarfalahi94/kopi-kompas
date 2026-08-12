import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

import '../data/brew_schema.dart';
import '../models/brew_entry.dart';
import '../screens/new_entry_screen.dart' show shouldCelebrate;
import '../strings.dart';

/// The number, the reasons that produced it, and confetti at 90 or above.
///
/// The reasons are not decoration. A score with no argument attached is one
/// you cannot disagree with, and this one will be wrong sometimes.
class ScoreReveal extends StatefulWidget {
  const ScoreReveal({
    super.key,
    required this.entry,
    required this.method,
    required this.onRated,
    required this.onDone,
  });

  final BrewEntry entry;
  final MethodSpec method;

  /// Fires only when a star is actually tapped. Never rating is a real state,
  /// and reporting 0 would make "unrated" read as "hated it" in every average
  /// the app ever computes.
  final ValueChanged<int> onRated;

  final VoidCallback onDone;

  @override
  State<ScoreReveal> createState() => _ScoreRevealState();
}

class _ScoreRevealState extends State<ScoreReveal> {
  late final ConfettiController _confetti = ConfettiController(
    duration: const Duration(seconds: 2),
  );

  late int? _rating = widget.entry.myRating;

  @override
  void initState() {
    super.initState();
    if (shouldCelebrate(widget.entry.overallScore)) _confetti.play();
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.entry;

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Text(
              widget.method.label,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Center(child: _headline(theme, entry)),
            const SizedBox(height: 24),
            Expanded(
              child: ListView(
                children: [
                  for (final reason in entry.scoreReasons)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(child: Text(reason)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            _rating_(context),
            if (entry.scoreRubric != null)
              Text(
                'rubric ${entry.scoreRubric} · ${entry.scoreModel}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: widget.onDone,
              child: Text(AppStrings.doneButton),
            ),
          ],
        ),
        ConfettiWidget(
          confettiController: _confetti,
          blastDirection: pi / 2,
          emissionFrequency: 0.05,
          numberOfParticles: 20,
          gravity: 0.25,
        ),
      ],
    );
  }

  /// The brewer's own verdict, asked here rather than in the form because it
  /// is the one field nobody can answer before tasting — and because putting
  /// it under the number turns "here is what the app thinks" into "and what
  /// do you think?".
  ///
  /// Shown for every status, including unscored methods: kopi joss gets no
  /// number, so an opinion is the only judgement it will ever carry.
  Widget _rating_(BuildContext context) => Column(
    children: [
      Text(AppStrings.rateThis, style: Theme.of(context).textTheme.bodyMedium),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              key: ValueKey('rating-$i'),
              icon: Icon((_rating ?? 0) >= i ? Icons.star : Icons.star_border),
              color: Theme.of(context).colorScheme.primary,
              onPressed: () {
                setState(() => _rating = i);
                widget.onRated(i);
              },
            ),
        ],
      ),
    ],
  );

  Widget _headline(ThemeData theme, BrewEntry entry) =>
      switch (entry.scoreStatus) {
        ScoreStatus.scored => Text(
          '${entry.overallScore}',
          style: theme.textTheme.displayLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        ScoreStatus.notApplicable => Text(
          AppStrings.notScored,
          style: theme.textTheme.titleLarge,
        ),
        _ => Text(AppStrings.scoreFailed, style: theme.textTheme.titleMedium),
      };
}
