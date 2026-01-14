import 'package:flutter/material.dart';
import '../painters/tool_icons_painter.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // First row of tools
          Row(
            children: [
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Scan to PDF',
                  backgroundColor: const Color(0xFFB2E7D9),
                  iconColor: const Color(0xFF4CAF50),
                  painter: ScanToPDFPainter(color: const Color(0xFF4CAF50)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Image to PDF',
                  backgroundColor: const Color(0xFFFFD9B3),
                  iconColor: const Color(0xFFFF9800),
                  painter: ImageToPDFPainter(color: const Color(0xFFFF9800)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Second row of tools
          Row(
            children: [
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Split PDF',
                  backgroundColor: const Color(0xFFE8B4E1),
                  iconColor: const Color(0xFF9C27B0),
                  painter: SplitPDFPainter(color: const Color(0xFF9C27B0)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Merge PDF',
                  backgroundColor: const Color(0xFFB3E5B3),
                  iconColor: const Color(0xFF4CAF50),
                  painter: MergePDFPainter(color: const Color(0xFF4CAF50)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Third row of tools
          Row(
            children: [
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Annotate',
                  backgroundColor: const Color(0xFFD9D4E8),
                  iconColor: const Color(0xFF9C27B0),
                  painter: AnnotatePainter(color: const Color(0xFF9C27B0)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Compress PDF',
                  backgroundColor: const Color(0xFFFFCDD2),
                  iconColor: const Color(0xFFE53935),
                  painter: CompressPDFPainter(color: const Color(0xFFE53935)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Fourth row of tools
          Row(
            children: [
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Create a ZIP file',
                  backgroundColor: const Color(0xFFFFE8B3),
                  iconColor: const Color(0xFFFFC107),
                  painter: CreateZIPPainter(color: const Color(0xFFFFC107)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'Print',
                  backgroundColor: const Color(0xFFB3D9FF),
                  iconColor: const Color(0xFF2196F3),
                  painter: PrintPainter(color: const Color(0xFF2196F3)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildToolCard(
    BuildContext context, {
    required String title,
    required Color backgroundColor,
    required Color iconColor,
    required CustomPainter painter,
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
        padding: const EdgeInsets.all(16),
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
              child: CustomPaint(
                painter: painter,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF263238),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
