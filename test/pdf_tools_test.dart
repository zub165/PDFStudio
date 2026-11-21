import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_studio/services/pdf_tools.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  test('adds text, a box and fillable fields to a document', () async {
    final document = PdfDocument();
    document.pages.add();

    PdfTools.addText(document, 0, 'Hello PDF Studio',
        x: 36, y: 36, size: 14);
    PdfTools.addBox(document, 0,
        x: 36, y: 72, width: 200, height: 60);
    PdfTools.addFillableTextField(document, 0, 'name',
        x: 36, y: 160, width: 200, height: 24);
    PdfTools.addFillableCheckBox(document, 0, 'agree',
        x: 36, y: 200);

    expect(document.form.fields.count, 2);

    final saved = await document.save();
    document.dispose();

    final reloaded = PdfDocument(inputBytes: saved);
    expect(reloaded.pages.count, 1);
    expect(reloaded.form.fields.count, 2);
    reloaded.dispose();
  });

  test('applies font family, style and color to text', () async {
    final document = PdfDocument();
    document.pages.add();

    PdfTools.addText(document, 0, 'Styled text',
        x: 36,
        y: 36,
        size: 18,
        color: PdfColor(10, 20, 30),
        family: PdfFontFamily.timesRoman,
        bold: true,
        italic: true,
        underline: true,
        strikethrough: true);

    final saved = await document.save();
    document.dispose();

    final reloaded = PdfDocument(inputBytes: saved);
    expect(
      PdfTextExtractor(reloaded).extractText(
            startPageIndex: 0,
            endPageIndex: 0,
          ),
      contains('Styled text'),
    );
    reloaded.dispose();
  });

  test('rejects invalid geometry and avoids duplicate field names', () {
    final document = PdfDocument();
    document.pages.add();

    expect(
      () => PdfTools.addBox(document, 0,
          x: 10, y: 10, width: 0, height: 50),
      throwsArgumentError,
    );
    expect(
      () => PdfTools.addText(document, 0, 'Bad size',
          x: 10, y: 10, size: 100),
      throwsArgumentError,
    );

    PdfTools.addFillableTextField(document, 0, 'same',
        x: 10, y: 10, width: 100, height: 20);
    PdfTools.addFillableCheckBox(document, 0, 'same', x: 10, y: 40);
    expect(document.form.fields[0].name, 'same');
    expect(document.form.fields[1].name, 'same_2');
    document.dispose();
  });

  test('adds a click box, image and video attachment', () async {
    final document = PdfDocument();
    document.pages.add();

    PdfTools.addClickBox(document, 0, 'Submit', 'submit',
        x: 20, y: 20, width: 100, height: 28);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/7VsAAAAASUVORK5CYII=',
    );
    PdfTools.addImage(document, 0, Uint8List.fromList(png),
        x: 20, y: 60, width: 40, height: 40);
    PdfTools.attachFile(document, 'clip.mp4', Uint8List.fromList([1, 2, 3]),
        mimeType: 'video/mp4');

    final saved = await document.save();
    document.dispose();

    final reloaded = PdfDocument(inputBytes: saved);
    expect(reloaded.form.fields.count, 1);
    expect(reloaded.form.fields[0], isA<PdfButtonField>());
    expect(reloaded.attachments.count, 1);
    expect(reloaded.attachments[0].fileName, 'clip.mp4');
    reloaded.dispose();
  });

  test('replaces text and adds a Yes/No radio group', () async {
    final original = PdfDocument();
    original.pages.add().graphics.drawString(
          'OLD VALUE',
          PdfStandardFont(PdfFontFamily.helvetica, 14),
        );
    var bytes = await original.save();
    original.dispose();

    final editing = PdfDocument(inputBytes: bytes);
    final changed =
        PdfTools.replaceText(editing, 0, 'OLD VALUE', 'NEW VALUE');
    expect(changed, greaterThan(0));
    PdfTools.addYesNoChoice(editing, 0, 'Do you agree?', 'agree',
        x: 36, y: 120);
    bytes = await editing.save();
    editing.dispose();

    final result = PdfDocument(inputBytes: bytes);
    expect(result.form.fields.count, 1);
    expect(result.form.fields[0], isA<PdfRadioButtonListField>());
    result.dispose();
  });
}
