import 'package:flutter/material.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import '../painters/pdf_icon_painter.dart';
import 'tools_screen.dart';

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
    _animationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    _progressAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);

    _animationController.forward();

    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const MyHomePage(title: 'PDF Editor'),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
                const Text(
                  'PDF Reader',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF263238),
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

class _MyHomePageState extends State<MyHomePage> {
  int _selectedTabIndex = 0;
  int _selectedBottomNavIndex = 0;
  final ImagePicker _imagePicker = ImagePicker();

  // Sample PDF files data
  final List<PDFFile> pdfFiles = [
    PDFFile(
      name: 'CS106-F25-01-Sectio...',
      date: '01/10/2026 21:34',
      size: '155.5 KB',
      isFavorite: false,
    ),
    PDFFile(
      name: 'CS250-F25-01-Sectio...',
      date: '01/10/2026 16:47',
      size: '278.5 KB',
      isFavorite: false,
    ),
    PDFFile(
      name: 'PDF_Merged_202601...',
      date: '01/10/2026 16:45',
      size: '439.6 KB',
      isFavorite: false,
    ),
    PDFFile(
      name: 'Crypto Arbitrage Bot ...',
      date: '01/10/2026 16:42',
      size: '335.2 KB',
      isFavorite: false,
    ),
    PDFFile(
      name: 'CS106-F25-01-Sectio...',
      date: '01/10/2026 16:10',
      size: '153.6 KB',
      isFavorite: false,
    ),
    PDFFile(
      name: 'combination and per...',
      date: '01/06/2026 07:31',
      size: '255.7 KB',
      isFavorite: false,
    ),
  ];

  Future<void> _openCamera() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      
      if (photo != null) {
        print('Photo captured: ${photo.path}');
        // You can process the captured image here
        // Convert to PDF or save it
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo captured: ${photo.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error opening camera: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Camera not available on web. Use Android/iOS app'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          // Red Header
          Container(
            color: const Color(0xFFE53935),
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
                          onPressed: () {},
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
          // Content
          Expanded(
            child: Container(
              color: const Color(0xFFF5F5F5),
              child: _selectedBottomNavIndex == 0
                  ? _buildHomeContent()
                  : const ToolsScreen(),
            ),
          ),
        ],
      ),
      // Bottom Navigation
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomAppBar(
          color: Colors.white,
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
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.home,
                              color: Color(0xFFE53935), size: 24),
                          SizedBox(height: 2),
                          Text(
                            'Home',
                            style: TextStyle(
                              color: Color(0xFFE53935),
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
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.dashboard,
                              color: Color(0xFFBDBDBD), size: 24),
                          SizedBox(height: 2),
                          Text(
                            'Tools',
                            style: TextStyle(
                              color: Color(0xFFBDBDBD),
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
        backgroundColor: const Color(0xFFE53935),
        shape: const CircleBorder(),
        onPressed: _openCamera,
        child: const Icon(Icons.document_scanner, color: Colors.white, size: 32),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
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
            color:
                isActive ? const Color(0xFFE53935) : const Color(0xFFBDBDBD),
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    return Column(
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
              const Text(
                '116 Documents',
                style: TextStyle(
                  color: Color(0xFF263238),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.search,
                        color: Color(0xFF757575)),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.tune,
                        color: Color(0xFF757575)),
                  ),
                ],
              ),
            ],
          ),
        ),
        // PDF List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            itemCount: pdfFiles.length,
            itemBuilder: (context, index) {
              return _buildPDFTile(pdfFiles[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPDFTile(PDFFile pdf) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
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
            color: Color(0xFF263238),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${pdf.date} • ${pdf.size}',
          style: const TextStyle(
            color: Color(0xFF9E9E9E),
            fontSize: 12,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  pdfFiles[pdfFiles.indexOf(pdf)].isFavorite =
                      !pdfFiles[pdfFiles.indexOf(pdf)].isFavorite;
                });
              },
              icon: Icon(
                pdf.isFavorite ? Icons.star : Icons.star_outline,
                color: const Color(0xFFE53935),
                size: 20,
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.more_vert,
                  color: Color(0xFFBDBDBD), size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class PDFFile {
  String name;
  String date;
  String size;
  bool isFavorite;

  PDFFile({
    required this.name,
    required this.date,
    required this.size,
    required this.isFavorite,
  });
}
