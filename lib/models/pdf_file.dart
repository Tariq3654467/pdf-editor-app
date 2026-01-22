class PDFFile {
  String name;
  String date;
  String size;
  bool isFavorite;
  String? filePath; // Path to the actual PDF file
  DateTime? lastAccessed; // When the PDF was last opened
  String? folderPath; // Folder path for grouping
  String? folderName; // Display name of the folder
  DateTime? dateModified; // Actual DateTime for sorting
  int? fileSizeBytes; // File size in bytes for sorting

  PDFFile({
    required this.name,
    required this.date,
    required this.size,
    required this.isFavorite,
    this.filePath,
    this.lastAccessed,
    this.folderPath,
    this.folderName,
    this.dateModified,
    this.fileSizeBytes,
  });
  
  // Factory constructor for creating from map
  factory PDFFile.fromMap(Map<String, dynamic> map) {
    return PDFFile(
      name: map['name'] as String? ?? 'Unknown',
      date: map['date'] as String? ?? '',
      size: map['size'] as String? ?? '0 B',
      isFavorite: map['isFavorite'] as bool? ?? false,
      filePath: map['filePath'] as String?,
      lastAccessed: map['lastAccessed'] != null 
          ? DateTime.tryParse(map['lastAccessed'].toString())
          : null,
      folderPath: map['folderPath'] as String?,
      folderName: map['folderName'] as String?,
      dateModified: map['dateModified'] != null
          ? (map['dateModified'] is DateTime
              ? map['dateModified'] as DateTime
              : DateTime.tryParse(map['dateModified'].toString()))
          : null,
      fileSizeBytes: map['fileSizeBytes'] as int?,
    );
  }
}

// Model for grouping PDFs by folder
class PDFFolder {
  String folderPath;
  String folderName;
  List<PDFFile> pdfs;
  int totalSize; // Total size in bytes
  DateTime? lastModified; // Most recent modification date

  PDFFolder({
    required this.folderPath,
    required this.folderName,
    required this.pdfs,
    this.totalSize = 0,
    this.lastModified,
  });
  
  int get count => pdfs.length;
  
  String get formattedSize {
    if (totalSize < 1024) {
      return '$totalSize B';
    } else if (totalSize < 1024 * 1024) {
      return '${(totalSize / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}
