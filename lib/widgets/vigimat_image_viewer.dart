import 'dart:io';
import 'package:flutter/material.dart';
import '../core/theme/vigimat_colors.dart';

/// Visionneuse interactive plein écran pour photos avec zoom et panoramique
class VigimatImageViewer extends StatefulWidget {
  const VigimatImageViewer({
    super.key,
    this.filePaths = const [],
    this.imageUrls = const [],
    this.initialIndex = 0,
    this.title = 'Photo du Matériel',
  });

  final List<String> filePaths;
  final List<String> imageUrls;
  final int initialIndex;
  final String title;

  static void showFile(
    BuildContext context, {
    required String filePath,
    String title = 'Photo du Matériel',
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VigimatImageViewer(
          filePaths: [filePath],
          title: title,
        ),
      ),
    );
  }

  static void showUrl(
    BuildContext context, {
    required String imageUrl,
    String title = 'Photo du Matériel',
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VigimatImageViewer(
          imageUrls: [imageUrl],
          title: title,
        ),
      ),
    );
  }

  static void showGallery(
    BuildContext context, {
    List<String> filePaths = const [],
    List<String> imageUrls = const [],
    int initialIndex = 0,
    String title = 'Photos du Matériel',
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VigimatImageViewer(
          filePaths: filePaths,
          imageUrls: imageUrls,
          initialIndex: initialIndex,
          title: title,
        ),
      ),
    );
  }

  @override
  State<VigimatImageViewer> createState() => _VigimatImageViewerState();
}

class _VigimatImageViewerState extends State<VigimatImageViewer> {
  late int _currentIndex;
  late final PageController _pageController;

  int get _totalCount =>
      widget.filePaths.isNotEmpty ? widget.filePaths.length : widget.imageUrls.length;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = _totalCount > 1;

    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A192F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (hasMultiple)
              Text(
                'Photo ${_currentIndex + 1} sur $_totalCount',
                style: const TextStyle(
                  color: VigimatColors.turquoise,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _totalCount,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              Widget imageWidget;
              if (widget.filePaths.isNotEmpty) {
                final path = widget.filePaths[index];
                imageWidget = Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => _errorPlaceholder(),
                );
              } else {
                final url = widget.imageUrls[index];
                imageWidget = Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(
                        color: VigimatColors.emerald,
                        strokeWidth: 2.5,
                      ),
                    );
                  },
                  errorBuilder: (_, _, _) => _errorPlaceholder(),
                );
              }

              return Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.5,
                  child: imageWidget,
                ),
              );
            },
          ),

          // Indicateur de zoom en bas
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.pinch_rounded,
                      color: VigimatColors.turquoise,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Pincez pour zoomer · Glissez pour naviguer',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorPlaceholder() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
          SizedBox(height: 10),
          Text(
            'Impossible de charger la photo',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
