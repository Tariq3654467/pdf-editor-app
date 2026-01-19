## PDF Editor App

A Flutter application for viewing and editing PDF files on mobile and desktop. It provides rich viewing controls, annotations, and basic PDF editing, built on top of `syncfusion_flutter_pdfviewer` and related PDF utilities.

### Features

- **Open PDFs from device storage** using a file picker.
- **PDF viewing** with page navigation, jump to page, and page indicator.
- **Multiple view modes**: vertical scroll, horizontal/page view (depending on your implementation).
- **Annotations & editing**:
  - Pen, highlighter, underline, and eraser tools.
  - Text editing overlay on PDF pages (Sejda-style).
  - Undo/redo support for annotation actions.
- **Bookmarks & recent files**:
  - Auto-bookmark when a PDF is opened.
  - Store favorites and last-accessed time using shared preferences.
- **Sharing & printing**:
  - Share PDFs via system share sheet (`share_plus`).
  - Print or generate print previews (`printing`).
- **Preferences & UI**:
  - Dark/light mode toggle.
  - Remembered user preferences between sessions.

### Tech Stack

- **Flutter** with Material Design.
- **PDF & printing**: `syncfusion_flutter_pdfviewer`, `syncfusion_flutter_pdf`, `pdf`, `printing`.
- **File handling**: `file_picker`, `path_provider`, `path`, `archive`, `image`.
- **Device integration**: `share_plus`, `permission_handler`, `url_launcher`, `in_app_review`, `shared_preferences`.

### Requirements

- **Flutter/Dart**: Dart SDK `^3.9.2` (Flutter 3.22+ recommended).
- **Platforms**: Android, iOS, and any desktop platform supported by Flutter.

### Getting Started

1. **Install dependencies**:

   ```bash
   flutter pub get
   ```

2. **Run the app**:

   ```bash
   flutter run
   ```

3. **Run on a specific device** (optional):

   ```bash
   flutter run -d <device_id>
   ```

### Project Structure

- **`lib/screens/pdf_viewer_screen.dart`**: Main PDF viewer and editor screen (navigation, view modes, annotation toolbar, etc.).
- **`lib/services/pdf_service.dart`**: General PDF utilities (file size/date formatting, loading helpers, etc.).
- **`lib/services/pdf_tools_service.dart`**: Tools for working with PDF content and annotations.
- **`lib/services/pdf_preferences_service.dart`**: Bookmarks, favorites, and user preferences (SharedPreferences).
- **`lib/services/pdf_text_editor_service.dart`**: Logic for text editing on top of pages.
- **`lib/models/pdf_file.dart`**: Data model for representing a PDF file and its metadata.
- **`lib/widgets/pdf_annotation_overlay.dart`**: Custom widget responsible for drawing and managing annotations.

### Notes

- This project uses third-party packages like Syncfusion for PDF viewing; make sure you comply with their licensing terms.
- Some mobile platforms may require extra permissions (e.g., storage access); check and update Android and iOS configs as needed.
