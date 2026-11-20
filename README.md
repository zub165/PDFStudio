# PDF Studio

A PDF editor built with Flutter for Web, Windows, macOS, Linux and Android.

**Live demo:** https://zub165.github.io/PDFstdio/
**Repository:** https://github.com/zub165/PDFstdio

## Features

- Open and view PDFs (pinch or double-tap to zoom, select text)
- Annotate: highlight, underline, strikethrough, squiggly, sticky notes
- Rotate or delete the current page
- Add a diagonal text watermark to every page
- Protect the file with an AES-256 password (applied when you save)
- Select text in the viewer and use **Replace selected**, or find/replace text on the current page
- Add new text, an outlined box, fillable text fields, checkboxes, labelled Yes/No radio choices and click-box push buttons
- Place images on a page and attach video files to the PDF
- Choose an exact position with **Pick on page**: tap or drag the crosshair over the PDF instead of typing X/Y
- Save (desktop and Android use a save dialog; web downloads the file)
- Keyboard shortcuts, labelled toolbars, a status bar, input validation and a confirmation before deleting a page

**Text editing limitation.** "Replace text" and "Delete text" cover the matched
text with the page's background colour and draw the replacement over it. The
original characters remain in the PDF content stream and can still be found by
text extraction or copied. Truly removing them requires flattening the page to
an image or using a different PDF engine. This also assumes a plain white page
background; it will not blend with coloured or image backgrounds.

Form fields added with "Fillable text field", "Fillable checkbox" or
"Yes / No choice" are real AcroForm fields, so they can be clicked and filled in
the viewer and saved with the document. **Click box** adds a push-button field,
but Syncfusion's viewer does not render push buttons as interactive controls, so
it will mainly be visible in other PDF viewers.

PDF AcroForm has no "fillable image" or "fillable video" field type. **Add image**
draws a static image onto the page, and **Attach video** embeds the file in the
PDF attachment list. Syncfusion's viewer does not expose drag handles for moving
fields after they are created, and text/boxes are drawn into the page, not
separate Flutter widgets. Use **Pick on page** when adding an item to choose its
exact position; press `Esc` to cancel placement.

Setting a password does not reload the viewer with encrypted bytes. The password
is kept with the editing session and applied only to the file you save; the
"Remove password before saving" menu item clears it.

On web, `web/index.html` loads PDF.js from cdnjs; an internet connection is
required for the viewer to render pages.

## Setup

The `lib/`, `pubspec.yaml` and this README are the app code. Flutter also needs
platform folders, which it generates for you:

```bash
flutter create --platforms=android,web,windows,macos,linux --project-name pdf_studio .
```

Run it inside the `pdf_studio` folder. Afterwards, check that `lib/` and
`pubspec.yaml` still match the files here. If `flutter create` replaced any of
them, copy the originals back from this download.

Then fetch packages and run:

```bash
flutter pub get
flutter run -d chrome        # Web
flutter run -d windows       # or macos / linux
flutter run -d <android-id>  # Android device or emulator
```

Build release versions:

```bash
flutter build web
flutter build apk            # or appbundle for the Play Store
flutter build windows        # or macos / linux
```

## Platform notes

**Android.** No extra permissions are needed. The file picker uses the system
document picker. Keep `minSdkVersion` at 21 or higher in
`android/app/build.gradle`.

**macOS.** File access in the sandbox needs the read/write entitlement. Add this
to `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

**Web.** Files are read into memory and saved as downloads. No server is needed.

**Syncfusion license.** The packages are free under the Syncfusion Community
License for individuals and small companies. In the pinned 27.x packages
license registration is deprecated and no key needs to be entered in the app;
check Syncfusion's current terms before commercial use.

## Project layout

```
lib/
  main.dart                     App entry point and theme
  screens/editor_screen.dart    Viewer, toolbars, dialogs, menus, shortcuts
  state/pdf_editor_state.dart   Holds the open PDF, annotations and password
  services/file_service.dart    Open and save (works on every platform)
  services/pdf_tools.dart       PDF edits, form fields and validation
assets/
  icons/app_icon.png            In-app and web app icon
web/
  favicon.png, icons/*          Generated from assets/icons/app_icon.png
```

## Ideas for next steps

- Freehand ink annotation (not exposed by the Syncfusion 27.x viewer's annotation modes)
- Merge several PDFs and extract page ranges (`PdfDocument` plus page imports)
- Add signatures by drawing on a page and placing it with `PdfBitmap`
- True text removal (not just a visual overlay), which needs a different PDF engine or a server-side tool
- Undo structural edits (rotate, delete, watermark) by keeping a stack of document bytes
- Use `pdfrx` or a native engine if you need very large files to render faster
