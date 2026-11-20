import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

/// Holds the open PDF and coordinates viewing, annotating and editing.
///
/// Annotations live inside the viewer. Structural edits (rotate, delete,
/// watermark) need the saved bytes, so [transform] first pulls the annotations
/// out of the viewer, applies the edit, then reloads the viewer.
class PdfEditorState extends ChangeNotifier {
  Uint8List? _bytes;
  String _name = 'document.pdf';
  String? _password;
  int _revision = 0;
  int _pageNumber = 1;
  bool _busy = false;

  final PdfViewerController viewerController = PdfViewerController();

  Uint8List? get bytes => _bytes;
  String get name => _name;
  int get revision => _revision;
  bool get hasDocument => _bytes != null;
  bool get isBusy => _busy;
  bool get hasPassword => _password != null && _password!.isNotEmpty;

  int get currentPage {
    final count = viewerController.pageCount;
    if (count > 0 && _pageNumber > count) return count;
    return _pageNumber < 1 ? 1 : _pageNumber;
  }

  void load(Uint8List bytes, String name) {
    _password = null;
    _pageNumber = 1;
    _loadDocument(bytes, name);
  }

  void close() {
    _bytes = null;
    _name = 'document.pdf';
    _password = null;
    _pageNumber = 1;
    _revision++;
    viewerController.annotationMode = PdfAnnotationMode.none;
    notifyListeners();
  }

  void setPageNumber(int page) {
    if (page < 1 || page == _pageNumber) return;
    _pageNumber = page;
  }

  void setPassword(String password) {
    _password = password;
    notifyListeners();
  }

  void clearPassword() {
    _password = null;
    notifyListeners();
  }

  /// Returns the document with all current annotations included.
  /// A password, if set, is applied only to the exported bytes.
  Future<Uint8List> exportBytes() async {
    var bytes = await _viewerBytes();
    final password = _password;
    if (password == null || password.isEmpty) return bytes;

    final doc = PdfDocument(inputBytes: bytes);
    try {
      doc.security.userPassword = password;
      doc.security.ownerPassword = password;
      doc.security.algorithm = PdfEncryptionAlgorithm.aesx256Bit;
      bytes = Uint8List.fromList(await doc.save());
    } finally {
      doc.dispose();
    }
    return bytes;
  }

  /// Applies a structural edit and reloads the result.
  Future<void> transform(void Function(PdfDocument doc) edit) async {
    if (_bytes == null) throw StateError('No document is open.');
    _setBusy(true);
    try {
      final input = await _viewerBytes();
      final doc = PdfDocument(inputBytes: input);
      try {
        edit(doc);
        final output = await doc.save();
        _loadDocument(Uint8List.fromList(output), _name);
      } finally {
        doc.dispose();
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<Uint8List> _viewerBytes() async {
    final current = _bytes;
    if (current == null) throw StateError('No document is open.');
    final saved = await viewerController.saveDocument();
    return saved.isEmpty ? current : Uint8List.fromList(saved);
  }

  void _loadDocument(Uint8List bytes, String name) {
    _bytes = bytes;
    _name = name;
    _revision++;
    viewerController.annotationMode = PdfAnnotationMode.none;
    notifyListeners();
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  @override
  void dispose() {
    viewerController.dispose();
    super.dispose();
  }
}
