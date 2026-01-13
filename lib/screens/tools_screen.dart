import 'package:flutter/material.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = [
      {
        'icon': Icons.qr_code_scanner,
        'title': 'Scan to PDF',
        'color': const Color(0xFFB2E7D9),
      },
      {
        'icon': Icons.image,
        'title': 'Image to PDF',
        'color': const Color(0xFFFFD9B3),
      },
      {
        'icon': Icons.cut,
        'title': 'Split PDF',
        'color': const Color(0xFFE8B4E1),
      },
      {
        'icon': Icons.merge,
        'title': 'Merge PDF',
        'color': const Color(0xFFB3E5B3),
      },
      {
        'icon': Icons.edit,
        'title': 'Annotate',
        'color': const Color(0xFFD9D4E8),
      },
      {
        'icon': Icons.compress,
        'title': 'Compress PDF',
        'color': const Color(0xFFFFCDD2),
      },
      {
        'icon': Icons.folder_zip,
        'title': 'Create a ZIP file',
        'color': const Color(0xFFFFE8B3),
      },
      {
        'icon': Icons.print,
        'title': 'Print',
        'color': const Color(0xFFB3D9FF),
      },
    ];

    return ListView(
      children: [
        GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
            childAspectRatio: 0.95,
          ),
          itemCount: tools.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, index) {
            final tool = tools[index] as Map<String, dynamic>;
            return _buildToolCard(
              context,
              icon: tool['icon'] as IconData,
              title: tool['title'] as String,
              backgroundColor: tool['color'] as Color,
            );
          },
        ),
      ],
    );
  }

  Widget _buildToolCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color backgroundColor,
  }) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title clicked'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF263238),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
