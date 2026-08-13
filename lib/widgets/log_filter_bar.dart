import 'package:flutter/material.dart';

import '../data/brew_schema.dart';
import '../services/log_filter.dart';
import '../strings.dart';

/// The search box and the two chips, above any list of brews.
///
/// Stateless as far as the filter is concerned: it renders what it is given
/// and reports changes upward. The owning screen holds the [LogFilter], which
/// is what keeps a filter alive while you open a brew and come back — screen
/// state outlives a pushed route, a widget's own state would not survive being
/// rebuilt from a fresh future.
class LogFilterBar extends StatefulWidget {
  const LogFilterBar({
    super.key,
    required this.schema,
    required this.filter,
    required this.onChanged,
    required this.shown,
    required this.total,
  });

  final BrewSchema schema;
  final LogFilter filter;
  final ValueChanged<LogFilter> onChanged;
  final int shown;
  final int total;

  @override
  State<LogFilterBar> createState() => _LogFilterBarState();
}

class _LogFilterBarState extends State<LogFilterBar> {
  late final _controller = TextEditingController(text: widget.filter.query);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The method picker, grouped by category, because a flat list of sixteen
  /// is the thing categories exist to avoid.
  Future<void> _pickMethod() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(AppStrings.filterAny),
              leading: const Icon(Icons.clear_all),
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final category in widget.schema.categories) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  category.label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              for (final id in category.methodIds)
                ListTile(
                  dense: true,
                  title: Text(widget.schema.method(id).label),
                  selected: id == widget.filter.methodId,
                  onTap: () => Navigator.pop(context, id),
                ),
            ],
          ],
        ),
      ),
    );
    if (picked == null) return;
    widget.onChanged(
      picked.isEmpty
          ? widget.filter.copyWith(clearMethod: true)
          : widget.filter.copyWith(methodId: picked),
    );
  }

  Future<void> _pickRating() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(AppStrings.filterAny),
              leading: const Icon(Icons.clear_all),
              onTap: () => Navigator.pop(context, 0),
            ),
            for (final n in [5, 4, 3, 2])
              ListTile(
                dense: true,
                title: Text(AppStrings.atLeastStars(n)),
                selected: n == widget.filter.minRating,
                onTap: () => Navigator.pop(context, n),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    widget.onChanged(
      picked == 0
          ? widget.filter.copyWith(clearRating: true)
          : widget.filter.copyWith(minRating: picked),
    );
  }

  void _clearAll() {
    _controller.clear();
    widget.onChanged(const LogFilter());
  }

  /// A chip that says what it does before you touch it.
  ///
  /// A bare word — "Method" — reads as a label, not a control, and a log of
  /// six entries gives nobody a reason to try tapping it. The icon says what
  /// it filters, the caret says it opens something, and the checkmark
  /// [FilterChip] would otherwise draw is turned off so the icon survives
  /// being selected.
  ///
  /// The caret never becomes a ✕. A chip has one tap target, so a cross drawn
  /// inside it opened the picker like everything else — it promised to clear
  /// the filter and did the opposite. Clearing lives in the button at the end
  /// of the row, which is a control of its own.
  Widget _chip({
    required IconData icon,
    required String text,
    required bool on,
    required VoidCallback onTap,
  }) => FilterChip(
    avatar: Icon(icon, size: 18),
    showCheckmark: false,
    label: Row(
      mainAxisSize: MainAxisSize.min,
      children: [Text(text), const Icon(Icons.arrow_drop_down, size: 18)],
    ),
    selected: on,
    onSelected: (_) => onTap(),
  );

  @override
  Widget build(BuildContext context) {
    final f = widget.filter;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: AppStrings.searchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: f.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _controller.clear();
                        widget.onChanged(f.copyWith(query: ''));
                      },
                    ),
              border: const OutlineInputBorder(),
            ),
            // Filtering an on-device list of a few hundred rows is far cheaper
            // than a frame, so this needs no debounce.
            onChanged: (t) => widget.onChanged(f.copyWith(query: t)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip(
                        icon: Icons.coffee_outlined,
                        text: f.methodId == null
                            ? AppStrings.filterMethod
                            : widget.schema.method(f.methodId!).label,
                        on: f.methodId != null,
                        onTap: _pickMethod,
                      ),
                      const SizedBox(width: 8),
                      _chip(
                        icon: Icons.star_outline,
                        text: f.minRating == null
                            ? AppStrings.filterRating
                            : AppStrings.atLeastStars(f.minRating!),
                        on: f.minRating != null,
                        onTap: _pickRating,
                      ),
                    ],
                  ),
                ),
              ),
              // The count is only shown while something is filtering, so a
              // short list is never mistaken for a list that lost entries.
              if (f.isActive) ...[
                const SizedBox(width: 8),
                Text(
                  AppStrings.matchCount(widget.shown, widget.total),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  tooltip: AppStrings.filterClear,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  onPressed: _clearAll,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
