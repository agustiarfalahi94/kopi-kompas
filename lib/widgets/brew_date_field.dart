import 'package:flutter/material.dart';

import '../strings.dart';

/// `12/08/2026 11:30` — numeric on purpose, so no month name needs
/// translating and the two languages read the same.
String formatBrewedAt(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}/'
    '${t.month.toString().padLeft(2, '0')}/${t.year} '
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';

/// When the coffee was brewed — the entry's own timestamp, not the moment it
/// was written down.
///
/// Always visible, never blank: it is either what the text said, or now. The
/// two are worth telling apart on screen, because a wrong guess about "this
/// morning" is only correctable by someone who can see it was a guess.
class BrewDateField extends StatelessWidget {
  const BrewDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.fromText = false,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  /// True when the parse found it in what the brewer typed.
  final bool fromText;

  Future<void> _edit(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(now.year - 5),
      // No future brews. A date ahead of today would sit at the top of the log
      // forever and count as an already-logged day for the reminder.
      lastDate: now,
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (time == null) return;

    onChanged(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.schedule),
      title: Text(AppStrings.brewedAt),
      subtitle: Text(
        fromText
            ? '${formatBrewedAt(value)} · ${AppStrings.brewedAtFromText}'
            : formatBrewedAt(value),
        style: theme.textTheme.bodyMedium,
      ),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () => _edit(context),
    );
  }
}
