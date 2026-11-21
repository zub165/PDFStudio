import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Structural edits that work on a PdfDocument in memory.
/// Each method changes the document it is given; the caller saves it.
class PdfTools {
  /// Rotates one page 90 degrees clockwise.
  static void rotatePage(PdfDocument doc, int index) {
    final page = doc.pages[index];
    final next = (page.rotation.index + 1) % PdfPageRotateAngle.values.length;
    page.rotation = PdfPageRotateAngle.values[next];
  }

  /// Removes one page. Refuses to leave an empty document.
  static void deletePage(PdfDocument doc, int index) {
    if (doc.pages.count <= 1) {
      throw StateError('A PDF needs at least one page.');
    }
    doc.pages.removeAt(index);
  }

  /// Draws a diagonal, semi-transparent text stamp across every page.
  static void addWatermark(PdfDocument doc, String text) {
    final font = PdfStandardFont(PdfFontFamily.helvetica, 48);
    final brush = PdfSolidBrush(PdfColor(120, 120, 120));
    final format = PdfStringFormat(
      alignment: PdfTextAlignment.center,
      lineAlignment: PdfVerticalAlignment.middle,
    );

    for (var i = 0; i < doc.pages.count; i++) {
      final page = doc.pages[i];
      final size = page.getClientSize();
      final g = page.graphics;

      g.save();
      g.setTransparency(0.2);
      // Move the origin to the page centre and rotate, so text sits diagonally.
      g.translateTransform(size.width / 2, size.height / 2);
      g.rotateTransform(-45);
      g.drawString(
        text,
        font,
        brush: brush,
        bounds: Rect.fromLTWH(-size.width / 2, -40, size.width, 80),
        format: format,
      );
      g.restore();
    }
  }

  /// Encrypts the document so it needs [password] to open and edit.
  static void setPassword(PdfDocument doc, String password) {
    doc.security.userPassword = password;
    doc.security.ownerPassword = password;
    doc.security.algorithm = PdfEncryptionAlgorithm.aesx256Bit;
  }

  /// Draws new text on a page at PDF points from its top-left corner.
  static void addText(
    PdfDocument doc,
    int pageIndex,
    String text, {
    required double x,
    required double y,
    double size = 14,
    PdfColor? color,
    PdfFontFamily family = PdfFontFamily.helvetica,
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool strikethrough = false,
  }) {
    if (text.trim().isEmpty) return;
    _positive(size, 'Font size', min: 4, max: 72);
    _finite(x, 'X');
    _finite(y, 'Y');
    final page = _page(doc, pageIndex);
    final font = _font(family, size,
        bold: bold,
        italic: italic,
        underline: underline,
        strikethrough: strikethrough);
    final maxWidth = page.getClientSize().width - x;
    page.graphics.drawString(
      text,
      font,
      brush: PdfSolidBrush(color ?? PdfColor(0, 0, 0)),
      bounds: Rect.fromLTWH(x, y, maxWidth > 0 ? maxWidth : 72, size * 1.6),
    );
  }

  /// Draws an outlined rectangle on a page at PDF points.
  static void addBox(
    PdfDocument doc,
    int pageIndex, {
    required double x,
    required double y,
    required double width,
    required double height,
    PdfColor? color,
  }) {
    _positive(width, 'Width');
    _positive(height, 'Height');
    _finite(x, 'X');
    _finite(y, 'Y');
    final page = _page(doc, pageIndex);
    page.graphics.drawRectangle(
      pen: PdfPen(color ?? PdfColor(0, 0, 0), width: 1.5),
      bounds: Rect.fromLTWH(x, y, width, height),
    );
  }

  /// Adds an editable text form field to a page.
  static void addFillableTextField(
    PdfDocument doc,
    int pageIndex,
    String name, {
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    _positive(width, 'Width');
    _positive(height, 'Height');
    _finite(x, 'X');
    _finite(y, 'Y');
    final page = _page(doc, pageIndex);
    final field = PdfTextBoxField(
      page,
      _uniqueName(doc, name, 'field'),
      Rect.fromLTWH(x, y, width, height),
      font: PdfStandardFont(PdfFontFamily.helvetica, 11),
      borderColor: PdfColor(40, 76, 126),
      borderWidth: 1,
      backColor: PdfColor(255, 255, 255),
    );
    doc.form.fields.add(field);
  }

  /// Replaces visible text on one page by covering the matched bounds and
  /// drawing new text. The original text remains in the PDF content stream.
  /// Returns the number of matches changed.
  static int replaceText(
    PdfDocument doc,
    int pageIndex,
    String find,
    String replacement, {
    PdfFontFamily family = PdfFontFamily.helvetica,
    double? size,
    PdfColor? color,
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool strikethrough = false,
  }) {
    final needle = find.trim();
    if (needle.isEmpty) return 0;
    if (size != null) _positive(size, 'Font size', min: 4, max: 72);
    _page(doc, pageIndex);
    final matches = PdfTextExtractor(doc).findText(
      [needle],
      startPageIndex: pageIndex,
      endPageIndex: pageIndex,
    );
    final onPage = matches.where((match) => match.pageIndex == pageIndex).toList();
    if (onPage.isEmpty) return 0;

    final page = _page(doc, pageIndex);
    final graphics = page.graphics;
    final pageWidth = page.getClientSize().width;
    for (final match in onPage) {
      final bounds = match.bounds;
      graphics.drawRectangle(
        bounds: Rect.fromLTWH(
          bounds.left - 1,
          bounds.top - 1,
          bounds.width + 2,
          bounds.height + 2,
        ),
        brush: PdfSolidBrush(PdfColor(255, 255, 255)),
      );
      if (replacement.isEmpty) continue;
      final fontSize = size ?? (bounds.height * 0.78).clamp(6.0, 48.0);
      final available = pageWidth - bounds.left - 4;
      graphics.drawString(
        replacement,
        _font(family, fontSize,
            bold: bold,
            italic: italic,
            underline: underline,
            strikethrough: strikethrough),
        brush: PdfSolidBrush(color ?? PdfColor(0, 0, 0)),
        bounds: Rect.fromLTWH(
          bounds.left,
          bounds.top,
          available > 0 ? available : 72,
          bounds.height + 2,
        ),
      );
    }
    return onPage.length;
  }

  /// Hides matching text on a page. See [replaceText] for the limitation.
  static int deleteText(PdfDocument doc, int pageIndex, String find) =>
      replaceText(doc, pageIndex, find, '');

  /// Adds a labelled Yes/No radio group that users can click in the viewer.
  static void addYesNoChoice(
    PdfDocument doc,
    int pageIndex,
    String label,
    String name, {
    required double x,
    required double y,
    double gap = 80,
  }) {
    _positive(gap, 'Gap', min: 24);
    _finite(x, 'X');
    _finite(y, 'Y');
    final page = _page(doc, pageIndex);
    final radio = PdfRadioButtonListField(
      page,
      _uniqueName(doc, name, 'choice'),
      items: [
        PdfRadioButtonListItem('Yes', Rect.fromLTWH(x, y, 16, 16)),
        PdfRadioButtonListItem('No', Rect.fromLTWH(x + gap, y, 16, 16)),
      ],
    );
    doc.form.fields.add(radio);

    if (label.trim().isEmpty) return;
    final font = PdfStandardFont(PdfFontFamily.helvetica, 11);
    final brush = PdfSolidBrush(PdfColor(0, 0, 0));
    final maxWidth = page.getClientSize().width - x - 4;
    page.graphics.drawString(
      label,
      font,
      brush: brush,
      bounds: Rect.fromLTWH(
        x,
        y - 18 < 4 ? 4 : y - 18,
        maxWidth > 0 ? maxWidth : 200,
        18,
      ),
    );
  }

  /// Adds a checkbox form field to a page.
  static void addFillableCheckBox(
    PdfDocument doc,
    int pageIndex,
    String name, {
    required double x,
    required double y,
    double size = 16,
  }) {
    _positive(size, 'Size', min: 8);
    _finite(x, 'X');
    _finite(y, 'Y');
    final page = _page(doc, pageIndex);
    final field = PdfCheckBoxField(
      page,
      _uniqueName(doc, name, 'check'),
      Rect.fromLTWH(x, y, size, size),
      borderColor: PdfColor(40, 76, 126),
      backColor: PdfColor(255, 255, 255),
    );
    doc.form.fields.add(field);
  }

  static void addClickBox(
    PdfDocument doc,
    int pageIndex,
    String caption,
    String name, {
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    _positive(width, 'Width');
    _positive(height, 'Height');
    _finite(x, 'X');
    _finite(y, 'Y');
    final page = _page(doc, pageIndex);
    final label = caption.trim().isEmpty ? 'Click' : caption.trim();
    final field = PdfButtonField(
      page,
      _uniqueName(doc, name, 'button'),
      Rect.fromLTWH(x, y, width, height),
      text: label,
      font: PdfStandardFont(PdfFontFamily.helvetica, 11),
      borderColor: PdfColor(40, 76, 126),
      backColor: PdfColor(238, 243, 250),
      foreColor: PdfColor(20, 45, 80),
      borderWidth: 1,
      tooltip: label,
    );
    doc.form.fields.add(field);
  }

  static void addImage(
    PdfDocument doc,
    int pageIndex,
    Uint8List imageBytes, {
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    if (imageBytes.isEmpty) {
      throw ArgumentError('Image data is empty.');
    }
    _positive(width, 'Width');
    _positive(height, 'Height');
    _finite(x, 'X');
    _finite(y, 'Y');
    final page = _page(doc, pageIndex);
    final image = PdfBitmap(imageBytes);
    page.graphics.drawImage(image, Rect.fromLTWH(x, y, width, height));
  }

  static void attachFile(
    PdfDocument doc,
    String fileName,
    Uint8List bytes, {
    String? description,
    String? mimeType,
  }) {
    if (fileName.trim().isEmpty) {
      throw ArgumentError('A file name is required.');
    }
    if (bytes.isEmpty) {
      throw ArgumentError('File data is empty.');
    }
    doc.attachments.add(
      PdfAttachment(
        fileName.trim(),
        bytes,
        description: description,
        mimeType: mimeType,
      ),
    );
  }

  static PdfFont _font(
    PdfFontFamily family,
    double size, {
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool strikethrough = false,
  }) {
    final styles = <PdfFontStyle>[
      if (bold) PdfFontStyle.bold,
      if (italic) PdfFontStyle.italic,
      if (underline) PdfFontStyle.underline,
      if (strikethrough) PdfFontStyle.strikethrough,
    ];
    if (styles.isEmpty) {
      return PdfStandardFont(family, size, style: PdfFontStyle.regular);
    }
    if (styles.length == 1) {
      return PdfStandardFont(family, size, style: styles.first);
    }
    return PdfStandardFont(family, size, multiStyle: styles);
  }

  static void _finite(double value, String label) {
    if (!value.isFinite) {
      throw ArgumentError('$label must be a finite number.');
    }
  }

  static void _positive(
    double value,
    String label, {
    double min = 0,
    double? max,
  }) {
    _finite(value, label);
    if (value <= min || (max != null && value > max)) {
      final range = max == null ? 'greater than $min' : 'between $min and $max';
      throw ArgumentError('$label must be $range.');
    }
  }

  static String _uniqueName(PdfDocument doc, String name, String prefix) {
    final base = name.trim().isEmpty ? prefix : name.trim();
    final existing = <String>{
      for (var i = 0; i < doc.form.fields.count; i++)
        doc.form.fields[i].name ?? '',
    };
    var candidate = base;
    var suffix = 2;
    while (existing.contains(candidate)) {
      candidate = '${base}_$suffix';
      suffix++;
    }
    return candidate;
  }

  static PdfPage _page(PdfDocument doc, int index) {
    if (index < 0 || index >= doc.pages.count) {
      throw StateError('Page ${index + 1} is not in this document.');
    }
    return doc.pages[index];
  }
}
