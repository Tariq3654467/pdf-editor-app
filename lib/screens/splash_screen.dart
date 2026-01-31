import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Import dart:io (guarded with kIsWeb checks for web compatibility)
import 'dart:io' as io;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../painters/pdf_icon_painter.dart';
import 'tools_screen.dart';
import '../services/pdf_service.dart';
import '../services/pdf_scanner_service.dart';
import '../models/pdf_file.dart' show PDFFile, PDFFolder;
import '../services/pdf_tools_service.dart';
import '../services/pdf_preferences_service.dart';
import '../services/pdf_cache_service.dart';
import '../services/pdf_storage_service.dart';
import '../models/pdf_file.dart';
import 'pdf_viewer_screen.dart';
import 'settings_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    try {
      _animationController = AnimationController(
        duration: const Duration(seconds: 3),
        vsync: this,
      );

      _progressAnimation =
          Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);

      _animationController.forward();

      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          try {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const MyHomePage(title: 'PDF Editor'),
              ),
            );
          } catch (e) {
            print('Error navigating from splash: $e');
            // Fallback: try again after a delay
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) {
                try {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const MyHomePage(title: 'PDF Editor'),
                    ),
                  );
                } catch (e2) {
                  print('Error on retry navigation: $e2');
                }
              }
            });
          }
        }
      });
    } catch (e) {
      print('Error initializing splash screen: $e');
      // If animation fails, still try to navigate after delay
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          try {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const MyHomePage(title: 'PDF Editor'),
              ),
            );
          } catch (e2) {
            print('Error navigating after animation failure: $e2');
          }
        }
      });
    }
  }

  @override
  void dispose() {
    try {
      _animationController.dispose();
    } catch (e) {
      print('Error disposing animation controller: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : Colors.white;
    
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Top Left - Large light pink circle (partially visible)
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFE0E6).withOpacity(0.6),
              ),
            ),
          ),
          // Top - Light red curved line from top-left sweeping right
          Positioned(
            top: 50,
            left: 20,
            child: CustomPaint(
              painter: CurvedLinePainter(
                color: const Color(0xFFFFCDD2).withOpacity(0.7),
                startX: 0,
                startY: 0,
                endX: 200,
                endY: -30,
              ),
              size: const Size(300, 100),
            ),
          ),
          // Top Right - Light red rounded square outline
          Positioned(
            top: 80,
            right: 60,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFFFFCDD2).withOpacity(0.8),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // Top Right - Fainter solid light pink rounded square inside
          Positioned(
            top: 88,
            right: 68,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFFFE0E6).withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          // Top Right - Vertical column of small light red dots
          Positioned(
            top: 100,
            right: 40,
            child: Column(
              children: List.generate(
                4,
                (index) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFCDD2).withOpacity(0.7),
                  ),
                ),
              ),
            ),
          ),
          // Bottom Left - Large faint light pink circle (partially visible)
          Positioned(
            bottom: -120,
            left: -120,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFE0E6).withOpacity(0.4),
              ),
            ),
          ),
          // Bottom Right - Smaller solid light pink circle
          Positioned(
            bottom: 80,
            right: 30,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFCDD2).withOpacity(0.6),
              ),
            ),
          ),
          // Bottom - Thin light red curved line from bottom-left curving to bottom-right
          Positioned(
            bottom: 100,
            left: 0,
            child: CustomPaint(
              painter: CurvedLinePainter(
                color: const Color(0xFFFFCDD2).withOpacity(0.6),
                startX: 50,
                startY: 0,
                endX: 250,
                endY: -40,
              ),
              size: const Size(350, 100),
            ),
          ),
          // Main content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // PDF Icon with custom design
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: CustomPaint(
                    painter: PDFIconPainter(),
                  ),
                ),
                const SizedBox(height: 30),
                // App Title
                Text(
                  'PDF Reader',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.headlineMedium?.color,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 40),
                // Progress Bar - showing partial progress on the right side
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 60),
                  child: AnimatedBuilder(
                    animation: _progressAnimation,
                    builder: (context, child) {
                      // Calculate available width for progress bar
                      final screenWidth = MediaQuery.of(context).size.width;
                      final availableWidth = screenWidth - 120; // 60 padding on each side
                      // Show partial progress (about 25-30% of bar width) on the right
                      final progressWidth = availableWidth * 0.28 * _progressAnimation.value;
                      
                      return SizedBox(
                        height: 6,
                        child: Stack(
                          children: [
                            // Light grey track (full width)
                            Container(
                              width: double.infinity,
                              height: 6,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0E0E0),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            // Red progress bar aligned to the right
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                width: progressWidth,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE53935),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for curved lines
class CurvedLinePainter extends CustomPainter {
  final Color color;
  final double startX;
  final double startY;
  final double endX;
  final double endY;

  CurvedLinePainter({
    required this.color,
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(startX, startY);
    path.quadraticBezierTo(
      (startX + endX) / 2,
      (startY + endY) / 2 - 20,
      endX,
      endY,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with AutomaticKeepAliveClientMixin {
  int _selectedTabIndex = 0;
  bool _showGroupedView = false; // Toggle between grouped and flat view
  int _selectedBottomNavIndex = 0;
  final ImagePicker _imagePicker = ImagePicker();
  List<PDFFile> pdfFiles = [];
  bool _isLoading = true;
  List<Map<String, dynamic>> _toolsHistory = [];
  
  // Pagination
  static const int _itemsPerPage = 20;
  int _currentPage = 0;
  final ScrollController _scrollController = ScrollController();
  
  @override
  bool get wantKeepAlive => true; // Preserve state when navigating away

  // Feature flag: Enable automatic device-wide PDF scanning
  // Automatic scanning runs in background with timeouts to prevent ANR
  // PDFs are loaded from cache first, then refreshed in background
  static const bool _enableAutomaticDeviceScan = true;

  @override
  void initState() {
    super.initState();
    
    // Setup scroll listener for pagination
    _scrollController.addListener(_onScroll);
    
    // Delay initialization slightly to ensure widget is built
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      
      try {
        // 1) Load cached PDFs first (instant display)
        _loadCachedPDFsFirst();

        // 2) Load tools history separately (non-blocking)
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!mounted) return;
          _loadToolsHistory().catchError((e) {
            print('Error loading tools history: $e');
          });
        });
        
        // 3) Trigger automatic background scan if enabled
        if (_enableAutomaticDeviceScan) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!mounted) return;
            // Start background scan (non-blocking, with timeouts)
            _loadPDFs(forceRescan: false);
            // Also check and request storage access if needed
            _checkAndRequestAccess().catchError((e) {
              print('Error checking storage access: $e');
            });
          });
        }
      } catch (e, stackTrace) {
        print('Error in delayed init: $e');
        print('Stack trace: $stackTrace');
      }
    });
  }
  
  /// Load cached PDFs immediately without any scanning
  /// This ensures UI shows something instantly, preventing perceived crash
  Future<void> _loadCachedPDFsFirst() async {
    if (!mounted) return;
    
    try {
      final cachedPDFs = await PDFCacheService.loadPDFList()
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => <PDFFile>[],
          )
          .catchError((e) {
            print('Error loading cache: $e');
            return <PDFFile>[];
          });
      
      if (mounted) {
        setState(() {
          pdfFiles = cachedPDFs;
          // Show loading indicator if no cache and automatic scan is enabled
          _isLoading = cachedPDFs.isEmpty && _enableAutomaticDeviceScan;
        });
      }
    } catch (e, stackTrace) {
      print('Error in _loadCachedPDFsFirst: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  @override
  void dispose() {
    try {
      _scrollController.dispose();
    } catch (e) {
      print('Error disposing scroll controller: $e');
    }
    super.dispose();
  }
  
  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      // Load more items when near bottom
      _loadMoreItems();
    }
  }
  
  void _loadMoreItems() {
    if (_showGroupedView && _selectedTabIndex == 0) {
      // Paginate folders
      final folders = _getGroupedPDFs();
      final totalPages = (folders.length / _itemsPerPage).ceil();
      if (_currentPage < totalPages - 1) {
        setState(() {
          _currentPage++;
        });
      }
    } else {
      // Paginate flat list
      final filteredPDFs = _getFilteredPDFs();
      final totalPages = (filteredPDFs.length / _itemsPerPage).ceil();
      if (_currentPage < totalPages - 1) {
        setState(() {
          _currentPage++;
        });
      }
    }
  }
  
  List<PDFFile> _getPaginatedPDFs() {
    final filteredPDFs = _getFilteredPDFs();
    final endIndex = (_currentPage + 1) * _itemsPerPage;
    return filteredPDFs.take(endIndex).toList();
  }
  
  bool _hasMoreItems() {
    if (_showGroupedView && _selectedTabIndex == 0) {
      final folders = _getGroupedPDFs();
      final totalPages = (folders.length / _itemsPerPage).ceil();
      return _currentPage < totalPages - 1;
    } else {
      final filteredPDFs = _getFilteredPDFs();
      final totalPages = (filteredPDFs.length / _itemsPerPage).ceil();
      return _currentPage < totalPages - 1;
    }
  }
  
  Future<void> _checkAndRequestAccess() async {
    // Automatic device scan + permission dialog is disabled via feature flag.
    // This prevents any surprise dialogs or scans on startup which might
    // contribute to hangs/crashes on some devices. User can still trigger
    // scanning manually via the \"Retry Scan\" button.
    if (!_enableAutomaticDeviceScan) {
      return;
    }

    if (!kIsWeb && io.Platform.isAndroid) {
      // Check if dialog has already been shown
      final dialogShown = await PDFPreferencesService.hasPermissionDialogBeenShown();
      
      // Only show dialog if:
      // 1. It hasn't been shown before
      // 2. User doesn't have storage access
      // 3. No PDFs were found (first launch or no access)
      if (!dialogShown) {
        final hasAccess = await PDFService.hasStorageAccess();
        final hasManageStorage = await Permission.manageExternalStorage.isGranted;
        
        // Check if user has any form of access
        if (!hasAccess && !hasManageStorage && pdfFiles.isEmpty) {
          // Show dialog to request access on first launch
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showStorageAccessDialog();
          });
        } else {
          // User already has access, mark dialog as shown
          await PDFPreferencesService.setPermissionDialogShown(true);
        }
      }
    }
  }
  
  Future<void> _showStorageAccessDialog() async {
    if (!mounted) return;
    
    // Mark that dialog has been shown
    await PDFPreferencesService.setPermissionDialogShown(true);
    
    final shouldRequest = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Enable Automatic PDF Loading'),
        content: const Text(
          'To automatically load ALL PDFs from your device, please grant storage access.\n\n'
          '📱 For ROOT-LEVEL ACCESS (all folders):\n'
          '1. Tap "Grant Root Access" below\n'
          '2. You\'ll be taken to Settings\n'
          '3. Find this app and enable "Allow access to manage all files"\n'
          '4. Return to the app\n\n'
          '📁 Alternative (folder access):\n'
          '• Tap "Select Folder" to choose a specific folder\n'
          '• Select "Downloads" or "Documents"\n'
          '• App will scan that folder and subfolders',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: const Text('Skip'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'folder'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFE53935)),
            ),
            child: const Text('Select Folder', style: TextStyle(color: Color(0xFFE53935))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'root'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
            ),
            child: const Text('Grant Root Access', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (shouldRequest != null && shouldRequest != 'skip' && mounted) {
      if (shouldRequest == 'root') {
        // Request root-level access via MANAGE_EXTERNAL_STORAGE
        final granted = await PDFScannerService.requestStoragePermission();
        if (granted && mounted) {
          _loadPDFs(forceRescan: true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Root access granted! Scanning all folders for PDFs...'),
              duration: Duration(seconds: 3),
            ),
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enable "Allow access to manage all files" in Settings, then return to the app.'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      } else if (shouldRequest == 'folder') {
        // Request folder access via SAF
        final granted = await PDFService.requestStorageAccess();
        if (granted && mounted) {
          _loadPDFs(forceRescan: true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Folder access granted! Scanning for PDFs...'),
              duration: Duration(seconds: 3),
            ),
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('If you see "Can\'t use this folder", try selecting "Downloads" or "Documents" folder instead.'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  Future<void> _loadToolsHistory() async {
    final history = await PDFPreferencesService.getToolsHistory();
    setState(() {
      _toolsHistory = history;
    });
  }

  Future<void> _loadPDFs({bool forceRescan = false}) async {
    // CRITICAL: Add delay to ensure widget is fully mounted before scanning
    // This prevents crashes on Samsung devices during rapid initialization
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (!mounted) return; // Safety check
    
    try {
      // Load from cache first (instant) - this never blocks
      final cachedPDFs = await PDFCacheService.loadPDFList().catchError((e) {
        print('Error loading cache: $e');
        return <PDFFile>[];
      });
      
      // Update UI immediately with cached results (if any)
      if (mounted) {
        setState(() {
          pdfFiles = cachedPDFs;
          _isLoading = cachedPDFs.isEmpty || forceRescan;
        });
      }
      
      // If we have cache and not forcing rescan, return early
      if (cachedPDFs.isNotEmpty && !forceRescan) {
        // Trigger background refresh without blocking
        _scanInBackground();
        return;
      }
      
      // No cache or force rescan - scan in background (non-blocking)
      _scanInBackground();
      
    } catch (e, stackTrace) {
      print('Error in _loadPDFs: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  /// Reload PDFs after operations (split, merge, etc.)
  /// This ensures newly created files appear in the list immediately
  Future<void> _reloadPDFsAfterOperation() async {
    if (!mounted) return;
    
    try {
      // First, load from cache (should have new files)
      final cachedPDFs = await PDFCacheService.loadPDFList().catchError((e) {
        print('Error loading cache: $e');
        return <PDFFile>[];
      });
      
      // Update UI immediately with cached results
      if (mounted) {
        setState(() {
          pdfFiles = cachedPDFs;
          _isLoading = false;
        });
      }
      
      // Also scan app directory to ensure we catch any files that might not be in cache yet
      // This is a quick scan of just the app's PDF directory
      try {
        final directory = await getApplicationDocumentsDirectory();
        final pdfDirectory = io.Directory('${directory.path}/PDFs');
        
        if (await pdfDirectory.exists()) {
          final files = pdfDirectory.listSync();
          final appPDFs = <PDFFile>[];
          final seenPaths = <String>{};
          
          // Add existing cached PDFs
          for (var pdf in cachedPDFs) {
            if (pdf.filePath != null) {
              seenPaths.add(pdf.filePath!);
              appPDFs.add(pdf);
            }
          }
          
          // Scan app directory for any PDFs not in cache
          for (var file in files) {
            if (file is io.File && file.path.toLowerCase().endsWith('.pdf')) {
              if (!seenPaths.contains(file.path)) {
                try {
                  final stat = await file.stat();
                  final fileName = path.basename(file.path);
                  
                  final newPDF = PDFFile(
                    name: fileName.length > 25
                        ? '${fileName.substring(0, 22)}...'
                        : fileName,
                    date: PDFService.formatDate(stat.modified),
                    size: PDFService.formatFileSize(stat.size),
                    isFavorite: false,
                    filePath: file.path,
                    lastAccessed: DateTime.now(),
                    folderPath: pdfDirectory.path,
                    folderName: 'App Files',
                    dateModified: stat.modified,
                    fileSizeBytes: stat.size,
                  );
                  
                  appPDFs.add(newPDF);
                  // Add to cache
                  await PDFCacheService.addPDFToCache(newPDF);
                } catch (e) {
                  print('Error processing file ${file.path}: $e');
                }
              }
            }
          }
          
          // Sort by date (newest first)
          appPDFs.sort((a, b) {
            final aDate = a.dateModified ?? DateTime(1970);
            final bDate = b.dateModified ?? DateTime(1970);
            return bDate.compareTo(aDate);
          });
          
          // Update UI with all PDFs
          if (mounted) {
            setState(() {
              pdfFiles = appPDFs;
              _isLoading = false;
            });
          }
        }
      } catch (e) {
        print('Error scanning app directory: $e');
      }
    } catch (e, stackTrace) {
      print('Error in _reloadPDFsAfterOperation: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  /// Scan PDFs in background without blocking UI thread
  /// This is critical for preventing ANR on Samsung devices
  void _scanInBackground() {
    // Use Future.microtask to ensure this runs after current frame
    Future.microtask(() async {
      try {
        // Scan in background - this should never block
        final scannedPDFs = await PDFScannerService.scanAllPDFsInBackground()
            .timeout(
              const Duration(seconds: 120), // Max 2 minutes
              onTimeout: () {
                print('PDF scan timeout - returning empty list');
                return <PDFFile>[];
              },
            )
            .catchError((e, stackTrace) {
              print('Error in background scan: $e');
              print('Stack trace: $stackTrace');
              return <PDFFile>[];
            });
        
        // Update UI only if widget is still mounted
        if (mounted) {
          setState(() {
            pdfFiles = scannedPDFs;
            _isLoading = false;
          });
          
          // Reload history after scan completes
          _loadToolsHistory().catchError((e) {
            print('Error loading tools history: $e');
          });
        }
      } catch (e, stackTrace) {
        print('Unexpected error in _scanInBackground: $e');
        print('Stack trace: $stackTrace');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    });
  }

  List<PDFFile> _getFilteredPDFs() {
    switch (_selectedTabIndex) {
      case 0: // My file - show all
        return pdfFiles;
      case 1: // Recent - show files sorted by last accessed
        final recentFiles = pdfFiles.where((pdf) => pdf.lastAccessed != null).toList();
        recentFiles.sort((a, b) {
          if (a.lastAccessed == null) return 1;
          if (b.lastAccessed == null) return -1;
          return b.lastAccessed!.compareTo(a.lastAccessed!);
        });
        return recentFiles;
      case 2: // Bookmarks - show only bookmarked files
        return pdfFiles.where((pdf) => pdf.isFavorite).toList();
      default:
        return pdfFiles;
    }
  }
  
  // Get PDFs grouped by folder
  List<PDFFolder> _getGroupedPDFs() {
    final filtered = _getFilteredPDFs();
    return PDFScannerService.groupPDFsByFolder(filtered);
  }

  Future<void> _pickAndAddPDF() async {
    if (kIsWeb) {
      // Web doesn't support file system access
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File picking not supported on web')),
      );
      return;
    }
    
    final filePath = await PDFService.pickPDFFile();
    if (filePath != null) {
      try {
        // Create PDFFile object from the newly added file
        final file = io.File(filePath);
        if (await file.exists()) {
          final stat = await file.stat();
          final fileName = path.basename(filePath);
          final displayName = fileName.length > 25
              ? '${fileName.substring(0, 22)}...'
              : fileName;
          
          // Get bookmarks and recent access
          final bookmarks = await PDFPreferencesService.getBookmarks();
          final isBookmarked = bookmarks.contains(filePath);
          
          final newPDF = PDFFile(
            name: displayName,
            date: PDFService.formatDate(stat.modified),
            size: PDFService.formatFileSize(stat.size),
            isFavorite: isBookmarked,
            filePath: filePath,
            lastAccessed: null,
            folderPath: file.parent.path,
            folderName: 'App Files',
            dateModified: stat.modified,
            fileSizeBytes: stat.size,
          );
          
          // Mark as recently accessed
          await PDFPreferencesService.setLastAccessed(filePath);
          
          // Update PDF with last accessed time
          final pdfWithRecent = PDFFile(
            name: newPDF.name,
            date: newPDF.date,
            size: newPDF.size,
            isFavorite: newPDF.isFavorite,
            filePath: newPDF.filePath,
            lastAccessed: DateTime.now(),
            folderPath: newPDF.folderPath,
            folderName: newPDF.folderName,
            dateModified: newPDF.dateModified,
            fileSizeBytes: newPDF.fileSizeBytes,
          );
          
          // Add to cache immediately
          await PDFCacheService.addPDFToCache(pdfWithRecent);
          
          // Update local list
          setState(() {
            // Check if PDF already exists in list
            final existingIndex = pdfFiles.indexWhere((p) => p.filePath == filePath);
            if (existingIndex >= 0) {
              // Update existing
              pdfFiles[existingIndex] = pdfWithRecent;
            } else {
              // Add new
              pdfFiles.insert(0, pdfWithRecent);
            }
            // Sort by date (newest first)
            pdfFiles.sort((a, b) {
              final aDate = a.dateModified ?? DateTime(1970);
              final bDate = b.dateModified ?? DateTime(1970);
              return bDate.compareTo(aDate);
            });
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF added successfully'),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          // File doesn't exist, force rescan to pick it up
          await _loadPDFs(forceRescan: true);
        }
      } catch (e) {
        print('Error adding PDF to cache: $e');
        // Fallback: force rescan of app directory only
        await _loadPDFs(forceRescan: true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF added successfully'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _openCamera() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      
      if (photo != null) {
        // Show loading indicator
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Convert image to PDF
        final pdfPath = await PDFToolsService.scanToPDF(photo.path);
        
        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          
          if (pdfPath != null) {
            // Open PDF in viewer
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => PDFViewerScreen(
                  filePath: pdfPath,
                  fileName: 'Scanned Document.pdf',
                ),
              ),
            );
            // Reload PDF list (from cache, no rescan)
            _loadPDFs(forceRescan: false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('PDF created successfully'),
                duration: Duration(seconds: 2),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error creating PDF from image'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog if open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: ${e.toString()}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      print('Error opening camera: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    // Handle back button to preserve state - use AutomaticKeepAliveClientMixin pattern
    // PHASE 3 FIX: Cache-first strategy - do NOT reload on every back navigation
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async {
        if (didPop) {
          // PHASE 3: Only refresh cache in background, don't reload UI
          // State is preserved by AutomaticKeepAliveClientMixin
          if (mounted) {
            // Background refresh only - no UI flicker
            Future.microtask(() async {
              if (mounted) {
                // Silently refresh cache in background without UI update
                try {
                  final cachedPDFs = await PDFCacheService.loadPDFList();
                  // Only update if cache has more files than current list
                  if (mounted && cachedPDFs.length > pdfFiles.length) {
                    setState(() {
                      pdfFiles = cachedPDFs;
                    });
                  }
                  // Trigger background scan if cache is old (> 1 minute)
                  final cacheTimestamp = await PDFCacheService.getCacheTimestamp();
                  if (cacheTimestamp != null) {
                    final age = DateTime.now().difference(cacheTimestamp);
                    if (age.inMinutes > 1) {
                      // Background scan - don't await, don't update UI
                      PDFScannerService.scanAllPDFsInBackground().then((newPDFs) {
                        if (mounted && newPDFs.isNotEmpty) {
                          // Only update if we got new files
                          setState(() {
                            pdfFiles = newPDFs;
                          });
                        }
                      }).catchError((e) {
                        print('Background scan error: $e');
                      });
                    }
                  }
                } catch (e) {
                  print('Error refreshing cache on back navigation: $e');
                  // Don't reload - preserve current state
                }
              }
            });
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFE53935),
        body: Column(
        children: [
          // Red Header with rounded bottom corners
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFE53935),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top,
              left: 20,
              right: 20,
              bottom: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and Icons Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedBottomNavIndex == 0 ? 'PDF Reader' : 'Tools',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.star, color: Color(0xFFFFD700)),
                          tooltip: 'Premium',
                        ),
                        IconButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const SettingsScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.settings, color: Colors.white),
                          tooltip: 'Settings',
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Content with rounded top corners
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: _selectedBottomNavIndex == 0
                  ? _buildHomeContent()
                  : ToolsScreen(
                      onOperationComplete: () {
                        // Force refresh of PDF list to show newly created files
                        // Use special reload function that scans app directory
                        _reloadPDFsAfterOperation();
                        _loadToolsHistory();
                      },
                    ),
            ),
          ),
        ],
        ),
        // Bottom Navigation
        bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.1,
              ),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomAppBar(
          color: Theme.of(context).scaffoldBackgroundColor,
          shape: const CircularNotchedRectangle(),
          notchMargin: 8.0,
          child: SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Home
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() => _selectedBottomNavIndex = 0);
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.home,
                            color: _selectedBottomNavIndex == 0
                                ? const Color(0xFFE53935) // Reddish-pink when active
                                : Theme.of(context).iconTheme.color?.withOpacity(0.6) ?? Colors.grey,
                            size: 24,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Home',
                            style: TextStyle(
                              color: _selectedBottomNavIndex == 0
                                  ? const Color(0xFFE53935) // Reddish-pink when active
                                  : Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6) ?? Colors.grey,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Tools
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() => _selectedBottomNavIndex = 1);
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildToolsIcon(
                            isActive: _selectedBottomNavIndex == 1,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tools',
                            style: TextStyle(
                              color: _selectedBottomNavIndex == 1
                                  ? const Color(0xFFE53935)
                                  : Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6) ?? Colors.grey,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFE53935), // Red circular button
        shape: const CircleBorder(),
        elevation: 4,
        onPressed: _openCamera,
        child: const Icon(
          Icons.crop_free, // Scanner icon - square with four corner squares (focus frame)
          color: Colors.white, // White icon on red background
          size: 28,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      ),
    );
  }

  Widget _buildToolsIcon({required bool isActive}) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDarkMode 
        ? (Colors.grey[400] ?? Colors.grey) 
        : const Color(0xFFBDBDBD);
    final color = isActive ? const Color(0xFFE53935) : inactiveColor;
    final plusColor = isActive ? const Color(0xFFE53935) : inactiveColor;
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        children: [
          // Grid of 4 squares
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 1.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 1.5),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Center(
                child: Icon(
                  Icons.add,
                  size: 8,
                  color: plusColor,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 1.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 1.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isActive = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedTabIndex = index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFFFCDD2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive
                ? const Color(0xFFE53935)
                : Theme.of(context).textTheme.bodyMedium?.color,
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
        // Tabs
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
          child: Row(
            children: [
              _buildTab('My file', 0),
              const SizedBox(width: 20),
              _buildTab('Recent', 1),
              const SizedBox(width: 20),
              _buildTab('Bookmarks', 2),
            ],
          ),
        ),
        // Document Count and Actions
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '${_getFilteredPDFs().length} ${_getFilteredPDFs().length == 1 ? 'Document' : 'Documents'}',
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Theme.of(context).textTheme.titleLarge?.color ?? Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_selectedTabIndex == 0)
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _showGroupedView = !_showGroupedView;
                          _currentPage = 0; // Reset pagination when switching views
                        });
                      },
                      icon: Icon(
                        _showGroupedView ? Icons.list : Icons.folder,
                        color: const Color(0xFF757575),
                      ),
                      tooltip: _showGroupedView ? 'Show List' : 'Group by Folder',
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                  IconButton(
                    onPressed: () {
                      // Search functionality
                    },
                    icon: const Icon(Icons.search,
                        color: Color(0xFF757575)),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                  IconButton(
                    onPressed: () {
                      // Filter/Sort functionality
                    },
                    icon: const Icon(Icons.tune,
                        color: Color(0xFF757575)),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                  IconButton(
                    onPressed: _pickAndAddPDF,
                    icon: const Icon(Icons.add,
                        color: Color(0xFF757575)),
                    tooltip: 'Add PDF',
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
        // PDF List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildPDFList(),
        ),
      ],
      ),
    );
  }

  Widget _buildPDFList() {
    // Handle grouped view
    if (_showGroupedView && _selectedTabIndex == 0) {
      return _buildGroupedPDFListView();
    }
    
    final filteredPDFs = _getFilteredPDFs();
    
    if (filteredPDFs.isEmpty) {
      // CRITICAL: Wrap empty state in RepaintBoundary and error boundary
      // This prevents crashes when rendering empty state on Samsung devices
      return RepaintBoundary(
        child: Builder(
          builder: (context) {
            try {
              String emptyMessage;
              String emptyTitle;
              
              switch (_selectedTabIndex) {
                case 1:
                  emptyTitle = 'No Recent Files';
                  emptyMessage = 'Files you open will appear here';
                  break;
                case 2:
                  emptyTitle = 'No Bookmarks';
                  emptyMessage = 'Tap the star icon to bookmark a file';
                  break;
                default:
                  emptyTitle = 'No PDFs found';
                  emptyMessage = 'PDFs on your device couldn\'t be automatically loaded.\n\nThis may be due to Android storage restrictions.\n\nTap "Add PDF" to manually select PDF files.';
              }
              
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        size: 64,
                        color: Color(0xFFBDBDBD),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        emptyTitle,
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black54,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        emptyMessage,
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white60
                              : Theme.of(context).textTheme.bodySmall?.color ?? Colors.black45,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_selectedTabIndex == 0) ...[
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            try {
                              _pickAndAddPDF();
                            } catch (e) {
                              print('Error in _pickAndAddPDF: $e');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE53935),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          icon: const Icon(Icons.add, color: Colors.white),
                          label: Text(
                            (kIsWeb || io.Platform.isIOS) ? 'Import PDF' : 'Add PDF',
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                        if (!kIsWeb && !io.Platform.isIOS) ...[
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () {
                              try {
                                _scanInBackground();
                              } catch (e) {
                                print('Error in retry scan: $e');
                              }
                            },
                            child: const Text(
                              'Retry Scan',
                              style: TextStyle(color: Color(0xFFE53935)),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              );
            } catch (e, stackTrace) {
              // Fallback UI if empty state rendering fails
              print('Error rendering empty state: $e');
              print('Stack trace: $stackTrace');
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    'No PDFs found. Tap "Add PDF" to import files.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white60
                          : const Color(0xFF9E9E9E),
                    ),
                  ),
                ),
              );
            }
          },
        ),
      );
    }
    
    final paginatedPDFs = _getPaginatedPDFs();
    
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      children: [
        // Tools History Section (only on "My file" tab)
        if (_selectedTabIndex == 0 && _toolsHistory.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).dividerColor.withOpacity(0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Tools Activity',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Theme.of(context).textTheme.titleMedium?.color ?? Colors.black87,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await PDFPreferencesService.clearToolsHistory();
                        await _loadToolsHistory();
                      },
                      child: const Text(
                        'Clear',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._toolsHistory.take(5).map((item) => _buildHistoryItem(item)),
              ],
            ),
          ),
        // PDF List (vertical list matching reference design)
        ...paginatedPDFs.map((pdf) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildPDFListCard(pdf),
        )),
        // Load more indicator
        if (_hasMoreItems())
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final operation = item['operation'] as String? ?? 'Unknown';
    final timestamp = item['timestamp'] as String?;
    DateTime? dateTime;
    if (timestamp != null) {
      try {
        dateTime = DateTime.parse(timestamp);
      } catch (e) {
        dateTime = null;
      }
    }
    
    String operationName = operation;
    IconData operationIcon = Icons.build;
    
    switch (operation.toLowerCase()) {
      case 'merge':
        operationName = 'Merged PDFs';
        operationIcon = Icons.merge;
        break;
      case 'split':
        operationName = 'Split PDF';
        operationIcon = Icons.content_cut;
        break;
      case 'compress':
        operationName = 'Compressed PDF';
        operationIcon = Icons.compress;
        break;
      case 'zip':
        operationName = 'Created ZIP';
        operationIcon = Icons.archive;
        break;
      case 'scan':
        operationName = 'Scanned to PDF';
        operationIcon = Icons.document_scanner;
        break;
      default:
        operationName = operation;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(operationIcon, size: 16, color: const Color(0xFF9E9E9E)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              operationName,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black87,
              ),
            ),
          ),
          if (dateTime != null)
            Text(
              _formatHistoryTime(dateTime),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : Theme.of(context).textTheme.bodySmall?.color ?? Colors.black54,
              ),
            ),
        ],
      ),
    );
  }

  String _formatHistoryTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  Widget _buildGroupedPDFListView() {
    final folders = _getGroupedPDFs();
    if (folders.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.folder_outlined,
                size: 64,
                color: Color(0xFFBDBDBD),
              ),
              const SizedBox(height: 16),
              Text(
                'No PDFs found',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black54,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    // Paginate folders
    final endIndex = (_currentPage + 1) * _itemsPerPage;
    final paginatedFolders = folders.take(endIndex).toList();
    final hasMore = folders.length > endIndex;
    
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      children: [
        ...paginatedFolders.map((folder) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).dividerColor.withOpacity(0.5),
              ),
            ),
            child: ExpansionTile(
              leading: const Icon(Icons.folder, color: Color(0xFFE53935)),
              title: Text(
                folder.folderName,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Theme.of(context).textTheme.titleLarge?.color ?? Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '${folder.count} ${folder.count == 1 ? 'file' : 'files'} • ${folder.formattedSize}',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : Theme.of(context).textTheme.bodySmall?.color ?? Colors.black54,
                  fontSize: 12,
                ),
              ),
              children: folder.pdfs.map((pdf) {
                return Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                  child: _buildPDFListCard(pdf),
                );
              }).toList(),
            ),
          );
        }).toList(),
        if (hasMore)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
              ),
            ),
          ),
      ],
    );
  }
  
  List<Widget> _buildGroupedPDFList() {
    final folders = _getGroupedPDFs();
    if (folders.isEmpty) {
      return [];
    }
    
    return folders.map((folder) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.5),
          ),
        ),
        child: ExpansionTile(
          leading: const Icon(Icons.folder, color: Color(0xFFE53935)),
          title: Text(
            folder.folderName,
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Theme.of(context).textTheme.titleLarge?.color ?? Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '${folder.count} ${folder.count == 1 ? 'file' : 'files'} • ${folder.formattedSize}',
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white70
                  : Theme.of(context).textTheme.bodySmall?.color ?? Colors.black54,
              fontSize: 12,
            ),
          ),
          children: folder.pdfs.map((pdf) {
            return Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: _buildPDFTile(pdf, isNested: true),
            );
          }).toList(),
        ),
      );
    }).toList();
  }

  Widget _buildPDFListCard(PDFFile pdf) {
    return GestureDetector(
      onTap: () async {
        if (pdf.filePath != null) {
          // Ensure PDF is in app storage (copy if external)
          final filePath = await PDFStorageService.ensureInAppStorage(pdf.filePath!);
          
          // Track that this PDF was accessed
          await PDFPreferencesService.setLastAccessed(filePath);
          
          // Navigate to PDF viewer
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PDFViewerScreen(
                filePath: filePath,
                fileName: pdf.name,
              ),
            ),
          );
          
          // Reload PDFs when returning from PDF viewer
          if (mounted) {
            await Future.delayed(const Duration(milliseconds: 500));
            await _reloadPDFsAfterOperation();
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF file path not available'),
            ),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'PDF',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          title: Text(
            pdf.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF263238),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${pdf.date} • ${pdf.size}',
              style: const TextStyle(
                color: Color(0xFF9E9E9E),
                fontSize: 12,
              ),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () async {
                  final newBookmarkStatus = !pdf.isFavorite;
                  
                  if (pdf.filePath != null) {
                    await PDFPreferencesService.setBookmark(
                      pdf.filePath!,
                      newBookmarkStatus,
                    );
                  }
                  
                  setState(() {
                    final index = pdfFiles.indexWhere((p) => p.filePath == pdf.filePath);
                    if (index != -1) {
                      pdfFiles[index].isFavorite = newBookmarkStatus;
                      PDFCacheService.updatePDFInCache(pdfFiles[index]);
                    }
                  });
                },
                icon: Icon(
                  pdf.isFavorite ? Icons.star : Icons.star_outline,
                  color: const Color(0xFFE53935),
                  size: 22,
                ),
              ),
              IconButton(
                onPressed: () => _showPDFOptionsMenu(context, pdf),
                icon: Icon(
                  Icons.more_vert,
                  color: const Color(0xFF9E9E9E),
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPDFGridCard(PDFFile pdf) {
    return GestureDetector(
      onTap: () async {
        if (pdf.filePath != null) {
          // Ensure PDF is in app storage (copy if external)
          final filePath = await PDFStorageService.ensureInAppStorage(pdf.filePath!);
          
          // Track that this PDF was accessed
          await PDFPreferencesService.setLastAccessed(filePath);
          
          // Navigate to PDF viewer
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PDFViewerScreen(
                filePath: filePath,
                fileName: pdf.name,
              ),
            ),
          );
          
          // Reload PDFs when returning from PDF viewer
          if (mounted) {
            await Future.delayed(const Duration(milliseconds: 500));
            await _reloadPDFsAfterOperation();
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF file path not available'),
            ),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          // Cards stay white even in dark mode to match reference design
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top section: Red PDF preview area (≈60%)
            Expanded(
              flex: 3, // 60% of card height
              child: Stack(
                children: [
                  // Red PDF Icon Container
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE53935),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'PDF',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  // Favorite/Star button (top right corner)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () async {
                        final newBookmarkStatus = !pdf.isFavorite;
                        
                        if (pdf.filePath != null) {
                          await PDFPreferencesService.setBookmark(
                            pdf.filePath!,
                            newBookmarkStatus,
                          );
                        }
                        
                        setState(() {
                          final index = pdfFiles.indexWhere((p) => p.filePath == pdf.filePath);
                          if (index != -1) {
                            pdfFiles[index].isFavorite = newBookmarkStatus;
                            PDFCacheService.updatePDFInCache(pdfFiles[index]);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Icon(
                          pdf.isFavorite ? Icons.star : Icons.star_outline,
                          color: const Color(0xFFE53935),
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  // Options menu button (top left corner)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: GestureDetector(
                      onTap: () => _showPDFOptionsMenu(context, pdf),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.more_vert,
                          color: const Color(0xFFE53935),
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom section: White background with file info (≈40%)
            Expanded(
              flex: 2, // 40% of card height
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // PDF filename (1-2 lines max)
                    Flexible(
                      child: Text(
                        pdf.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF263238),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Date • file size and options menu button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            '${pdf.date} • ${pdf.size}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF9E9E9E),
                              fontSize: 11,
                              height: 1.2,
                            ),
                          ),
                        ),
                        // Options menu button
                        GestureDetector(
                          onTap: () => _showPDFOptionsMenu(context, pdf),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.more_vert,
                              color: const Color(0xFF9E9E9E),
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPDFTile(PDFFile pdf, {bool isNested = false}) {
    return GestureDetector(
      onTap: () async {
        if (pdf.filePath != null) {
          // Ensure PDF is in app storage (copy if external)
          final filePath = await PDFStorageService.ensureInAppStorage(pdf.filePath!);
          
          // Track that this PDF was accessed
          await PDFPreferencesService.setLastAccessed(filePath);
          
          // Navigate to PDF viewer
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PDFViewerScreen(
                filePath: filePath,
                fileName: pdf.name,
              ),
            ),
          );
          
          // Reload PDFs when returning from PDF viewer
          // This ensures newly created files (split, merge, etc.) appear in the list
          if (mounted) {
            // Small delay to ensure cache is fully updated
            await Future.delayed(const Duration(milliseconds: 500));
            // Force reload from cache to get newly added files
            // Also scan app directory to ensure new files are found
            await _reloadPDFsAfterOperation();
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF file path not available'),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white, // Keep cards white for better visibility
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(12),
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'PDF',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          title: Text(
            pdf.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF263238), // Dark text for visibility on white cards
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            isNested 
                ? '${pdf.date} • ${pdf.size}'
                : '${pdf.folderName ?? "Unknown"} • ${pdf.date} • ${pdf.size}',
            style: const TextStyle(
              color: Color(0xFF9E9E9E), // Grey text for metadata on white cards
              fontSize: 12,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () async {
                  final newBookmarkStatus = !pdf.isFavorite;
                  
                  if (pdf.filePath != null) {
                    await PDFPreferencesService.setBookmark(
                      pdf.filePath!,
                      newBookmarkStatus,
                    );
                  }
                  
                  setState(() {
                    final index = pdfFiles.indexWhere((p) => p.filePath == pdf.filePath);
                    if (index != -1) {
                      pdfFiles[index].isFavorite = newBookmarkStatus;
                      // Update cache with new bookmark status
                      PDFCacheService.updatePDFInCache(pdfFiles[index]);
                    }
                  });
                },
                icon: Icon(
                  pdf.isFavorite ? Icons.star : Icons.star_outline,
                  color: const Color(0xFFE53935),
                  size: 20,
                ),
              ),
              IconButton(
                onPressed: () => _showPDFOptionsMenu(context, pdf),
                icon: Icon(
                  Icons.more_vert,
                  color: Theme.of(context).iconTheme.color?.withOpacity(0.7) ?? Colors.grey,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPDFOptionsMenu(BuildContext context, PDFFile pdf) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).bottomSheetTheme.backgroundColor ?? 
                 Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (pdf.filePath != null) ...[
              ListTile(
                leading: Icon(
                  Icons.drive_file_rename_outline,
                  color: Theme.of(context).iconTheme.color,
                ),
                title: Text(
                  'Rename',
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    fontSize: 16,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _renamePDF(pdf);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.share,
                  color: Theme.of(context).iconTheme.color,
                ),
                title: Text(
                  'Share',
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    fontSize: 16,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _sharePDF(pdf);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red, fontSize: 16),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deletePDF(pdf);
                },
              ),
            ],
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Future<void> _sharePDF(PDFFile pdf) async {
    try {
      if (pdf.filePath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'PDF file path not available',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
                ),
              ),
              backgroundColor: Theme.of(context).snackBarTheme.backgroundColor ?? 
                               (Theme.of(context).brightness == Brightness.dark 
                                   ? Colors.grey[800] 
                                   : Colors.grey[300]),
            ),
          );
        }
        return;
      }

      if (kIsWeb) {
        // On web, share without file existence check
        await Share.share(pdf.filePath!, subject: pdf.name);
        return;
      }
      
      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
            ),
          ),
        );
      }
      
      // Ensure PDF is in app storage (copy if external or content URI)
      final filePath = await PDFStorageService.ensureInAppStorage(pdf.filePath!);
      final file = io.File(filePath);
      
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
      }
      
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(filePath)],
          text: 'Check out this PDF: ${pdf.name}',
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'PDF file not found or cannot be accessed',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
                ),
              ),
              backgroundColor: Theme.of(context).snackBarTheme.backgroundColor ?? 
                               (Theme.of(context).brightness == Brightness.dark 
                                   ? Colors.grey[800] 
                                   : Colors.grey[300]),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        // Close loading dialog if still open
        try {
          Navigator.pop(context);
        } catch (_) {}
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error sharing PDF: $e',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
              ),
            ),
            backgroundColor: Theme.of(context).snackBarTheme.backgroundColor ?? 
                             (Theme.of(context).brightness == Brightness.dark 
                                 ? Colors.grey[800] 
                                 : Colors.grey[300]),
          ),
        );
      }
    }
  }

  void _deletePDF(PDFFile pdf) async {
    if (pdf.filePath == null) return;

    // Ensure PDF is in app storage first to get the actual file path
    String? actualFilePath;
    try {
      actualFilePath = await PDFStorageService.ensureInAppStorage(pdf.filePath!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error accessing PDF file: $e',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
              ),
            ),
            backgroundColor: Theme.of(context).snackBarTheme.backgroundColor ?? 
                             (Theme.of(context).brightness == Brightness.dark 
                                 ? Colors.grey[800] 
                                 : Colors.grey[300]),
          ),
        );
      }
      return;
    }

    if (actualFilePath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'PDF file not found',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
              ),
            ),
            backgroundColor: Theme.of(context).snackBarTheme.backgroundColor ?? 
                             (Theme.of(context).brightness == Brightness.dark 
                                 ? Colors.grey[800] 
                                 : Colors.grey[300]),
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).dialogBackgroundColor,
        title: Text(
          'Delete PDF',
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color ?? Colors.black87,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${pdf.name}"?',
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              try {
                final file = io.File(actualFilePath!);
                if (await file.exists()) {
                  await file.delete();
                  // Remove from cache
                  await PDFCacheService.removePDFFromCache(pdf.filePath!);
                  // Remove from bookmarks
                  await PDFPreferencesService.setBookmark(pdf.filePath!, false);
                  // Remove from recent access
                  final recentAccess = await PDFPreferencesService.getRecentAccess();
                  recentAccess.remove(pdf.filePath!);
                  // Reload PDFs to refresh UI
                  await _loadPDFs();
                } else {
                  // File doesn't exist, but remove from cache anyway
                  await PDFCacheService.removePDFFromCache(pdf.filePath!);
                  await PDFPreferencesService.setBookmark(pdf.filePath!, false);
                  await _loadPDFs();
                }
                if (mounted) {
                  Navigator.pop(context); // Close dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'PDF deleted successfully',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
                        ),
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Error deleting PDF: $e',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
                        ),
                      ),
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _renamePDF(PDFFile pdf) async {
    if (pdf.filePath == null) return;

    // Show loading indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
          ),
        ),
      );
    }

    // Ensure PDF is in app storage first to get the actual file path
    String? actualFilePath;
    try {
      actualFilePath = await PDFStorageService.ensureInAppStorage(pdf.filePath!);
      
      // Verify the file exists
      if (actualFilePath != null) {
        final file = io.File(actualFilePath);
        if (!await file.exists()) {
          actualFilePath = null;
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error accessing PDF file: $e',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
              ),
            ),
            backgroundColor: Theme.of(context).snackBarTheme.backgroundColor ?? 
                             (Theme.of(context).brightness == Brightness.dark 
                                 ? Colors.grey[800] 
                                 : Colors.grey[300]),
          ),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.pop(context); // Close loading dialog
    }

    if (actualFilePath == null || actualFilePath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'PDF file not found or cannot be accessed',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
              ),
            ),
            backgroundColor: Theme.of(context).snackBarTheme.backgroundColor ?? 
                             (Theme.of(context).brightness == Brightness.dark 
                                 ? Colors.grey[800] 
                                 : Colors.grey[300]),
          ),
        );
      }
      return;
    }

    final nameController = TextEditingController(
      text: path.basenameWithoutExtension(actualFilePath),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).dialogBackgroundColor,
        title: Text(
          'Rename PDF',
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color ?? Colors.black87,
          ),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: 'Enter new name',
            hintStyle: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
            ),
            border: const OutlineInputBorder(),
            suffixText: '.pdf',
            suffixStyle: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
            ),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              
              if (newName.isEmpty) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Please enter a valid name',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
                        ),
                      ),
                      backgroundColor: Theme.of(context).snackBarTheme.backgroundColor ?? 
                                       (Theme.of(context).brightness == Brightness.dark 
                                           ? Colors.grey[800] 
                                           : Colors.grey[300]),
                    ),
                  );
                }
                return;
              }

              // Validate name (no invalid characters)
              if (newName.contains(RegExp(r'[<>:"/\\|?*]'))) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Name contains invalid characters',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
                        ),
                      ),
                      backgroundColor: Theme.of(context).snackBarTheme.backgroundColor ?? 
                                       (Theme.of(context).brightness == Brightness.dark 
                                           ? Colors.grey[800] 
                                           : Colors.grey[300]),
                    ),
                  );
                }
                return;
              }

              try {
                // Use the actual file path (already ensured to be in app storage)
                final oldFile = io.File(actualFilePath);
                
                if (!await oldFile.exists()) {
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'PDF file not found',
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
                          ),
                        ),
                        backgroundColor: Theme.of(context).snackBarTheme.backgroundColor ?? 
                                         (Theme.of(context).brightness == Brightness.dark 
                                             ? Colors.grey[800] 
                                             : Colors.grey[300]),
                      ),
                    );
                  }
                  return;
                }

                // Get directory and create new path
                final directory = path.dirname(actualFilePath);
                final newFileName = '$newName.pdf';
                final newPath = path.join(directory, newFileName);

                // Check if file with new name already exists
                final targetFile = io.File(newPath);
                if (await targetFile.exists() && newPath != actualFilePath) {
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'A file with this name already exists',
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
                          ),
                        ),
                        backgroundColor: Theme.of(context).snackBarTheme.backgroundColor ?? 
                                         (Theme.of(context).brightness == Brightness.dark 
                                             ? Colors.grey[800] 
                                             : Colors.grey[300]),
                      ),
                    );
                  }
                  return;
                }

                // Rename the file
                await oldFile.rename(newPath);

                // Update cache: Remove old entry and add new one
                await PDFCacheService.removePDFFromCache(pdf.filePath!);
                
                // Create new PDFFile object with updated path
                final renamedFile = io.File(newPath);
                final stat = await renamedFile.stat();
                final updatedPDF = PDFFile(
                  name: path.basename(newPath),
                  date: PDFService.formatDate(stat.modified),
                  size: PDFService.formatFileSize(stat.size),
                  isFavorite: pdf.isFavorite,
                  filePath: newPath,
                  lastAccessed: pdf.lastAccessed,
                  folderPath: path.dirname(newPath),
                  folderName: pdf.folderName,
                  dateModified: stat.modified,
                  fileSizeBytes: stat.size,
                );
                
                // Add renamed file to cache
                await PDFCacheService.addPDFToCache(updatedPDF);

                // Update bookmark if file was bookmarked
                final wasBookmarked = await PDFPreferencesService.isBookmarked(pdf.filePath!);
                if (wasBookmarked) {
                  await PDFPreferencesService.setBookmark(pdf.filePath!, false);
                  await PDFPreferencesService.setBookmark(newPath, true);
                }

                // Update recent access
                final recentAccess = await PDFPreferencesService.getRecentAccess();
                if (recentAccess.containsKey(pdf.filePath!)) {
                  final lastAccessed = recentAccess[pdf.filePath!];
                  recentAccess.remove(pdf.filePath!);
                  if (lastAccessed != null) {
                    await PDFPreferencesService.setLastAccessed(newPath);
                  }
                }

                // Reload PDFs to refresh UI
                await _loadPDFs();

                if (mounted) {
                  Navigator.pop(context); // Close dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'PDF renamed successfully',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
                        ),
                      ),
                      backgroundColor: Theme.of(context).snackBarTheme.backgroundColor ?? 
                                       (Theme.of(context).brightness == Brightness.dark 
                                           ? Colors.grey[800] 
                                           : Colors.grey[300]),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Error renaming PDF: $e',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
                        ),
                      ),
                      backgroundColor: Theme.of(context).snackBarTheme.backgroundColor ?? 
                                       (Theme.of(context).brightness == Brightness.dark 
                                           ? Colors.grey[800] 
                                           : Colors.grey[300]),
                    ),
                  );
                }
              }
            },
            child: Text(
              'Rename',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
