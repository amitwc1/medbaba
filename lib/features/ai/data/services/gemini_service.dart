import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../../../core/utils/result.dart';

/// Represents the classification result of a user query.
class QueryClassification {
  final String category;
  final String complexity;

  QueryClassification({required this.category, required this.complexity});
}

/// Represents the full structured result from the upgraded AI service.
class AiResponse {
  final String text;
  final String category;
  final String complexity;

  AiResponse({
    required this.text,
    required this.category,
    required this.complexity,
  });
}

/// Service class interfacing with Google Gemini API using `google_generative_ai`.
class GeminiService {
  GeminiService();

  /// Validates the API key by sending a lightweight prompt to the Gemini API.
  Future<Result<bool>> validateApiKey(String apiKey, String modelName) async {
    if (apiKey.trim().isEmpty) {
      return Result.failure('API key cannot be empty.');
    }
    try {
      final model = GenerativeModel(model: modelName, apiKey: apiKey);
      final response = await model.generateContent([
        Content.text('Ping')
      ]);
      if (response.text != null) {
        return Result.success(true);
      }
      return Result.failure('Empty response received from the Gemini API.');
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('API_KEY_INVALID') || 
          errorMsg.contains('invalid') || 
          errorMsg.contains('403') || 
          errorMsg.contains('INVALID_ARGUMENT')) {
        return Result.failure('Invalid API key. Please check and try again.');
      }
      return Result.failure('API key validation failed: ${e.toString()}');
    }
  }

  /// Classifies the user query into one of 12 categories and determines complexity.
  Future<QueryClassification> classifyQuery(String apiKey, String modelName, String query) async {
    try {
      final model = GenerativeModel(model: modelName, apiKey: apiKey);
      final prompt = '''
Classify the following query into one of these 12 categories:
- Education
- Programming
- Medicine and Health
- Mathematics
- Science
- Business
- Language Learning
- History
- Current Affairs
- General Knowledge
- Productivity
- Career Guidance

Also determine if the query complexity is "simple" (requiring a short direct answer) or "complex" (requiring a comprehensive breakdown).

Return the result in JSON format with EXACTLY these keys:
{
  "category": "...",
  "complexity": "..."
}
Ensure you return ONLY valid JSON and nothing else. Do not add markdown backticks outside of the JSON block if possible, but if you do, ensure they are formatted as a json block.

Query:
$query
''';
      final response = await model.generateContent([Content.text(prompt)]);
      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        return QueryClassification(category: 'General Knowledge', complexity: 'complex');
      }

      // Clean JSON if model returns markdown wrapping
      String jsonStr = text.trim();
      if (jsonStr.startsWith('```')) {
        final lines = jsonStr.split('\n');
        if (lines.first.contains('json')) {
          jsonStr = lines.sublist(1, lines.length - 1).join('\n').trim();
        } else {
          jsonStr = lines.sublist(1, lines.length - 1).join('\n').trim();
        }
      }

      final Map<String, dynamic> data = jsonDecode(jsonStr);
      return QueryClassification(
        category: data['category'] as String? ?? 'General Knowledge',
        complexity: data['complexity'] as String? ?? 'complex',
      );
    } catch (_) {
      return QueryClassification(category: 'General Knowledge', complexity: 'complex');
    }
  }

  /// Performs a QA self-check check on the generated response.
  /// Returns "PASS" or a specific instruction on what failed.
  Future<String> evaluateResponse(
    String apiKey,
    String modelName,
    String query,
    String candidateResponse,
  ) async {
    try {
      final model = GenerativeModel(model: modelName, apiKey: apiKey);
      final prompt = '''
You are an AI Quality Assurance Inspector for MindVault. Your job is to verify if the candidate response satisfies the QA checklist for the user's query.

User Query:
$query

Candidate Response:
$candidateResponse

QA Checklist:
1. Is the response relevant to the user query?
2. Is the response complete and not cut off?
3. Is the response easy to understand and clear?
4. Is the response internally consistent and free of contradictions?
5. Does it provide examples if helpful?
6. Does the response NOT make unsupported claims or fabricate facts?
7. If the query is medical, does it include safety warnings and contact instructions?

Respond with EXACTLY "PASS" if the response is excellent and meets all requirements.
If the response fails any check, reply with "FAIL" followed by a newline and a single brief instruction on what needs correction (e.g. "FAIL\\nAdd possible side effects and a safety warning").
Ensure you do not output any other text.
''';
      final response = await model.generateContent([Content.text(prompt)]);
      return response.text?.trim() ?? 'PASS';
    } catch (_) {
      return 'PASS'; // Fallback to avoid blocking on QA API error
    }
  }

  /// Generates a structured response with query classification and quality checks.
  Future<Result<AiResponse>> generateResponse({
    required String apiKey,
    required String modelName,
    required String query,
    String? contextText,
    List<Map<String, String>>? chatHistory,
  }) async {
    try {
      // 1. Classification
      final classification = await classifyQuery(apiKey, modelName, query);

      // 2. Select category-specific rules
      String categoryConstraints = '';
      switch (classification.category.toLowerCase().replaceAll(' ', '')) {
        case 'medicineandhealth':
        case 'medicine':
        case 'health':
          categoryConstraints = '''
The user query is classified as Medicine and Health.
You must structure your response EXACTLY using these markdown sections:
## Overview
[Provide general educational information]

## How It Works
[Explain the biological/medical mechanisms in simple terms]

## Common Uses
[List common uses, if applicable]

## Possible Side Effects
[Outline common side effects or risks]

## Warnings
[Provide safety warnings, cautions, and contraindications]

## When To Contact A Doctor
[Specify clear symptoms or situations when professional medical help is required]

CRITICAL SAFETY RULES:
- Never claim absolute certainty or write in a diagnostic tone.
- Never invent diagnoses or present guesses as facts.
- Always remain strictly educational.
''';
          break;
        case 'programming':
          categoryConstraints = '''
The user query is classified as Programming.
You must structure your response using these markdown sections:
## Explanation
[A concise explanation of the code, logic, or concept]

## Code Example
[A complete, clean, commenting-supported, and runnable code snippet block]

## Best Practices
[A list of relevant software engineering best practices]

## Common Mistakes
[Common pitfalls and how to avoid them]

## Optimization Tips
[Performance, readability, or architectural optimization details]

CRITICAL RULES:
- Ensure the code is correct, compiles, and adheres to the standards of the language used.
- Include clear comments in the code.
''';
          break;
        case 'mathematics':
        case 'math':
          categoryConstraints = '''
The user query is classified as Mathematics.
You must structure your response using these markdown sections:
## Concept
[An overview of the mathematical concept or rule]

## Formula
[The relevant formulas rendered in clear mathematical notation]

## Step-by-Step Solution
[A detailed step-by-step breakdown of the solving process]

## Final Answer
[The final solution clearly formatted]

## Verification
[A verification step showing why the answer is correct]
''';
          break;
        case 'languagelearning':
          categoryConstraints = '''
The user query is classified as Language Learning.
You must structure your response using these markdown sections:
## Meaning
[Clear explanation of meaning, usage, and translation]

## Pronunciation
[Phonetic guide or pronunciation tips]

## Examples
[Sentences showing correct usage with translations]

## Common Mistakes
[Common learner errors and correct alternatives]

## Practice Exercises
[Short exercises to reinforce learning]
```
''';
          break;
        case 'education':
        case 'student':
          categoryConstraints = '''
The user query is classified as an educational study question.
You must structure your response using these markdown sections:
## Simple Explanation
[A simple, high-level summary using analogies if helpful]

## Detailed Explanation
[A deeper look into the concept]

## Examples
[Concrete, practical examples]

## Step-by-Step Breakdown
[A breakdown of the components or processes]

## Key Points
[Bullet points of critical takeaways]

## Memory Tips
[Mnemonics or active recall memory hooks]

## Practice Questions
[Include 2-3 self-testing practice questions]
''';
          break;
        default:
          if (classification.complexity == 'complex') {
            categoryConstraints = '''
You must structure your response using these markdown sections:
## Summary
[Brief summary of the response]

## Detailed Explanation
[Complete detailed explanation]

## Examples
[Illustrative examples]

## Important Points
[Bullet list of key takeaways]

## Conclusion
[Concluding thoughts]
''';
          } else {
            categoryConstraints = '''
You must structure your response using these markdown sections:
## Direct Answer
[A direct, concise response to the question]

## Brief Explanation
[A brief paragraph providing supporting details]
''';
          }
      }

      // 3. Handle prompt templates
      String templateConstraints = '';
      final lowerQuery = query.toLowerCase();
      if (lowerQuery.contains('active recall') || lowerQuery.contains('flashcard')) {
        templateConstraints = '''
CRITICAL FORMATTING RULE FOR FLASHCARDS:
You must output ONLY flashcards using exactly this format:
Q: [Question]
A: [Answer]

Separate each flashcard with a blank line. Do not include any introduction, conclusion, headers, or bullet points.
''';
      } else if (lowerQuery.contains('mcq') || lowerQuery.contains('quiz')) {
        templateConstraints = '''
CRITICAL FORMATTING RULE FOR QUIZ / MCQs:
You must output multiple choice questions exactly using this Markdown structure:
### Question 1: [Question text]
- A) [Option A]
- B) [Option B]
- C) [Option C]
- D) [Option D]

**Correct Answer:** [Correct letter]
**Explanation:** [Brief explanation of why this option is correct]

Separate each question with a blank line. Do not add general summary or conversational filler.
''';
      }

      // 4. Construct content list and model
      final systemInstruction = '''
You are MindVault AI, an intelligent learning and productivity assistant.

Your primary goal is to provide accurate, helpful, clear, and context-aware responses.

Always:
- Understand user intent.
- Explain concepts clearly.
- Structure answers properly.
- State uncertainty when information is unclear.
- Prefer educational explanations over unsupported conclusions.
- Break down difficult concepts into simple language.
- Provide examples whenever useful.
- Be concise for simple questions and comprehensive for complex questions.
- Never fabricate facts.
- Avoid overconfidence.
- Use Markdown formatting for readability.

$categoryConstraints
$templateConstraints
''';

      final model = GenerativeModel(
        model: modelName,
        apiKey: apiKey,
        systemInstruction: Content('system', [TextPart(systemInstruction)]),
        generationConfig: GenerationConfig(temperature: 0.4),
      );

      final contents = <Content>[];
      if (chatHistory != null) {
        for (final msg in chatHistory) {
          final isUser = msg['role'] == 'user';
          final text = msg['content'] ?? '';
          if (isUser) {
            contents.add(Content('user', [TextPart(text)]));
          } else {
            contents.add(Content('model', [TextPart(text)]));
          }
        }
      }

      String promptText = '';
      if (contextText != null && contextText.trim().isNotEmpty) {
        promptText += 'Context information:\n$contextText\n\n';
      }
      promptText += 'User request:\n$query';
      contents.add(Content('user', [TextPart(promptText)]));

      // 5. Generate Candidate
      final response = await model.generateContent(contents);
      String candidateText = response.text ?? '';

      // Skip QA check for strict template prompts to avoid breaking raw Q/A format
      if (templateConstraints.isNotEmpty) {
        return Result.success(AiResponse(
          text: candidateText,
          category: classification.category,
          complexity: classification.complexity,
        ));
      }

      // 6. QA Evaluation Check
      final qaResult = await evaluateResponse(apiKey, modelName, query, candidateText);
      if (qaResult.startsWith('FAIL')) {
        final feedback = qaResult.substring(4).trim();
        // Corrective Second Pass
        final correctiveContents = List<Content>.from(contents);
        correctiveContents.add(Content('model', [TextPart(candidateText)]));
        correctiveContents.add(Content('user', [TextPart(
          'Your previous response was flagged by Quality Assurance: "$feedback". '
          'Please regenerate the response correcting this issue. Keep the same structure.'
        )]));
        final correctedResponse = await model.generateContent(correctiveContents);
        candidateText = correctedResponse.text ?? candidateText;
      }

      return Result.success(AiResponse(
        text: candidateText,
        category: classification.category,
        complexity: classification.complexity,
      ));
    } catch (e) {
      return Result.failure(_handleError(e));
    }
  }

  /// Generates a concise summary of the provided text.
  Future<Result<String>> generateSummary(String apiKey, String modelName, String text) async {
    final res = await generateResponse(
      apiKey: apiKey,
      modelName: modelName,
      query: 'Summarize this in simple language with key points.',
      contextText: text,
    );
    return res.isSuccess ? Result.success(res.data!.text) : Result.failure(res.error!);
  }

  /// Generates study flashcards (Question/Answer format) from the provided text.
  Future<Result<String>> generateFlashcards(String apiKey, String modelName, String text) async {
    final res = await generateResponse(
      apiKey: apiKey,
      modelName: modelName,
      query: 'Generate high-quality flashcards using active recall principles.',
      contextText: text,
    );
    return res.isSuccess ? Result.success(res.data!.text) : Result.failure(res.error!);
  }

  /// Generates a multiple-choice quiz based on the provided text.
  Future<Result<String>> generateQuiz(String apiKey, String modelName, String text) async {
    final res = await generateResponse(
      apiKey: apiKey,
      modelName: modelName,
      query: 'Generate MCQs with explanations and answers.',
      contextText: text,
    );
    return res.isSuccess ? Result.success(res.data!.text) : Result.failure(res.error!);
  }

  /// Explains a concept in simple terms.
  Future<Result<String>> explainConcept(String apiKey, String modelName, String concept) async {
    final res = await generateResponse(
      apiKey: apiKey,
      modelName: modelName,
      query: 'Explain this topic to a beginner using examples.',
      contextText: concept,
    );
    return res.isSuccess ? Result.success(res.data!.text) : Result.failure(res.error!);
  }

  /// Generates a personalized study plan for a topic.
  Future<Result<String>> generateStudyPlan(String apiKey, String modelName, String topic) async {
    final res = await generateResponse(
      apiKey: apiKey,
      modelName: modelName,
      query: 'Generate a step-by-step study plan.',
      contextText: topic,
    );
    return res.isSuccess ? Result.success(res.data!.text) : Result.failure(res.error!);
  }

  /// Categorizes and formats errors into user-friendly messages.
  String _handleError(dynamic error) {
    final msg = error.toString();
    if (msg.contains('API_KEY_INVALID') || msg.contains('invalid api key')) {
      return 'Invalid API key. Please check and try again.';
    } else if (msg.contains('RESOURCE_EXHAUSTED') || msg.contains('rate limit')) {
      return 'API rate limit exceeded. Please try again later.';
    } else if (msg.contains('quota')) {
      return 'Gemini API quota exceeded. Please check your Google AI Studio billing/quota.';
    } else if (msg.contains('SocketException') || msg.contains('network') || msg.contains('Failed host lookup')) {
      return 'No internet connection. Please verify your network and try again.';
    } else if (msg.contains('TimeoutException') || msg.contains('timeout')) {
      return 'Connection timed out. Please check your internet connection and try again.';
    }
    return 'AI Request Failed: $msg';
  }
}

class ParsedMcq {
  final String question;
  final List<String> options;
  final String correctAnswer;
  final String explanation;

  ParsedMcq({
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
  });
}

class AiResponseParser {
  static List<(String, String)> parseFlashcards(String text) {
    final cards = <(String, String)>[];
    final lines = text.split('\n');
    String currentQ = '';
    String currentA = '';
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith(RegExp(r'^Q\s*:\s*', caseSensitive: false))) {
        if (currentQ.isNotEmpty && currentA.isNotEmpty) {
          cards.add((currentQ, currentA));
          currentQ = '';
          currentA = '';
        }
        currentQ = trimmed.replaceFirst(RegExp(r'^Q\s*:\s*', caseSensitive: false), '').trim();
      } else if (trimmed.startsWith(RegExp(r'^A\s*:\s*', caseSensitive: false))) {
        currentA = trimmed.replaceFirst(RegExp(r'^A\s*:\s*', caseSensitive: false), '').trim();
      } else if (trimmed.isNotEmpty) {
        if (currentA.isNotEmpty) {
          currentA += '\n$trimmed';
        } else if (currentQ.isNotEmpty) {
          currentQ += '\n$trimmed';
        }
      }
    }
    if (currentQ.isNotEmpty && currentA.isNotEmpty) {
      cards.add((currentQ, currentA));
    }
    return cards;
  }

  static List<ParsedMcq> parseMcqs(String text) {
    final mcqs = <ParsedMcq>[];
    final sections = text.split(RegExp(r'###\s*Question\s*\d+\s*:\s*', caseSensitive: false));

    for (final section in sections) {
      if (section.trim().isEmpty) continue;

      final lines = section.split('\n').map((l) => l.trim()).toList();
      if (lines.isEmpty) continue;

      String questionText = '';
      final options = <String>[];
      String correctAnswer = '';
      String explanation = '';

      int lineIdx = 0;
      while (lineIdx < lines.length && !lines[lineIdx].startsWith(RegExp(r'^[-\*]\s*[A-D]\)'))) {
        if (lines[lineIdx].isNotEmpty) {
          if (questionText.isNotEmpty) questionText += '\n';
          questionText += lines[lineIdx];
        }
        lineIdx++;
      }

      while (lineIdx < lines.length && (lines[lineIdx].startsWith(RegExp(r'^[-\*]\s*[A-D]\)')) || lines[lineIdx].startsWith(RegExp(r'^[A-D]\)')))) {
        final line = lines[lineIdx];
        final cleanedOpt = line.replaceFirst(RegExp(r'^[-\*]\s*'), '').trim();
        options.add(cleanedOpt);
        lineIdx++;
      }

      for (int i = lineIdx; i < lines.length; i++) {
        final line = lines[i];
        if (line.toLowerCase().contains('correct answer')) {
          final match = RegExp(r'correct\s*answer\s*[:\*]*\s*([A-D])', caseSensitive: false).firstMatch(line);
          if (match != null) {
            correctAnswer = match.group(1)!.toUpperCase();
          }
        } else if (line.toLowerCase().contains('explanation')) {
          explanation = line.replaceFirst(RegExp(r'^.*explanation\s*[:\*]*\s*', caseSensitive: false), '').trim();
        }
      }

      if (questionText.isNotEmpty && options.isNotEmpty) {
        mcqs.add(ParsedMcq(
          question: questionText,
          options: options,
          correctAnswer: correctAnswer,
          explanation: explanation,
        ));
      }
    }

    return mcqs;
  }
}
