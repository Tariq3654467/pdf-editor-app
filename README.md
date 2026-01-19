## PDF Editor App

A Flutter application for viewing and editing PDF files on mobile/desktop. It supports rich viewing controls, annotations, and basic PDF editing using `syncfusion_flutter_pdfviewer` and related PDF tools.

## Features

- **Open PDFs from device storage** using file picker.
- **View PDFs** with page navigation, page indicator, and multiple view modes.
- **Annotate and edit**: pen, highlight, underline, eraser, and text editing on pages.
- **Bookmarks & recent files** using shared preferences.
- **Share & print** PDFs via `share_plus` and `printing`.
- **Dark mode and UI preferences** persisted between sessions.

## Requirements

- **Flutter SDK**: Dart SDK ^3.9.2 (Flutter 3.22+ recommended).
- **Platforms**: Android, iOS, and desktop platforms supported by Flutter.

## Getting Started

```bash
flutter pub get
flutter run
```

You can target a specific device with:

```bash
flutter run -d <device_id>
```

## Project Structure

- **`lib/screens/pdf_viewer_screen.dart`**: Main PDF viewer and editor screen.
- **`lib/services/*`**: PDF loading, tools, preferences, and text editing services.
- **`lib/models/*`**: Data models such as `PDFFile`.
- **`lib/widgets/*`**: UI components like the annotation overlay.

# pdf_editor_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
