import 'package:flutter/services.dart';

/// Eight date digits, with separators inserted after the year and month.
class IsoDateInputFormatter extends TextInputFormatter {
  const IsoDateInputFormatter();

  static final _nonDigit = RegExp(r'[^0-9]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Do not interfere with an IME until its composition is committed.
    if (!newValue.composing.isCollapsed) return newValue;
    if (oldValue.text == newValue.text && oldValue.composing.isCollapsed) {
      return newValue;
    }

    var raw = newValue.text;
    var selection = newValue.selection;
    final deletedAt = selection.baseOffset;
    // Backspace over an automatic hyphen also removes the preceding digit,
    // rather than immediately restoring the hyphen and trapping the cursor.
    if (selection.isCollapsed &&
        oldValue.selection.isCollapsed &&
        oldValue.selection.baseOffset == deletedAt + 1 &&
        oldValue.text.length == raw.length + 1 &&
        deletedAt > 0 &&
        deletedAt < oldValue.text.length &&
        oldValue.text[deletedAt] == '-' &&
        oldValue.text.replaceRange(deletedAt, deletedAt + 1, '') == raw) {
      raw = raw.replaceRange(deletedAt - 1, deletedAt, '');
      selection = TextSelection.collapsed(offset: deletedAt - 1);
    }

    final allDigits = raw.replaceAll(_nonDigit, '');
    final digits = allDigits.substring(0, allDigits.length.clamp(0, 8));
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if (i == 3 || i == 5) buffer.write('-');
    }
    final text = buffer.toString();

    int mapOffset(int offset) {
      if (offset < 0) return text.length;
      final prefix = raw.substring(0, offset.clamp(0, raw.length));
      final count = prefix.replaceAll(_nonDigit, '').length.clamp(0, 8);
      var mapped = count + (count > 4 ? 1 : 0) + (count > 6 ? 1 : 0);
      if ((count == 4 || count == 6) &&
          (prefix.endsWith('-') ||
              (selection.isCollapsed &&
                  prefix.isNotEmpty &&
                  !_nonDigit.hasMatch(prefix[prefix.length - 1])))) {
        mapped++;
      }
      return mapped.clamp(0, text.length);
    }

    return newValue.copyWith(
      text: text,
      selection: selection.copyWith(
        baseOffset: mapOffset(selection.baseOffset),
        extentOffset: mapOffset(selection.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }
}
