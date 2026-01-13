import 'package:flutter/material.dart';
import 'dart:async';
import '../painters/pdf_icon_painter.dart';

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
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // PDF Icon with custom design
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // PDF Icon Background
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: CustomPaint(
                        painter: PDFIconPainter(),
                      ),
                    ),
                    // Green checkmark overlay
                    Positioned(
                      bottom: 5,
                      right: 5,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF66BB6A),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              // App Title
              const Text(
                'PDF Reader',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF263238),
                ),
              ),
              const SizedBox(height: 50),
              // Progress Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 60),
                child: AnimatedBuilder(
                  animation: _progressAnimation,
                  builder: (context, child) {
                    return Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _progressAnimation.value,
                            minHeight: 6,
                            backgroundColor: const Color(0xFFE0E0E0),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFFE53935),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
                    const Text(
                      'PDF Reader',
                      style: TextStyle(
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
              ),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Home
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() => _selectedBottomNavIndex = 0);
                      },
                      icon: const Icon(Icons.home,
                          color: Color(0xFFE53935), size: 24),
                    ),
                    const Text(
                      'Home',
                      style: TextStyle(
                        color: Color(0xFFE53935),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Tools
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() => _selectedBottomNavIndex = 1);
                      },
                      icon: const Icon(Icons.dashboard,
                          color: Color(0xFFBDBDBD), size: 24),
                    ),
                    const Text(
                      'Tools',
                      style: TextStyle(
                        color: Color(0xFFBDBDBD),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFE53935),
        shape: const CircleBorder(),
        onPressed: () {},
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 32),
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
