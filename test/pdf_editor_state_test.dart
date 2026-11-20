import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_studio/state/pdf_editor_state.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  test('password is applied only when exporting', () async {
    final original = PdfDocument();
    original.pages.add();
    final bytes = Uint8List.fromList(await original.save());
    original.dispose();

    final state = PdfEditorState();
    addTearDown(state.dispose);
    state.load(bytes, 'sample.pdf');

    expect(state.hasPassword, isFalse);
    state.setPassword('secret');
    expect(state.hasPassword, isTrue);

    final exported = await state.exportBytes();
    final locked = PdfDocument(inputBytes: exported, password: 'secret');
    expect(locked.pages.count, 1);
    locked.dispose();
  });

  test('load clears a password from a previous document', () async {
    final original = PdfDocument();
    original.pages.add();
    final bytes = Uint8List.fromList(await original.save());
    original.dispose();

    final state = PdfEditorState();
    addTearDown(state.dispose);
    state.load(bytes, 'first.pdf');
    state.setPassword('secret');
    state.load(bytes, 'second.pdf');

    expect(state.hasPassword, isFalse);
    expect(state.name, 'second.pdf');
  });
}
