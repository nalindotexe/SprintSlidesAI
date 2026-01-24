# SprintSlides AI 🧠⚡

![Flutter](https://img.shields.io/badge/Flutter-Web%20%7C%20Mobile-02569B?logo=flutter&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-Backend-009688?logo=fastapi&logoColor=white)
![Groq](https://img.shields.io/badge/Groq-LLM%20API-orange)
![Firebase](https://img.shields.io/badge/Firebase-Hosting-FFCA28?logo=firebase&logoColor=black)
![Render](https://img.shields.io/badge/Render-Backend%20Hosting-46E3B7?logo=render&logoColor=black)
![PDF](https://img.shields.io/badge/PDF-Export-red?logo=adobeacrobatreader&logoColor=white)
![Status](https://img.shields.io/badge/Status-Live-success)

---

## 🚀 SprintSlides AI

**SprintSlides AI** is an AI-powered revision tool that converts academic topics into **structured, exam-focused study slides** and allows students to **download them as PDFs**.

Built for speed, clarity, and efficiency — SprintSlides helps students *study smarter, not longer*.

🔗 **Live App:** https://sprintslides.web.app  
🔗 **Backend API:** https://sprintslidesai.onrender.com  

---

## ✨ Features

- 🧠 **AI Slide Generation**  
  Generate **5–15 structured revision slides** from any topic.

- ⚡ **Ultra-Fast Inference**  
  Powered by **Groq API (LLaMA 3)** for low-latency, high-quality responses.

- 📄 **PDF Export**  
  Download a professionally formatted PDF including:
  - Title page
  - App logo
  - Slide numbering
  - Clean layout for printing & offline study

- 🎯 **Exam-Oriented Content**  
  Slides focus on:
  - Core concepts  
  - Active recall  
  - Examples & exam tips  

- 🌐 **Cross-Platform UI**  
  Built with Flutter → works on **Web, Android, and iOS**.

---

## 🛠️ Tech Stack

### Frontend
- Flutter (Web)
- Material 3 UI
- Firebase Hosting

### Backend
- FastAPI (Python)
- Groq API (LLaMA 3.1 8B Instant)
- ReportLab (PDF generation)
- Render (Backend hosting)

---

## 🧱 Architecture

Flutter Web App
|
| POST /generateDeck
v
FastAPI Backend (Render)
|
| Groq API (LLM)
v
Structured JSON Slides
|
| POST /downloadPdf
v
PDF Generation (ReportLab)


---

## 🧪 Local Development

### Prerequisites
- Flutter SDK
- Python 3.10+
- Groq API Key

---

### Backend Setup

```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```
Create .env file:
```bash
GROQ_API_KEY=your_groq_api_key_here
```
Run backend:
```bash
uvicorn main:app --reload
```
Frontend Setup
```bash
flutter pub get
flutter run -d chrome
```
📄 PDF Export

  Generated server-side using ReportLab
    Includes:
       Logo branding
        Topic title
        Slide headers
        Automatic text wrapping

🎯 Motivation

SprintSlides was built to solve information overload during exams.

It applies:

   The 80/20 rule
    Active recall
    Structured learning

So students revise faster and more effectively.

### 👨‍💻 Developers
   Nalin Singh
    GitHub: https://github.com/nalindotexe
   
   Pragna K.
    GitHub: https://github.com/Pragna-15

🤝 Contributing

Pull requests are welcome.

Ideas for future features:
    Flashcards, Quizzes, User accounts,Saved decks, Themed PDFs


Built with ❤️ for students, speed, and hackathons.
