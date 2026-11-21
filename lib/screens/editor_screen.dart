import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../services/file_service.dart';
import '../services/pdf_tools.dart';
import '../state/pdf_editor_state.dart';

enum _PlacementKind {
  text,
  box,
  textField,
  checkbox,
  yesNo,
  clickBox,
  image
}

class _FieldDialogResult {
  const _FieldDialogResult(this.values, this.pickOnPage);

  final List<String> values;
  final bool pickOnPage;
}

class _Placement {
  const _Placement(this.kind, this.values, {this.bytes});

  final _PlacementKind kind;
  final List<String> values;
  final Uint8List? bytes;
}

class _FontSettings {
  const _FontSettings({
    required this.family,
    required this.size,
    required this.color,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
  });

  final PdfFontFamily family;
  final double size;
  final Color color;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final PdfEditorState _state = PdfEditorState();
  final UndoHistoryController _undoController = UndoHistoryController();
  PdfAnnotationMode _mode = PdfAnnotationMode.none;
  _Placement? _placement;
  Offset? _placementPointer;
  String? _selectedText;
  int? _selectedPageIndex;
  _FontSettings _fontSettings = const _FontSettings(
    family: PdfFontFamily.helvetica,
    size: 14,
    color: Color(0xFF000000),
  );

  static const _fontFamilies = <(PdfFontFamily, String)>[
    (PdfFontFamily.helvetica, 'Helvetica'),
    (PdfFontFamily.courier, 'Courier'),
    (PdfFontFamily.timesRoman, 'Times Roman'),
    (PdfFontFamily.symbol, 'Symbol'),
    (PdfFontFamily.zapfDingbats, 'Zapf Dingbats'),
  ];

  static const _fontColors = <(Color, String)>[
    (Color(0xFF000000), 'Black'),
    (Color(0xFFFFFFFF), 'White'),
    (Color(0xFFE53935), 'Red'),
    (Color(0xFF1E88E5), 'Blue'),
    (Color(0xFF43A047), 'Green'),
    (Color(0xFFFDD835), 'Yellow'),
    (Color(0xFF8E24AA), 'Purple'),
    (Color(0xFFEF6C00), 'Orange'),
  ];

  static const _annotationTools = <(PdfAnnotationMode, String, IconData)>[
    (PdfAnnotationMode.none, 'Select', Icons.near_me_outlined),
    (PdfAnnotationMode.highlight, 'Highlight', Icons.highlight_outlined),
    (PdfAnnotationMode.underline, 'Underline', Icons.format_underlined),
    (PdfAnnotationMode.strikethrough, 'Strike', Icons.strikethrough_s),
    (PdfAnnotationMode.squiggly, 'Squiggly', Icons.gesture),
    (PdfAnnotationMode.stickyNote, 'Note', Icons.sticky_note_2_outlined),
  ];

  static const _features = <String>[
    'Highlight',
    'Rotate pages',
    'Watermark',
    'Password',
    'Replace text',
    'Fillable forms',
  ];

  @override
  void dispose() {
    _undoController.dispose();
    _state.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final picked = await FileService.pickPdf();
      if (picked == null) return;
      _state.load(picked.bytes, picked.name);
      setState(() {
        _mode = PdfAnnotationMode.none;
        _placement = null;
        _placementPointer = null;
        _selectedText = null;
        _selectedPageIndex = null;
      });
      _showMessage('Opened ${picked.name}');
    } catch (e) {
      _showError('Could not open that file. $e');
    }
  }

  Future<void> _save() async {
    if (!_state.hasDocument) return;
    try {
      final bytes = await _state.exportBytes();
      final path = await FileService.savePdf(bytes, _state.name);
      if (kIsWeb) {
        _showMessage('Download started');
      } else if (path != null) {
        _showMessage('Saved ${_state.name}');
      }
    } catch (e) {
      _showError('Could not save the file. $e');
    }
  }

  void _close() {
    _state.close();
    setState(() {
      _mode = PdfAnnotationMode.none;
      _placement = null;
      _placementPointer = null;
      _selectedText = null;
      _selectedPageIndex = null;
    });
    _showMessage('Document closed');
  }

  void _removePassword() {
    _state.clearPassword();
    _showMessage('Password removed. Save to update the file.');
  }

  void _setMode(PdfAnnotationMode mode) {
    final next = _mode == mode ? PdfAnnotationMode.none : mode;
    setState(() => _mode = next);
    _state.viewerController.annotationMode = next;
  }

  void _zoom(double amount) {
    final controller = _state.viewerController;
    controller.zoomLevel = (controller.zoomLevel + amount).clamp(1.0, 3.0);
  }

  void _resetZoom() => _state.viewerController.zoomLevel = 1.0;

  void _turnPage(bool forward) {
    final controller = _state.viewerController;
    if (controller.pageCount < 1) return;
    if (forward) {
      controller.nextPage();
    } else {
      controller.previousPage();
    }
  }

  void _beginPlacement(
    _PlacementKind kind,
    List<String> values, {
    Uint8List? bytes,
  }) {
    setState(() {
      _placement = _Placement(kind, values, bytes: bytes);
      _placementPointer = null;
    });
    _showMessage('Tap or drag on the page to choose the position.');
  }

  void _cancelPlacement() {
    if (_placement == null) return;
    setState(() {
      _placement = null;
      _placementPointer = null;
    });
  }

  void _updatePlacementPointer(PointerEvent event) {
    if (_placement == null) return;
    setState(() => _placementPointer = event.localPosition);
  }

  void _handleViewerTap(PdfGestureDetails details) {
    final placement = _placement;
    if (placement == null) return;
    if (details.pageNumber < 1) {
      _showError('Tap inside a PDF page.');
      return;
    }
    setState(() {
      _placement = null;
      _placementPointer = null;
    });
    _applyPlacementValue(
      placement.kind,
      details.pageNumber - 1,
      details.pagePosition.dx,
      details.pagePosition.dy,
      placement.values,
      bytes: placement.bytes,
    );
  }

  void _handleTextSelectionChanged(PdfTextSelectionChangedDetails details) {
    final text = details.selectedText?.trim();
    setState(() {
      if (text == null || text.isEmpty) {
        _selectedText = null;
        _selectedPageIndex = null;
      } else {
        _selectedText = text;
        _selectedPageIndex = _state.currentPage - 1;
      }
    });
  }

  void _clearSelectedText() {
    _state.viewerController.clearSelection();
    setState(() {
      _selectedText = null;
      _selectedPageIndex = null;
    });
  }

  Future<void> _applyPlacementValue(
    _PlacementKind kind,
    int pageIndex,
    double x,
    double y,
    List<String> values, {
    Uint8List? bytes,
  }) async {
    switch (kind) {
      case _PlacementKind.text:
        await _runEdit(
          'Text added',
          (doc) => PdfTools.addText(
            doc,
            pageIndex,
            values[0],
            x: x,
            y: y,
            size: _fontSettings.size,
            color: _pdfColor(_fontSettings.color),
            family: _fontSettings.family,
            bold: _fontSettings.bold,
            italic: _fontSettings.italic,
            underline: _fontSettings.underline,
            strikethrough: _fontSettings.strikethrough,
          ),
        );
      case _PlacementKind.box:
        await _runEdit(
          'Box added',
          (doc) => PdfTools.addBox(doc, pageIndex,
              x: x,
              y: y,
              width: double.parse(values[2]),
              height: double.parse(values[3])),
        );
      case _PlacementKind.textField:
        await _runEdit(
          'Fillable field added',
          (doc) => PdfTools.addFillableTextField(doc, pageIndex, values[0],
              x: x,
              y: y,
              width: double.parse(values[3]),
              height: double.parse(values[4])),
        );
      case _PlacementKind.checkbox:
        await _runEdit(
          'Checkbox added',
          (doc) => PdfTools.addFillableCheckBox(doc, pageIndex, values[0],
              x: x, y: y),
        );
      case _PlacementKind.yesNo:
        await _runEdit(
          'Yes / No choice added',
          (doc) => PdfTools.addYesNoChoice(
            doc,
            pageIndex,
            values[0],
            values[1],
            x: x,
            y: y,
          ),
        );
      case _PlacementKind.clickBox:
        await _runEdit(
          'Click box added',
          (doc) => PdfTools.addClickBox(
            doc,
            pageIndex,
            values[0],
            values[1],
            x: x,
            y: y,
            width: double.parse(values[2]),
            height: double.parse(values[3]),
          ),
        );
      case _PlacementKind.image:
        if (bytes == null) {
          _showError('Image data was not available.');
          return;
        }
        await _runEdit(
          'Image added',
          (doc) => PdfTools.addImage(
            doc,
            pageIndex,
            bytes,
            x: x,
            y: y,
            width: double.parse(values[2]),
            height: double.parse(values[3]),
          ),
        );
    }
  }

  Future<void> _runEdit(
    String progressMessage,
    void Function(PdfDocument doc) edit,
  ) async {
    try {
      await _state.transform(edit);
      _showMessage(progressMessage);
    } catch (e) {
      _showError('$e');
    }
  }

  Future<void> _rotateCurrentPage() {
    final index = _state.currentPage - 1;
    return _runEdit(
      'Rotated page ${index + 1}',
      (doc) => PdfTools.rotatePage(doc, index),
    );
  }

  Future<void> _confirmDeletePage() async {
    final index = _state.currentPage - 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete page?'),
        content: Text(
          'Page ${index + 1} will be removed from this document.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runEdit(
      'Deleted page ${index + 1}',
      (doc) => PdfTools.deletePage(doc, index),
    );
  }

  Future<void> _addWatermark() async {
    final text = await _askText(
      title: 'Add watermark',
      hint: 'For example: DRAFT or CONFIDENTIAL',
    );
    if (text == null || text.isEmpty) return;
    await _runEdit('Watermark added', (doc) => PdfTools.addWatermark(doc, text));
  }

  Future<void> _protectWithPassword() async {
    final password = await _askText(
      title: 'Set password',
      hint: 'Required to open and edit this PDF',
      obscure: true,
    );
    if (password == null || password.isEmpty) return;
    _state.setPassword(password);
    _showMessage('Password will be applied when you save.');
  }

  Future<void> _editFontSettings() async {
    final sizeController =
        TextEditingController(text: '${_fontSettings.size}');
    final colorController =
        TextEditingController(text: _hexColor(_fontSettings.color));
    var family = _fontSettings.family;
    var bold = _fontSettings.bold;
    var italic = _fontSettings.italic;
    var underline = _fontSettings.underline;
    var strikethrough = _fontSettings.strikethrough;
    var previewColor = _fontSettings.color;
    String? error;

    final updated = await showDialog<_FontSettings>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Font'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<PdfFontFamily>(
                  initialValue: family,
                  decoration: const InputDecoration(labelText: 'Font family'),
                  items: [
                    for (final (value, label) in _fontFamilies)
                      DropdownMenuItem(value: value, child: Text(label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => family = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sizeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Font size (4-72)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: colorController,
                  decoration: const InputDecoration(
                    labelText: 'Font color (#RRGGBB)',
                  ),
                  onChanged: (value) {
                    final parsed = _parseHexColor(value);
                    if (parsed != null) setState(() => previewColor = parsed);
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (swatch, label) in _fontColors)
                      Tooltip(
                        message: label,
                        child: InkWell(
                          onTap: () {
                            colorController.text = _hexColor(swatch);
                            setState(() => previewColor = swatch);
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: swatch,
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bold'),
                  value: bold,
                  onChanged: (value) => setState(() => bold = value ?? false),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Italic'),
                  value: italic,
                  onChanged: (value) => setState(() => italic = value ?? false),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Underline'),
                  value: underline,
                  onChanged: (value) =>
                      setState(() => underline = value ?? false),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Strikethrough'),
                  value: strikethrough,
                  onChanged: (value) =>
                      setState(() => strikethrough = value ?? false),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Aa Bb Cc 123',
                    style: TextStyle(
                      color: previewColor,
                      fontSize: 20,
                      fontFamily: family == PdfFontFamily.courier
                          ? 'monospace'
                          : family == PdfFontFamily.timesRoman
                              ? 'serif'
                              : null,
                      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                      fontStyle:
                          italic ? FontStyle.italic : FontStyle.normal,
                      decoration: TextDecoration.combine([
                        if (underline) TextDecoration.underline,
                        if (strikethrough) TextDecoration.lineThrough,
                      ]),
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: Colors.red.shade700)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final parsedSize = double.tryParse(sizeController.text.trim());
                final parsedColor = _parseHexColor(colorController.text.trim());
                if (parsedSize == null ||
                    !parsedSize.isFinite ||
                    parsedSize < 4 ||
                    parsedSize > 72) {
                  setState(() => error = 'Font size must be between 4 and 72.');
                  return;
                }
                if (parsedColor == null) {
                  setState(() => error = 'Enter a color like #1E88E5.');
                  return;
                }
                Navigator.of(dialogContext).pop(
                  _FontSettings(
                    family: family,
                    size: parsedSize,
                    color: parsedColor,
                    bold: bold,
                    italic: italic,
                    underline: underline,
                    strikethrough: strikethrough,
                  ),
                );
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    sizeController.dispose();
    colorController.dispose();
    if (updated == null) return;
    setState(() => _fontSettings = updated);
    _showMessage('Font updated');
  }

  String _hexColor(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  Color? _parseHexColor(String value) {
    final hex = value.trim().replaceFirst('#', '');
    if (hex.length != 6 && hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return Color(hex.length == 6 ? 0xFF000000 | parsed : parsed);
  }

  PdfColor _pdfColor(Color color) {
    final argb = color.toARGB32();
    return PdfColor(
      (argb >> 16) & 0xFF,
      (argb >> 8) & 0xFF,
      argb & 0xFF,
      (argb >> 24) & 0xFF,
    );
  }

  Future<void> _addText() async {
    final pageIndex = _state.currentPage - 1;
    final result = await _askFields(
      'Add text',
      const [
        ('Text', 'Text to place on the page', ''),
        ('X', 'Left position in PDF points', '72'),
        ('Y', 'Top position in PDF points', '72'),
      ],
      pickOnPage: true,
    );
    if (result == null) return;
    final values = result.values;
    if (values[0].isEmpty) {
      _showError('Enter the text to add.');
      return;
    }
    if (result.pickOnPage) {
      _beginPlacement(_PlacementKind.text, values);
      return;
    }
    final nums = _parseNumbers(values, 1, 2, 'X and Y');
    if (nums == null) return;
    if (nums[0] < 0 || nums[1] < 0) {
      _showError('X and Y cannot be negative.');
      return;
    }
    await _applyPlacementValue(
        _PlacementKind.text, pageIndex, nums[0], nums[1], values);
  }

  Future<void> _addBox() async {
    final pageIndex = _state.currentPage - 1;
    final result = await _askFields(
      'Add box',
      const [
        ('X', 'Left position in PDF points', '72'),
        ('Y', 'Top position in PDF points', '72'),
        ('Width', 'Box width in PDF points', '200'),
        ('Height', 'Box height in PDF points', '80'),
      ],
      pickOnPage: true,
    );
    if (result == null) return;
    final values = result.values;
    final size = _parseNumbers(values, 2, 2, 'width and height');
    if (size == null) return;
    if (size[0] <= 0 || size[1] <= 0) {
      _showError('Width and height must be greater than zero.');
      return;
    }
    if (result.pickOnPage) {
      _beginPlacement(_PlacementKind.box, values);
      return;
    }
    final nums = _parseNumbers(values, 0, 2, 'X and Y');
    if (nums == null) return;
    if (nums[0] < 0 || nums[1] < 0) {
      _showError('X and Y cannot be negative.');
      return;
    }
    await _applyPlacementValue(
        _PlacementKind.box, pageIndex, nums[0], nums[1], values);
  }

  Future<void> _addFillableField() async {
    final pageIndex = _state.currentPage - 1;
    final result = await _askFields(
      'Add fillable text field',
      const [
        ('Field name', 'For example: full_name', 'field'),
        ('X', 'Left position in PDF points', '72'),
        ('Y', 'Top position in PDF points', '120'),
        ('Width', 'Field width in PDF points', '200'),
        ('Height', 'Field height in PDF points', '24'),
      ],
      pickOnPage: true,
    );
    if (result == null) return;
    final values = result.values;
    final size = _parseNumbers(values, 3, 2, 'width and height');
    if (size == null) return;
    if (size[0] <= 0 || size[1] <= 0) {
      _showError('Width and height must be greater than zero.');
      return;
    }
    if (result.pickOnPage) {
      _beginPlacement(_PlacementKind.textField, values);
      return;
    }
    final nums = _parseNumbers(values, 1, 2, 'X and Y');
    if (nums == null) return;
    if (nums[0] < 0 || nums[1] < 0) {
      _showError('X and Y cannot be negative.');
      return;
    }
    await _applyPlacementValue(
        _PlacementKind.textField, pageIndex, nums[0], nums[1], values);
  }

  Future<void> _addFillableCheckbox() async {
    final pageIndex = _state.currentPage - 1;
    final result = await _askFields(
      'Add fillable checkbox',
      const [
        ('Field name', 'For example: agreed', 'check'),
        ('X', 'Left position in PDF points', '72'),
        ('Y', 'Top position in PDF points', '160'),
      ],
      pickOnPage: true,
    );
    if (result == null) return;
    final values = result.values;
    if (result.pickOnPage) {
      _beginPlacement(_PlacementKind.checkbox, values);
      return;
    }
    final nums = _parseNumbers(values, 1, 2, 'X and Y');
    if (nums == null) return;
    if (nums[0] < 0 || nums[1] < 0) {
      _showError('X and Y cannot be negative.');
      return;
    }
    await _applyPlacementValue(
        _PlacementKind.checkbox, pageIndex, nums[0], nums[1], values);
  }

  Future<void> _replaceText() async {
    final pageIndex = _state.currentPage - 1;
    final result = await _askFields('Replace text', const [
      ('Find', 'Existing text on this page', ''),
      ('Replace with', 'Leave empty to remove the text', ''),
    ]);
    if (result == null || result.values[0].isEmpty) return;
    await _replaceAt(pageIndex, result.values[0], result.values[1]);
  }

  Future<void> _replaceSelected() async {
    final selected = _selectedText;
    if (selected == null) return;
    final pageIndex = _selectedPageIndex ?? _state.currentPage - 1;
    final result = await _askFields(
      'Replace selected text',
      [
        ('Find', 'Text selected in the viewer', selected),
        ('Replace with', 'Leave empty to remove the text', ''),
      ],
    );
    if (result == null || result.values[0].isEmpty) return;
    await _replaceAt(pageIndex, result.values[0], result.values[1]);
  }

  Future<void> _replaceAt(int pageIndex, String find, String replacement) async {
    var count = 0;
    try {
      await _state.transform(
        (doc) => count = PdfTools.replaceText(
          doc,
          pageIndex,
          find,
          replacement,
          family: _fontSettings.family,
          size: _fontSettings.size,
          color: _pdfColor(_fontSettings.color),
          bold: _fontSettings.bold,
          italic: _fontSettings.italic,
          underline: _fontSettings.underline,
          strikethrough: _fontSettings.strikethrough,
        ),
      );
    } catch (e) {
      _showError('$e');
      return;
    }
    _clearSelectedText();
    _showMessage(
      count == 0
          ? 'Text not found on this page'
          : 'Updated $count occurrence${count == 1 ? '' : 's'}',
    );
  }

  Future<void> _deleteText() async {
    final pageIndex = _state.currentPage - 1;
    final result = await _askFields('Delete text', const [
      ('Find', 'Existing text to hide on this page', ''),
    ]);
    if (result == null || result.values[0].isEmpty) return;
    final values = result.values;
    var count = 0;
    try {
      await _state.transform(
        (doc) => count = PdfTools.deleteText(doc, pageIndex, values[0]),
      );
    } catch (e) {
      _showError('$e');
      return;
    }
    _clearSelectedText();
    _showMessage(
      count == 0
          ? 'Text not found on this page'
          : 'Removed $count occurrence${count == 1 ? '' : 's'}',
    );
  }

  Future<void> _addYesNoChoice() async {
    final pageIndex = _state.currentPage - 1;
    final result = await _askFields(
      'Add Yes / No choice',
      const [
        ('Question', 'For example: Do you agree?', ''),
        ('Field name', 'For example: agree', 'choice'),
        ('X', 'Left position in PDF points', '72'),
        ('Y', 'Top position in PDF points', '240'),
      ],
      pickOnPage: true,
    );
    if (result == null) return;
    final values = result.values;
    if (result.pickOnPage) {
      _beginPlacement(_PlacementKind.yesNo, values);
      return;
    }
    final nums = _parseNumbers(values, 2, 2, 'X and Y');
    if (nums == null) return;
    if (nums[0] < 0 || nums[1] < 0) {
      _showError('X and Y cannot be negative.');
      return;
    }
    await _applyPlacementValue(
        _PlacementKind.yesNo, pageIndex, nums[0], nums[1], values);
  }

  Future<void> _addClickBox() async {
    final pageIndex = _state.currentPage - 1;
    final result = await _askFields(
      'Add click box',
      const [
        ('Caption', 'For example: Submit', 'Click'),
        ('Field name', 'For example: submit', 'button'),
        ('X', 'Left position in PDF points', '72'),
        ('Y', 'Top position in PDF points', '280'),
        ('Width', 'Button width in PDF points', '100'),
        ('Height', 'Button height in PDF points', '28'),
      ],
      pickOnPage: true,
    );
    if (result == null) return;
    final values = result.values;
    final size = _parseNumbers(values, 4, 2, 'width and height');
    if (size == null) return;
    if (size[0] <= 0 || size[1] <= 0) {
      _showError('Width and height must be greater than zero.');
      return;
    }
    if (result.pickOnPage) {
      _beginPlacement(_PlacementKind.clickBox, values);
      return;
    }
    final nums = _parseNumbers(values, 2, 2, 'X and Y');
    if (nums == null) return;
    if (nums[0] < 0 || nums[1] < 0) {
      _showError('X and Y cannot be negative.');
      return;
    }
    await _applyPlacementValue(
        _PlacementKind.clickBox, pageIndex, nums[0], nums[1], values);
  }

  Future<void> _addImage() async {
    try {
      final asset = await FileService.pickImage();
      if (asset == null) return;
      final pageIndex = _state.currentPage - 1;
      final result = await _askFields(
        'Add image',
        const [
          ('X', 'Left position in PDF points', '72'),
          ('Y', 'Top position in PDF points', '320'),
          ('Width', 'Image width in PDF points', '160'),
          ('Height', 'Image height in PDF points', '120'),
        ],
        pickOnPage: true,
      );
      if (result == null) return;
      final values = result.values;
      final size = _parseNumbers(values, 2, 2, 'width and height');
      if (size == null) return;
      if (size[0] <= 0 || size[1] <= 0) {
        _showError('Width and height must be greater than zero.');
        return;
      }
      if (result.pickOnPage) {
        _beginPlacement(_PlacementKind.image, values, bytes: asset.bytes);
        return;
      }
      final nums = _parseNumbers(values, 0, 2, 'X and Y');
      if (nums == null) return;
      if (nums[0] < 0 || nums[1] < 0) {
        _showError('X and Y cannot be negative.');
        return;
      }
      await _applyPlacementValue(
        _PlacementKind.image,
        pageIndex,
        nums[0],
        nums[1],
        values,
        bytes: asset.bytes,
      );
    } catch (e) {
      _showError('Could not add that image. $e');
    }
  }

  Future<void> _attachVideo() async {
    try {
      final asset = await FileService.pickVideo();
      if (asset == null) return;
      await _runEdit(
        'Video attached to the PDF',
        (doc) => PdfTools.attachFile(
          doc,
          asset.name,
          asset.bytes,
          description: 'Attached video',
          mimeType: _videoMimeType(asset.name),
        ),
      );
    } catch (e) {
      _showError('Could not attach that video. $e');
    }
  }

  String _videoMimeType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      default:
        return 'application/octet-stream';
    }
  }

  List<double>? _parseNumbers(
    List<String> values,
    int start,
    int count,
    String label,
  ) {
    final result = <double>[];
    for (var i = start; i < start + count; i++) {
      final value = double.tryParse(values[i]);
      if (value == null || !value.isFinite) {
        _showError('Enter valid numbers for $label.');
        return null;
      }
      result.add(value);
    }
    return result;
  }

  Future<_FieldDialogResult?> _askFields(
    String title,
    List<(String label, String hint, String initial)> fields, {
    bool pickOnPage = false,
  }) async {
    final controllers = [
      for (final field in fields) TextEditingController(text: field.$3),
    ];
    List<String> values() => [
          for (final controller in controllers) controller.text.trim(),
        ];
    final result = await showDialog<_FieldDialogResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                TextField(
                  controller: controllers[i],
                  autofocus: i == 0,
                  textInputAction: i == fields.length - 1
                      ? TextInputAction.done
                      : TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: fields[i].$1,
                    hintText: fields[i].$2,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (pickOnPage)
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                _FieldDialogResult(values(), true),
              ),
              child: const Text('Pick on page'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _FieldDialogResult(values(), false),
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    for (final controller in controllers) {
      controller.dispose();
    }
    return result;
  }

  Future<String?> _askText({
    required String title,
    required String hint,
    bool obscure = false,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _showShortcuts() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keyboard shortcuts'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.folder_open_outlined),
              title: Text('Open PDF'),
              trailing: Text('Ctrl / Cmd + O'),
            ),
            ListTile(
              leading: Icon(Icons.save_outlined),
              title: Text('Save PDF'),
              trailing: Text('Ctrl / Cmd + S'),
            ),
            ListTile(
              leading: Icon(Icons.undo),
              title: Text('Undo / Redo'),
              trailing: Text('Ctrl / Cmd + Z / Shift + Z'),
            ),
            ListTile(
              leading: Icon(Icons.keyboard_arrow_right),
              title: Text('Next / previous page'),
              trailing: Text('Page Down / Page Up'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  void _showError(String message) => _showMessage('Error: $message');

  String get _activeToolLabel =>
      _annotationTools.firstWhere((tool) => tool.$1 == _mode).$2;

  String get _placementLabel {
    switch (_placement?.kind) {
      case _PlacementKind.text:
        return 'Tap the page to place text';
      case _PlacementKind.box:
        return 'Tap the page to place a box';
      case _PlacementKind.textField:
        return 'Tap the page to place a text field';
      case _PlacementKind.checkbox:
        return 'Tap the page to place a checkbox';
      case _PlacementKind.yesNo:
        return 'Tap the page to place the Yes / No choice';
      case _PlacementKind.clickBox:
        return 'Tap the page to place the click box';
      case _PlacementKind.image:
        return 'Tap the page to place the image';
      case null:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): _open,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): _open,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ,
            control: true, shift: true): _redo,
        const SingleActivator(LogicalKeyboardKey.keyZ,
            meta: true, shift: true): _redo,
        LogicalKeySet(LogicalKeyboardKey.pageUp): () => _turnPage(false),
        LogicalKeySet(LogicalKeyboardKey.pageDown): () => _turnPage(true),
        LogicalKeySet(LogicalKeyboardKey.escape): _cancelPlacement,
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: Listenable.merge([_state, _undoController]),
          builder: (context, _) {
            final hasDoc = _state.hasDocument;

            return Scaffold(
              appBar: AppBar(
                leading: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/icons/app_icon.png',
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PDF Studio'),
                    if (hasDoc)
                      Text(
                        _state.name,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                actions: [
                  if (hasDoc)
                    IconButton(
                      tooltip: 'Close document',
                      icon: const Icon(Icons.close_outlined),
                      onPressed: _close,
                    ),
                  IconButton(
                    tooltip: 'Open PDF (Ctrl/Cmd + O)',
                    icon: const Icon(Icons.folder_open_outlined),
                    onPressed: _open,
                  ),
                  IconButton(
                    tooltip: 'Save PDF (Ctrl/Cmd + S)',
                    icon: const Icon(Icons.save_outlined),
                    onPressed: hasDoc && !_state.isBusy ? _save : null,
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More options',
                    onSelected: (value) {
                      if (value == 'shortcuts') _showShortcuts();
                      if (value == 'clear_password') _removePassword();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: 'shortcuts',
                        child: Text('Keyboard shortcuts'),
                      ),
                      if (_state.hasPassword)
                        const PopupMenuItem<String>(
                          value: 'clear_password',
                          child: Text('Remove password before saving'),
                        ),
                    ],
                  ),
                ],
              ),
              body: hasDoc ? _buildEditor() : _buildEmptyState(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/icons/app_icon.png',
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('No PDF open', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Open a PDF to annotate it, edit pages, add watermarks,\n'
                'protect it with a password and create fillable forms.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _open,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open PDF'),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final feature in _features)
                    Chip(
                      label: Text(feature),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      children: [
        _buildAnnotationBar(),
        _buildDocumentBar(),
        if (_state.isBusy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: Stack(
            children: [
              SfPdfViewer.memory(
                _state.bytes!,
                key: ValueKey(_state.revision),
                controller: _state.viewerController,
                undoController: _undoController,
                canShowScrollHead: true,
                enableDoubleTapZooming: true,
                enableTextSelection: true,
                initialPageNumber: _state.currentPage,
                maxZoomLevel: 3,
                onTap: _handleViewerTap,
                onTextSelectionChanged: _handleTextSelectionChanged,
                onPageChanged: (details) =>
                    _state.setPageNumber(details.newPageNumber),
                onDocumentLoadFailed: (details) =>
                    _showError('${details.error}: ${details.description}'),
              ),
              if (_placement != null) _buildPlacementOverlay(),
              if (_placement == null && _selectedText != null)
                _buildSelectionOverlay(),
            ],
          ),
        ),
        _buildStatusBar(),
      ],
    );
  }

  Widget _buildPlacementOverlay() {
    final theme = Theme.of(context);
    final pointer = _placementPointer;
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _updatePlacementPointer,
            onPointerMove: _updatePlacementPointer,
            onPointerHover: _updatePlacementPointer,
            child: const SizedBox.expand(),
          ),
        ),
        if (pointer != null)
          Positioned(
            left: pointer.dx - 18,
            top: pointer.dy - 18,
            child: IgnorePointer(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.add,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
            ),
          ),
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_location_alt_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(_placementLabel),
                    IconButton(
                      tooltip: 'Cancel placement (Esc)',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _cancelPlacement,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionOverlay() {
    final selected = _selectedText ?? '';
    return Positioned(
      top: 12,
      right: 12,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Text(
                    'Selected: $selected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _replaceSelected,
                  child: const Text('Replace'),
                ),
                IconButton(
                  tooltip: 'Clear selection',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _clearSelectedText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnnotationBar() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: Divider.createBorderSide(context)),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'ANNOTATE',
              style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 12),
                itemCount: _annotationTools.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final (mode, label, icon) = _annotationTools[i];
                  return FilterChip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(icon, size: 16),
                    label: Text(label),
                    selected: _mode == mode,
                    showCheckmark: false,
                    onSelected: (_) => _setMode(mode),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentBar() {
    final theme = Theme.of(context);
    final busy = _state.isBusy;
    final tools = <(String, String, IconData, VoidCallback?)>[
      ('History', 'Undo', Icons.undo,
          _undoController.value.canUndo && !busy ? _undo : null),
      ('History', 'Redo', Icons.redo,
          _undoController.value.canRedo && !busy ? _redo : null),
      ('View', 'Zoom out', Icons.zoom_out, !busy ? () => _zoom(-0.25) : null),
      ('View', 'Zoom in', Icons.zoom_in, !busy ? () => _zoom(0.25) : null),
      ('View', 'Reset zoom', Icons.aspect_ratio, !busy ? _resetZoom : null),
      ('Page', 'Previous', Icons.keyboard_arrow_left,
          !busy ? () => _turnPage(false) : null),
      ('Page', 'Next', Icons.keyboard_arrow_right,
          !busy ? () => _turnPage(true) : null),
      ('Page', 'Rotate', Icons.rotate_right, !busy ? _rotateCurrentPage : null),
      ('Page', 'Delete', Icons.delete_outline,
          !busy ? _confirmDeletePage : null),
      ('Content', 'Watermark', Icons.water_drop_outlined,
          !busy ? _addWatermark : null),
      ('Content', 'Password', Icons.lock_outline,
          !busy ? _protectWithPassword : null),
      ('Content', 'Replace', Icons.find_replace, !busy ? _replaceText : null),
      (
        'Content',
        'Replace selected',
        Icons.find_replace,
        !busy && _selectedText != null ? _replaceSelected : null
      ),
      ('Content', 'Hide text', Icons.backspace_outlined,
          !busy ? _deleteText : null),
      ('Content', 'Font', Icons.font_download, !busy ? _editFontSettings : null),
      ('Content', 'Add text', Icons.text_fields, !busy ? _addText : null),
      ('Content', 'Add box', Icons.crop_square_outlined, !busy ? _addBox : null),
      ('Forms', 'Yes / No', Icons.radio_button_checked,
          !busy ? _addYesNoChoice : null),
      ('Forms', 'Fill box', Icons.text_snippet_outlined,
          !busy ? _addFillableField : null),
      ('Forms', 'Checkbox', Icons.check_box_outlined,
          !busy ? _addFillableCheckbox : null),
      ('Forms', 'Click box', Icons.touch_app, !busy ? _addClickBox : null),
      ('Media', 'Add image', Icons.image_outlined, !busy ? _addImage : null),
      ('Media', 'Attach video', Icons.movie_outlined,
          !busy ? _attachVideo : null),
      ('File', 'Save', Icons.save_outlined, !busy ? _save : null),
    ];

    final children = <Widget>[];
    String? previousGroup;
    for (final (group, label, icon, onPressed) in tools) {
      if (previousGroup != null && group != previousGroup) {
        children.add(const SizedBox(width: 12));
      }
      children.add(_toolButton(label, icon, onPressed));
      previousGroup = group;
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: Divider.createBorderSide(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Wrap(
          spacing: 2,
          runSpacing: 2,
          children: children,
        ),
      ),
    );
  }

  Widget _toolButton(String label, IconData icon, VoidCallback? onPressed) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: SizedBox(
        width: 74,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    final theme = Theme.of(context);
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: Divider.createBorderSide(context)),
      ),
      child: ListenableBuilder(
        listenable: _state.viewerController,
        builder: (context, _) {
          final controller = _state.viewerController;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  _annotationTools.firstWhere((tool) => tool.$1 == _mode).$3,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  _placement != null ? _placementLabel : _activeToolLabel,
                  style: theme.textTheme.labelSmall,
                ),
                if (_state.hasPassword) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.lock_outline,
                      size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text('Protected', style: theme.textTheme.labelSmall),
                ],
                const Spacer(),
                Text(
                  '${controller.pageNumber} / ${controller.pageCount}',
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(width: 12),
                Text(
                  '${(controller.zoomLevel * 100).round()}%',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _undo() {
    if (_undoController.value.canUndo) _undoController.undo();
  }

  void _redo() {
    if (_undoController.value.canRedo) _undoController.redo();
  }
}
