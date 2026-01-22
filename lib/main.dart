import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const SprintSlidesApp());
}

class SprintSlidesApp extends StatelessWidget {
  const SprintSlidesApp({super.key});

  // Modern Dark Theme Colors
  static const Color kBackground = Color(0xFF0A0D14);
  static const Color kCardBg = Color(0xFF1C2130);
  static const Color kPrimary = Color(0xFF6366F1); // Indigo 500
  static const Color kTextMain = Colors.white;
  static const Color kTextSub = Color(0xFF9CA3AF); // Gray 400

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SprintSlides',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBackground,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: kPrimary,
          surface: kCardBg,
          onSurface: kTextMain,
          background: kBackground,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: kTextMain,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          titleMedium: TextStyle(
            color: kTextMain,
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: TextStyle(color: kTextMain, fontSize: 16),
          bodyMedium: TextStyle(color: kTextSub, fontSize: 14),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kBackground,
          hintStyle: const TextStyle(color: Colors.grey),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kPrimary, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: kPrimary,
          inactiveTrackColor: kBackground,
          thumbColor: kPrimary,
          trackHeight: 6.0,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10.0),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 20.0),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ),
      ),
      home: const SprintSlidesHome(),
    );
  }
}

class SprintSlidesHome extends StatefulWidget {
  const SprintSlidesHome({super.key});

  @override
  State<SprintSlidesHome> createState() => _SprintSlidesHomeState();
}

class _SprintSlidesHomeState extends State<SprintSlidesHome> {
  final _topic = TextEditingController();
  final PageController _pageController = PageController();

  // State
  double _numSlides = 5;
  bool _loading = false;
  String? _error;
  List<SprintSlide> _slides = [];
  int _currentIndex = 0;

  // ✅ Backend URLs
  static const String _backendUrl = "http://localhost:8000/generateDeck";
  static const String _pdfUrl = "http://localhost:8000/downloadPdf";

  @override
  void dispose() {
    _topic.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _generateDeck() async {
    final topicText = _topic.text.trim();
    final count = _numSlides.round();

    if (topicText.isEmpty) {
      _showSnack("Please enter a topic first.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _slides = [];
      _currentIndex = 0;
    });

    try {
      final resp = await http.post(
        Uri.parse(_backendUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "topic": topicText,
          "slideCount": count,
        }),
      );

      if (resp.statusCode != 200) {
        throw Exception(_cleanBackendError(resp.body));
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception("Invalid backend response format.");
      }

      final slidesJson = decoded["slides"];
      if (slidesJson is! List) {
        throw Exception("Backend response missing slides list.");
      }

      final slides = slidesJson
          .map((e) => SprintSlide.fromJson(e as Map<String, dynamic>))
          .toList();

      if (slides.length != count) {
        throw Exception("Expected $count slides, got ${slides.length}.");
      }

      setState(() {
        _slides = slides;
        _currentIndex = 0;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) _pageController.jumpToPage(0);
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll("Exception:", "").trim();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadPdf() async {
    if (_slides.isEmpty) {
      _showSnack("Generate a deck first.");
      return;
    }

    final topicText = _topic.text.trim();
    if (topicText.isEmpty) {
      _showSnack("Topic missing.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final slidesJson = _slides.map((s) => s.toJson()).toList();

      final resp = await http.post(
        Uri.parse(_pdfUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "topic": topicText,
          "slides": slidesJson,
        }),
      );

      if (resp.statusCode != 200) {
        throw Exception(_cleanBackendError(resp.body));
      }

      final Uint8List pdfBytes = resp.bodyBytes;
      final blob = html.Blob([pdfBytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);

      final safeTopic =
          topicText.replaceAll(RegExp(r'[^a-zA-Z0-9_\- ]'), '').trim();
      final filename = "SprintSlides_${safeTopic.replaceAll(' ', '_')}.pdf";

      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", filename)
        ..click();

      html.Url.revokeObjectUrl(url);
      _showSnack("PDF downloaded ✅");
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll("Exception:", "").trim();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: SprintSlidesApp.kBackground,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.white.withOpacity(0.1), height: 1),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: SprintSlidesApp.kPrimary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: SprintSlidesApp.kPrimary.withOpacity(0.3)),
              ),
              child: const Icon(Icons.flash_on_rounded,
                  color: Color(0xFF818CF8), size: 20),
            ),
            const SizedBox(width: 12),
            const Text("SprintSlides",
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 20.0),
              child: Text(
                _slides.isEmpty
                    ? "Ready"
                    : "${_currentIndex + 1} / ${_slides.length}",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: SprintSlidesApp.kTextSub,
                ),
              ),
            ),
          )
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _InputCard(
                  topicController: _topic,
                  numSlides: _numSlides,
                  onSliderChanged: (val) => setState(() => _numSlides = val),
                  onGenerate: _generateDeck,
                  onDownloadPdf: _downloadPdf,
                  isLoading: _loading,
                  downloadEnabled: _slides.isNotEmpty && !_loading,
                ),
              ),
              const SizedBox(height: 30),
              Expanded(
                child: _loading
                    ? const Center(child: _LoadingIndicator())
                    : _error != null
                        ? Center(child: _ErrorDisplay(error: _error!))
                        : _slides.isEmpty
                            ? const _EmptyStateDisplay()
                            : _SlideDeckViewer(
                                controller: _pageController,
                                slides: _slides,
                                onPageChanged: (idx) {
                                  setState(() => _currentIndex = idx);
                                },
                              ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const Padding(
        padding: EdgeInsets.only(bottom: 24),
        child: Text(
          "Powered by Flutter + Backend ⚡",
          textAlign: TextAlign.center,
          style: TextStyle(color: SprintSlidesApp.kTextSub, fontSize: 12),
        ),
      ),
    );
  }
}

/// -------------------------
/// UI Components
/// -------------------------

class _InputCard extends StatelessWidget {
  final TextEditingController topicController;
  final double numSlides;
  final ValueChanged<double> onSliderChanged;
  final VoidCallback onGenerate;
  final VoidCallback onDownloadPdf;
  final bool isLoading;
  final bool downloadEnabled;

  const _InputCard({
    required this.topicController,
    required this.numSlides,
    required this.onSliderChanged,
    required this.onGenerate,
    required this.onDownloadPdf,
    required this.isLoading,
    required this.downloadEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: SprintSlidesApp.kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("What do you want to learn?",
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: SprintSlidesApp.kTextSub,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: topicController,
                style: const TextStyle(fontWeight: FontWeight.w500),
                decoration: const InputDecoration(
                  hintText: "e.g., Quantum Physics, French History...",
                  prefixIcon:
                      Icon(Icons.search, color: SprintSlidesApp.kTextSub),
                ),
                onSubmitted: (_) => onGenerate(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Divider(color: Colors.white.withOpacity(0.05)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.layers_outlined,
                      size: 16, color: Color(0xFF818CF8)),
                  const SizedBox(width: 8),
                  Text("Deck Size",
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: SprintSlidesApp.kTextSub,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: SprintSlidesApp.kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: SprintSlidesApp.kPrimary.withOpacity(0.2)),
                ),
                child: Text(
                  "${numSlides.round()} Slides",
                  style: const TextStyle(
                    color: Color(0xFF818CF8),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: numSlides,
            min: 5,
            max: 15,
            divisions: 10,
            onChanged: onSliderChanged,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : onGenerate,
              icon: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(isLoading
                  ? "Generating Deck..."
                  : "Generate Sprint Deck"),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: downloadEnabled ? onDownloadPdf : null,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text("Download PDF"),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                side: BorderSide(
                    color: SprintSlidesApp.kPrimary.withOpacity(0.6)),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideDeckViewer extends StatelessWidget {
  final PageController controller;
  final List<SprintSlide> slides;
  final Function(int) onPageChanged;

  const _SlideDeckViewer({
    required this.controller,
    required this.slides,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: controller,
            onPageChanged: onPageChanged,
            itemCount: slides.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: _SlideCard(slide: slides[index]),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => controller.previousPage(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: SprintSlidesApp.kCardBg,
                  padding: const EdgeInsets.all(16),
                  side: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                icon: const Icon(Icons.chevron_left),
              ),
              const SizedBox(width: 24),
              SizedBox(
                height: 40,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(slides.length, (i) {
                    return AnimatedBuilder(
                      animation: controller,
                      builder: (ctx, child) {
                        double selectedness = 0.0;
                        if (controller.hasClients &&
                            controller.position.haveDimensions) {
                          selectedness = 1.0 -
                              ((controller.page ?? 0) - i)
                                  .abs()
                                  .clamp(0.0, 1.0);
                        } else {
                          selectedness = i == 0 ? 1.0 : 0.0;
                        }

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 6,
                          width: 6 + (24 * selectedness),
                          decoration: BoxDecoration(
                            color: Color.lerp(Colors.grey[800],
                                SprintSlidesApp.kPrimary, selectedness),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      },
                    );
                  }),
                ),
              ),
              const SizedBox(width: 24),
              IconButton(
                onPressed: () => controller.nextPage(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: SprintSlidesApp.kCardBg,
                  padding: const EdgeInsets.all(16),
                  side: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        )
      ],
    );
  }
}

class _SlideCard extends StatelessWidget {
  final SprintSlide slide;

  const _SlideCard({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: SprintSlidesApp.kCardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: SprintSlidesApp.kPrimary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                slide.type.toUpperCase().replaceAll("_", " "),
                style: const TextStyle(
                  color: Color(0xFF818CF8),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              slide.title,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: SprintSlidesApp.kTextMain,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Text(
                  slide.content,
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.6,
                    color: Color(0xFFD1D5DB),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateDisplay extends StatelessWidget {
  const _EmptyStateDisplay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text("Enter a topic to generate slides!",
          style: TextStyle(color: Colors.grey[400])),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(strokeWidth: 3),
        const SizedBox(height: 16),
        Text("Generating...", style: TextStyle(color: Colors.grey[400])),
      ],
    );
  }
}

class _ErrorDisplay extends StatelessWidget {
  final String error;
  const _ErrorDisplay({required this.error});

  @override
  Widget build(BuildContext context) {
    return Text(error, style: const TextStyle(color: Colors.redAccent));
  }
}

String _cleanBackendError(String body) {
  try {
    final parsed = jsonDecode(body);
    final detail = parsed["detail"];

    if (detail is String) return detail;
    if (detail is Map && detail["error"] != null) return detail["error"].toString();

    return "Backend error. Try again.";
  } catch (_) {
    if (body.length > 200) return body.substring(0, 200) + "...";
    return body;
  }
}

class SprintSlide {
  final String type;
  final String title;
  final String content;

  const SprintSlide({
    required this.type,
    required this.title,
    required this.content,
  });

  factory SprintSlide.fromJson(Map<String, dynamic> json) {
    return SprintSlide(
      type: (json["type"] ?? "slide").toString(),
      title: (json["title"] ?? "").toString(),
      content: (json["content"] ?? "").toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "type": type,
      "title": title,
      "content": content,
    };
  }
}
