const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

/**
 * Add Gemini key with:
 * firebase functions:config:set gemini.key="YOUR_AI_STUDIO_KEY"
 */
function getGeminiKey() {
  const key = functions.config()?.gemini?.key;
  if (!key) throw new Error("Missing Gemini key. Set: firebase functions:config:set gemini.key");
  return key;
}

function cors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
}

function buildPrompt(topic) {
  return `
You are an expert academic coach.

Create a 5-slide revision deck for the topic: "${topic}".
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
`.trim();
}

function stripMarkdownFences(text) {
  let t = (text || "").trim();
  if (t.startsWith("```")) {
    const firstNewline = t.indexOf("\n");
    if (firstNewline !== -1) t = t.substring(firstNewline + 1);
    const lastFence = t.lastIndexOf("```");
    if (lastFence !== -1) t = t.substring(0, lastFence);
  }
  return t.trim();
}

function forceJsonOnly(text) {
  const t = (text || "").trim();
  const start = t.indexOf("{");
  const end = t.lastIndexOf("}");
  if (start === -1 || end === -1 || end <= start) return t;
  return t.substring(start, end + 1).trim();
}

async function callGeminiGenerateContent({ model, apiKey, prompt }) {
  const url = `https://generativelanguage.googleapis.com/v1/models/${model}:generateContent?key=${apiKey}`;

  const payload = {
    contents: [
      { role: "user", parts: [{ text: prompt }] }
    ],
    generationConfig: {
      temperature: 0.4,
      maxOutputTokens: 1200
    }
  };

  const resp = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });

  const bodyText = await resp.text();
  let body;
  try {
    body = JSON.parse(bodyText);
  } catch {
    body = { raw: bodyText };
  }

  return { status: resp.status, body };
}

function extractGeminiText(respBody) {
  try {
    return respBody?.candidates?.[0]?.content?.parts?.[0]?.text?.toString() ?? "";
  } catch {
    return "";
  }
}

const MODEL_FALLBACKS = [
  "gemini-2.0-flash",
  "gemini-1.5-flash"
];

exports.generateDeck = functions.https.onRequest(async (req, res) => {
  cors(res);

  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "POST") return res.status(405).json({ error: "Use POST" });

  try {
    const { topic, userId } = req.body || {};
    if (!topic || typeof topic !== "string") {
      return res.status(400).json({ error: "Missing topic" });
    }

    const apiKey = getGeminiKey();
    const prompt = buildPrompt(topic.trim());

    let lastErr = null;
    let modelUsed = null;
    let rawText = null;

    for (const model of MODEL_FALLBACKS) {
      const { status, body } = await callGeminiGenerateContent({ model, apiKey, prompt });

      if (status === 200) {
        modelUsed = model;
        rawText = extractGeminiText(body);
        break;
      }

      lastErr = { model, status, body };
      if (status === 429) break;
    }

    if (!rawText || rawText.trim() === "") {
      return res.status(500).json({
        error: "Gemini returned empty or failed.",
        debug: lastErr,
      });
    }

    const cleaned = stripMarkdownFences(rawText);
    const safeJson = forceJsonOnly(cleaned);

    let decoded;
    try {
      decoded = JSON.parse(safeJson);
    } catch {
      return res.status(500).json({
        error: "Failed to parse JSON from Gemini output.",
        modelUsed,
        rawOutput: rawText,
        cleanedOutput: safeJson,
      });
    }

    const slides = decoded?.slides;
    if (!Array.isArray(slides) || slides.length !== 5) {
      return res.status(500).json({
        error: "Invalid deck format. Expected slides array of length 5.",
        modelUsed,
        decoded,
      });
    }

    // Save to Firestore (optional)
    let docId = null;
    try {
      const ref = await db.collection("decks").add({
        topic: topic.trim(),
        slides,
        userId: userId || null,
        modelUsed,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      docId = ref.id;
    } catch (e) {}

    return res.status(200).json({ ok: true, modelUsed, docId, slides });
  } catch (e) {
    return res.status(500).json({ error: e?.message || String(e) });
  }
});
