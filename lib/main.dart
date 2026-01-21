import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const SprintSlidesApp());
}

class SprintSlidesApp extends StatelessWidget {
  const SprintSlidesApp({super.key});

  static const Color kBrand = Color(0xFF4F46E5);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: kBrand),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "SprintSlides",
      theme: theme,
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
  final _topic = TextEditingController(text: "photosynthesis");
  final _groqKey = TextEditingController();

  bool _loading = false;
  String? _error;

  List<SprintSlide> _slides = [];
  int _index = 0;

  @override
  void dispose() {
    _topic.dispose();
    _groqKey.dispose();
    super.dispose();
  }

  // ✅ Groq models (fast + reliable for hackathons)
  static const String _model = "llama-3.1-8b-instant";
  // Alternatives you can try:
  // static const String _model = "llama-3.3-70b-versatile";

  Future<void> _generateDeck() async {
    final topic = _topic.text.trim();
    final key = _groqKey.text.trim();

    if (topic.isEmpty) {
      setState(() => _error = "Please enter a topic.");
      return;
    }
    if (key.isEmpty) {
      setState(() => _error = "Please paste your Groq API key.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _slides = [];
      _index = 0;
    });

    try {
      final prompt = _buildPrompt(topic);

      final url = Uri.parse("https://api.groq.com/openai/v1/chat/completions");

      final payload = {
        "model": _model,
        "messages": [
          {
            "role": "system",
            "content":
                "You are an expert academic coach. You output ONLY valid JSON."
          },
          {"role": "user", "content": prompt}
        ],
        "temperature": 0.4,
        "max_tokens": 1200,
      };

      final resp = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $key",
        },
        body: jsonEncode(payload),
      );

      if (resp.statusCode != 200) {
        throw Exception(
          "Groq error (${resp.statusCode}): ${resp.body}",
        );
      }

      final decoded = jsonDecode(resp.body);

      final rawText = decoded["choices"]?[0]?["message"]?["content"]?.toString();

      if (rawText == null || rawText.trim().isEmpty) {
        throw Exception("Groq returned empty content.");
      }

      // cleanup
      final cleaned = _forceJsonOnly(_stripMarkdown(rawText));

      Map<String, dynamic> parsed;
      try {
        parsed = jsonDecode(cleaned);
      } catch (_) {
        throw Exception(
          "Groq returned invalid JSON.\n\nRaw:\n$rawText\n\nCleaned:\n$cleaned",
        );
      }

      final slidesJson = parsed["slides"];
      if (slidesJson is! List) {
        throw Exception("Response JSON missing 'slides' list.");
      }

      final slides = slidesJson
          .map((e) => SprintSlide.fromJson(e as Map<String, dynamic>))
          .toList();

      if (slides.length != 5) {
        throw Exception("Expected 5 slides, got ${slides.length}.");
      }

      setState(() {
        _slides = slides;
        _index = 0;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceAll("Exception:", "").trim());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _prev() {
    if (_index > 0) setState(() => _index--);
  }

  void _next() {
    if (_index < _slides.length - 1) setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    final brand = SprintSlidesApp.kBrand;

    return Scaffold(
      appBar: AppBar(
        title: const Text("SprintSlides"),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _TopPanel(
                  topicController: _topic,
                  apiKeyController: _groqKey,
                  loading: _loading,
                  onGenerate: _generateDeck,
                ),
                const SizedBox(height: 18),
                if (_error != null)
                  _ErrorBox(text: _error!)
                else if (_loading)
                  const _LoadingBox()
                else if (_slides.isEmpty)
                  const _EmptyState()
                else
                  SlideViewer(
                    slides: _slides,
                    index: _index,
                    onPrev: _prev,
                    onNext: _next,
                    brand: brand,
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 8),
        child: Text(
          "Powered by Flutter Web + Groq ⚡",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black.withOpacity(0.55)),
        ),
      ),
    );
  }
}

/// -------------------------
/// Prompt
/// -------------------------
String _buildPrompt(String topic) {
  return """
Create a 5-slide revision deck for the topic: "$topic".

Focus strongly on:
1) Active Recall
2) Structural Learning

IMPORTANT RESPONSE RULES:
- Return ONLY valid JSON.
- No Markdown.
- No code fences.
- No explanation outside JSON.
- Exactly 5 slides.

JSON schema:
{
  "slides": [
    { "type": "String", "title": "String", "content": "String" }
  ]
}

Slide requirements:
- type must be one of: ["overview","core_concepts","active_recall","examples","exam_tips"]
- title should be short and strong
- content should be concise bullet-style text separated by newlines (\\n)

Make EXACTLY 5 slides.
""".trim();
}

/// -------------------------
/// Helpers
/// -------------------------
String _stripMarkdown(String t) {
  t = t.trim();
  if (t.startsWith("```")) {
    final firstNewline = t.indexOf("\n");
    if (firstNewline != -1) {
      t = t.substring(firstNewline + 1);
    }
    final lastFence = t.lastIndexOf("```");
    if (lastFence != -1) {
      t = t.substring(0, lastFence);
    }
  }
  return t.trim();
}

String _forceJsonOnly(String t) {
  t = t.trim();
  final start = t.indexOf("{");
  final end = t.lastIndexOf("}");
  if (start == -1 || end == -1 || end <= start) return t;
  return t.substring(start, end + 1).trim();
}

/// -------------------------
/// UI Widgets
/// -------------------------
class _TopPanel extends StatelessWidget {
  const _TopPanel({
    required this.topicController,
    required this.apiKeyController,
    required this.loading,
    required this.onGenerate,
  });

  final TextEditingController topicController;
  final TextEditingController apiKeyController;
  final bool loading;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final brand = SprintSlidesApp.kBrand;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.black.withOpacity(0.07)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: topicController,
                    decoration: const InputDecoration(
                      labelText: "Topic",
                      hintText: "e.g., Photosynthesis / Electrostatics / DSA",
                    ),
                    onSubmitted: (_) => onGenerate(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: apiKeyController,
                    decoration: const InputDecoration(
                      labelText: "Groq API Key",
                      hintText: "Paste Groq API key",
                    ),
                    obscureText: true,
                    onSubmitted: (_) => onGenerate(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: loading ? null : onGenerate,
                  icon: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(loading ? "Generating..." : "Generate Deck"),
                ),
                const SizedBox(width: 12),
                Text(
                  "5-slide Sprint Deck • Active Recall • Structural Learning",
                  style: TextStyle(color: Colors.black.withOpacity(0.55)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.red.withOpacity(0.07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.red.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingBox extends StatelessWidget {
  const _LoadingBox();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.black.withOpacity(0.07)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(28),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text("Generating your Sprint Deck..."),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.black.withOpacity(0.07)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(28),
        child: Center(
          child: Text(
            "Enter a topic + Groq API key, then generate your 5-slide Sprint Deck ⚡",
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class SlideViewer extends StatelessWidget {
  const SlideViewer({
    super.key,
    required this.slides,
    required this.index,
    required this.onPrev,
    required this.onNext,
    required this.brand,
  });

  final List<SprintSlide> slides;
  final int index;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final Color brand;

  @override
  Widget build(BuildContext context) {
    final slide = slides[index];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.black.withOpacity(0.07)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: brand.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: brand.withOpacity(0.25)),
                  ),
                  child: Text(
                    slide.type.toUpperCase(),
                    style: TextStyle(
                      color: brand,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Text(
                  "Slide ${index + 1} / ${slides.length}",
                  style: TextStyle(color: Colors.black.withOpacity(0.55)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              slide.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              slide.content,
              style: const TextStyle(fontSize: 16, height: 1.45),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: index == 0 ? null : onPrev,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text("Prev"),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: index == slides.length - 1 ? null : onNext,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text("Next"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// -------------------------
/// Model
/// -------------------------
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
      type: (json["type"] ?? "").toString(),
      title: (json["title"] ?? "").toString(),
      content: (json["content"] ?? "").toString(),
    );
  }
}
