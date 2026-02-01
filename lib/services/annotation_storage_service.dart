import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/pdf_annotation.dart';

/// Service to persist and load PDF annotations
class AnnotationStorageService {
  static const String _annotationsDir = 'annotations';
  static AnnotationStorageService? _instance;

  AnnotationStorageService._();

  factory AnnotationStorageService() {
    _instance ??= AnnotationStorageService._();
    return _instance!;
  }

  /// Get annotations file path for a PDF
  Future<File> _getAnnotationsFile(String pdfPath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final annotationsDir = Directory('${appDir.path}/$_annotationsDir');
    if (!await annotationsDir.exists()) {
      await annotationsDir.create(recursive: true);
    }

    // Create a unique filename based on PDF path hash
    final pdfHash = pdfPath.hashCode.toString();
    return File('${annotationsDir.path}/$pdfHash.json');
  }

  /// Save all annotations for a PDF
  Future<bool> saveAnnotations(String pdfPath, List<PDFAnnotation> annotations) async {
    try {
      final file = await _getAnnotationsFile(pdfPath);
      final json = {
        'pdfPath': pdfPath,
        'annotations': annotations.map((a) => a.toJson()).toList(),
        'lastModified': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(json));
      return true;
    } catch (e) {
      debugPrint('Error saving annotations: $e');
      return false;
    }
  }

  /// Load all annotations for a PDF
  Future<List<PDFAnnotation>> loadAnnotations(String pdfPath) async {
    try {
      final file = await _getAnnotationsFile(pdfPath);
      if (!await file.exists()) {
        return [];
      }

      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final annotationsJson = json['annotations'] as List;

      return annotationsJson
          .map((a) => PDFAnnotationFactory.fromJson(a as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading annotations: $e');
      return [];
    }
  }

  /// Add a single annotation
  Future<bool> addAnnotation(String pdfPath, PDFAnnotation annotation) async {
    final annotations = await loadAnnotations(pdfPath);
    annotations.add(annotation);
    return await saveAnnotations(pdfPath, annotations);
  }

  /// Remove an annotation by ID
  Future<bool> removeAnnotation(String pdfPath, String annotationId) async {
    final annotations = await loadAnnotations(pdfPath);
    annotations.removeWhere((a) => a.id == annotationId);
    return await saveAnnotations(pdfPath, annotations);
  }

  /// Update an annotation
  Future<bool> updateAnnotation(String pdfPath, PDFAnnotation annotation) async {
    final annotations = await loadAnnotations(pdfPath);
    final index = annotations.indexWhere((a) => a.id == annotation.id);
    if (index != -1) {
      annotations[index] = annotation;
      return await saveAnnotations(pdfPath, annotations);
    }
    return false;
  }

  /// Clear all annotations for a PDF
  Future<bool> clearAnnotations(String pdfPath) async {
    try {
      final file = await _getAnnotationsFile(pdfPath);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (e) {
      debugPrint('Error clearing annotations: $e');
      return false;
    }
  }

  /// Get annotations for a specific page
  Future<List<PDFAnnotation>> getAnnotationsForPage(String pdfPath, int pageIndex) async {
    final annotations = await loadAnnotations(pdfPath);
    return annotations.where((a) => a.pageIndex == pageIndex).toList();
  }
}

