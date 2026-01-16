class PDFFile {
  String name;
  String date;
  String size;
  bool isFavorite;
  String? filePath; // Path to the actual PDF file
  DateTime? lastAccessed; // When the PDF was last opened

  PDFFile({
    required this.name,
    required this.date,
    required this.size,
    required this.isFavorite,
    this.filePath,
    this.lastAccessed,
  });
}
