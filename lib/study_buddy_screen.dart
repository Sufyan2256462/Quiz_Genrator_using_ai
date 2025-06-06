import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Replace with your actual OpenRouter/OpenAI API Key
// WARNING: Hardcoding API keys in client-side code is NOT recommended for production apps.
// Use a backend or Firebase Functions to proxy API calls securely.
const String openRouterApiKey = "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";
const String openAIApiUrl = "https://openrouter.ai/api/v1/chat/completions"; // OpenRouter endpoint

class StudyBuddyScreen extends StatefulWidget {
  @override
  _StudyBuddyScreenState createState() => _StudyBuddyScreenState();
}

class _StudyBuddyScreenState extends State<StudyBuddyScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _notesController = TextEditingController();

  String _summary = "";
  List<Map<String, String>> _quizQuestions = []; // Store generated quiz questions with Q&A

  bool _isLoadingSummary = false;
  bool _isLoadingQuiz = false;
  bool _showQuiz = false; // Add this to control quiz visibility

  User? _user; // To hold the currently logged-in user

  List<Map<String, dynamic>> _userQuizResults = [];

  @override
  void initState() {
    super.initState();
    // Listen for authentication state changes
    _auth.authStateChanges().listen((user) {
      setState(() {
        _user = user;
      });
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  // --- Authentication Methods (Basic) ---
  void _signInAnonymously() async {
    try {
      await _auth.signInAnonymously();
    } catch (e) {
      _showSnackBar("Error signing in: ${e.toString()}");
    }
  }

  void _signOut() async {
    try {
      await _auth.signOut();
       _showSnackBar("Signed out successfully.");
    } catch (e) {
      _showSnackBar("Error signing out: ${e.toString()}");
    }
  }

  // --- AI Interaction Methods ---
  Future<void> _generateSummary() async {
    if (_notesController.text.isEmpty) {
       _showSnackBar("Please enter some notes to summarize.");
       return;
    }

    setState(() {
      _isLoadingSummary = true;
      _summary = ""; // Clear previous summary
    });

    try {
      final response = await http.post(
        Uri.parse(openAIApiUrl),
        headers: {
          'Authorization': 'Bearer $openRouterApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo', // Or another suitable model
          'messages': [
            {"role": "system", "content": "Summarize the following text concisely."},
            {"role": "user", "content": _notesController.text},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _summary = data['choices'][0]['message']['content'].trim();
        });
        if (_user != null) {
           _saveSummaryToFirestore(_notesController.text, _summary); // Save to Firestore
        }
      } else {
         _showSnackBar("Error generating summary: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
       _showSnackBar("Network error generating summary: ${e.toString()}");
    } finally {
      setState(() {
        _isLoadingSummary = false;
      });
    }
  }

  Future<void> _generateQuiz() async {
     if (_notesController.text.isEmpty) {
       _showSnackBar("Please enter some notes to generate a quiz from.");
       return;
    }

    setState(() {
      _isLoadingQuiz = true;
      _quizQuestions = []; // Clear previous questions
    });

    try {
      // Modified prompt to request structured Q&A
      final response = await http.post(
        Uri.parse(openAIApiUrl),
        headers: {
          'Authorization': 'Bearer $openRouterApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo', // Or another suitable model
          'messages': [
            {"role": "system", "content": "Generate 5 multiple-choice or short-answer quiz questions based on the following text. Provide the answer immediately after each question, clearly labeled (e.g., Q: What is...? A: ...)."},
            {"role": "user", "content": _notesController.text},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final quizText = data['choices'][0]['message']['content'].trim();

        // Basic parsing for Q&A format (Q: ... A: ...)
        final lines = quizText.split('\n').where((String l) => l.isNotEmpty).toList();
        List<Map<String, String>> parsedQuestions = [];
        String? currentQuestion;
        String? currentAnswer; // Use a separate variable for the current answer

        for (final line in lines) {
          if (line.startsWith('Q:')) {
            // If we have a complete Q&A pair, add it to the list
            if (currentQuestion != null && currentAnswer != null) {
               parsedQuestions.add({
                 'question': currentQuestion.trim(), // Trim question
                 'answer': currentAnswer.trim(), // Trim answer
               });
            }
            currentQuestion = line.substring(2).trim();
            currentAnswer = null; // Reset answer for the new question
          } else if (line.startsWith('A:') && currentQuestion != null) {
             currentAnswer = line.substring(2).trim();
             // If we have both Q and A, add the pair
             if (currentQuestion != null && currentAnswer != null) {
                parsedQuestions.add({
                  'question': currentQuestion.trim(),
                  'answer': currentAnswer.trim(),
                });
               currentQuestion = null; // Reset for the next pair
               currentAnswer = null; // Reset for the next pair
            }
          }
           else if (currentQuestion != null) { // Handle multi-line questions (basic)
               currentQuestion += '\n' + line.trim();
          } else if (currentAnswer != null) { // Handle multi-line answers (basic)
              currentAnswer += '\n' + line.trim();
          }
        }
         // Add the last Q&A pair if incomplete or pending
         if (currentQuestion != null && currentAnswer != null) {
            parsedQuestions.add({
              'question': currentQuestion.trim(),
              'answer': currentAnswer.trim(),
            });
         }


        setState(() {
           _quizQuestions = parsedQuestions;
        });

        if (_user != null) {
           _saveQuizToFirestore(_notesController.text, quizText); // Save raw quiz text to Firestore
        }
      } else {
         _showSnackBar("Error generating quiz: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
       _showSnackBar("Network error generating quiz: ${e.toString()}");
    } finally {
      setState(() {
        _isLoadingQuiz = false;
      });
    }
  }

  // --- Firestore Methods ---
  void _saveSummaryToFirestore(String notes, String summary) async {
     if (_user == null) return; // Only save if user is logged in
     try {
       await _firestore.collection('users').doc(_user!.uid).collection('studySessions').add({
         'notes': notes,
         'summary': summary,
         'timestamp': FieldValue.serverTimestamp(),
       });
       // Optional: Show a confirmation
       // _showSnackBar("Summary saved to Firestore.");
     } catch (e) {
       _showSnackBar("Error saving summary to Firestore: ${e.toString()}");
     }
  }

   void _saveQuizToFirestore(String notes, String quiz) async {
     if (_user == null) return; // Only save if user is logged in
     try {
       await _firestore.collection('users').doc(_user!.uid).collection('quizzes').add({
         'notes': notes,
         'quiz': quiz, // Store raw quiz text as a single string
         'timestamp': FieldValue.serverTimestamp(),
       });
       // Optional: Show a confirmation
       // _showSnackBar("Quiz saved to Firestore.");
     } catch (e) {
       _showSnackBar("Error saving quiz to Firestore: ${e.toString()}");
     }
  }

  void _saveQuizAttemptToFirestore() async {
    if (_user == null) return;
    try {
      await _firestore.collection('users').doc(_user!.uid).collection('quizAttempts').add({
        'quiz': _quizQuestions,
        'userAnswers': _userQuizResults,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _showSnackBar("Quiz attempt saved!");
      setState(() {
        _showQuiz = false;
        _userQuizResults = [];
      });
    } catch (e) {
      _showSnackBar("Error saving quiz attempt: "+ e.toString());
    }
  }

  // --- Utility for SnackBar ---
  void _showSnackBar(String message) {
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(message)),
       );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check authentication state
    if (_user == null) {
      // Show authentication screen/widgets
      return Scaffold(
        appBar: AppBar(
          title: Text('Study Buddy'),
          elevation: 4.0, // Add subtle shadow
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_outline, size: 80, color: Colors.blueGrey[400]), // Add an icon
              SizedBox(height: 20),
              Text('Please sign in to use the Study Buddy.', style: TextStyle(fontSize: 18)),
              SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _signInAnonymously, // Using anonymous sign-in for simplicity
                icon: Icon(Icons.login),
                label: Text('Sign In Anonymously'),
                 style: ElevatedButton.styleFrom(
                   padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12)
                 )
              ),
              // Add options for email/password or Google Sign-In here if needed
            ],
          ),
        ),
      );
    } else {
      // Show main Study Buddy features for logged-in user
      return Scaffold(
        appBar: AppBar(
          title: Text('Study Buddy - Logged in'),
          elevation: 4.0, // Add subtle shadow
          actions: [
            IconButton(
              icon: Icon(Icons.logout),
              tooltip: 'Sign Out',
              onPressed: _signOut,
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView( // Use ListView for scrollability
            children: [
              Text('Study Notes', style: Theme.of(context).textTheme.headlineSmall), // Section Title
              SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 10, // Allow multiple lines for notes
                decoration: InputDecoration(
                  hintText: 'Enter or paste your study notes here',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  filled: true,
                  fillColor: Colors.blueGrey[50],
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded( // Use Expanded to make buttons take available space
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ElevatedButton(
                        onPressed: _isLoadingSummary ? null : _generateSummary,
                        child: _isLoadingSummary
                            ? SizedBox( // Use SizedBox for consistent size
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
                              )
                            : Text('Summarize'),
                         style: ElevatedButton.styleFrom(
                           padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)), // Rounded corners
                         ),
                      ),
                    ),
                  ),
                   Expanded( // Use Expanded to make buttons take available space
                     child: Padding(
                       padding: const EdgeInsets.symmetric(horizontal: 4.0),
                       child: ElevatedButton(
                         onPressed: _isLoadingQuiz ? null : () async {
                           await _generateQuiz();
                           setState(() {
                             _showQuiz = false; // Hide quiz until Take Quiz is pressed
                           });
                         },
                         child: _isLoadingQuiz
                             ? SizedBox( // Use SizedBox for consistent size
                                 width: 20,
                                 height: 20,
                                 child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
                               )
                             : Text('Generate Quiz'),
                           style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 12),
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)), // Rounded corners
                           ),
                       ),
                     ),
                   ),
                   Expanded(
                     child: Padding(
                       padding: const EdgeInsets.symmetric(horizontal: 4.0),
                       child: ElevatedButton(
                         onPressed: _quizQuestions.isNotEmpty ? () {
                           setState(() {
                             _showQuiz = true;
                           });
                         } : null,
                         child: Text('Take Quiz'),
                         style: ElevatedButton.styleFrom(
                           padding: EdgeInsets.symmetric(vertical: 12),
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                         ),
                       ),
                     ),
                   ),
                ],
              ),
              SizedBox(height: 30),

              // Display Summary
              if (_summary.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Text('Summary', style: Theme.of(context).textTheme.headlineSmall), // Section Title
                     SizedBox(height: 8),
                     Card(
                        elevation: 2.0,
                        margin: EdgeInsets.symmetric(vertical: 8.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)), // Rounded corners
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text(_summary),
                        ),
                      ),
                      SizedBox(height: 20),
                  ],
                ),

              // Display Quiz Questions with answer input and feedback
              if (_quizQuestions.isNotEmpty && _showQuiz)
                 Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                      Text('Quiz Questions', style: Theme.of(context).textTheme.headlineSmall), // Section Title
                      SizedBox(height: 8),
                      ListView.builder(
                         shrinkWrap: true,
                         physics: NeverScrollableScrollPhysics(), // Disable scrolling for nested ListView
                         itemCount: _quizQuestions.length,
                         itemBuilder: (context, index) {
                           final qna = _quizQuestions[index];
                           // Ensure _userQuizResults has the right length
                           if (_userQuizResults.length < _quizQuestions.length) {
                             _userQuizResults = List.generate(_quizQuestions.length, (i) => {'userAnswer': '', 'isCorrect': false});
                           }
                           return QuizQuestionWidget(
                             question: qna['question'] ?? '',
                             answer: qna['answer'] ?? '',
                             onAnswered: (userAnswer, isCorrect) {
                               setState(() {
                                 _userQuizResults[index] = {
                                   'question': qna['question'] ?? '',
                                   'correctAnswer': qna['answer'] ?? '',
                                   'userAnswer': userAnswer,
                                   'isCorrect': isCorrect,
                                 };
                               });
                             },
                           );
                         },
                      ),
                      SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _userQuizResults.where((r) => r['userAnswer'] == '').isEmpty ? _saveQuizAttemptToFirestore : null,
                        child: Text('Submit Quiz'),
                      ),
                      SizedBox(height: 20),
                   ],
                 ),

              // Display Past Sessions (Summaries and Quizzes)
              Text('Past Sessions', style: Theme.of(context).textTheme.headlineSmall), // Section Title
              SizedBox(height: 8),

              // StreamBuilder for past Study Sessions (Summaries)
              StreamBuilder<QuerySnapshot>(
                 stream: _user != null
                     ? _firestore.collection('users').doc(_user!.uid).collection('studySessions').orderBy('timestamp', descending: true).snapshots()
                     : Stream.empty(), // Empty stream if user is not logged in
                 builder: (context, snapshot) {
                   if (snapshot.connectionState == ConnectionState.waiting) {
                     return Center(child: CircularProgressIndicator());
                   }
                   if (snapshot.hasError) {
                     return Text('Error loading summaries: ${snapshot.error}', style: TextStyle(color: Colors.red));
                   }
                   if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                     return Text('No past summaries.');
                   }

                   final summaries = snapshot.data!.docs;
                   return ListView.builder(
                     shrinkWrap: true,
                     physics: NeverScrollableScrollPhysics(),
                     itemCount: summaries.length,
                     itemBuilder: (context, index) {
                       final summaryData = summaries[index].data() as Map<String, dynamic>;
                       final timestamp = summaryData['timestamp'] as Timestamp?;
                       final formattedTimestamp = timestamp != null
                           ? timestamp.toDate().toString().split('.')[0] // Corrected conversion
                           : 'N/A';

                       return Card(
                         elevation: 1.0,
                         margin: EdgeInsets.symmetric(vertical: 4.0),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)), // Rounded corners
                         child: ListTile(
                           title: Text('Summary from $formattedTimestamp'),
                           subtitle: Text(summaryData['summary'] ?? 'No summary content', maxLines: 2, overflow: TextOverflow.ellipsis),
                            // onTap: () { /* TODO: Implement navigation to view full summary */ },
                         ),
                       );
                     },
                   );
                 },
              ),
               SizedBox(height: 10), // Spacing between summaries and quizzes
              // StreamBuilder for past Quizzes
               StreamBuilder<QuerySnapshot>(
                 stream: _user != null
                     ? _firestore.collection('users').doc(_user!.uid).collection('quizzes').orderBy('timestamp', descending: true).snapshots()
                     : Stream.empty(), // Empty stream if user is not logged in
                 builder: (context, snapshot) {
                   if (snapshot.connectionState == ConnectionState.waiting) {
                     return Center(child: CircularProgressIndicator());
                   }
                    if (snapshot.hasError) {
                     return Text('Error loading quizzes: ${snapshot.error}', style: TextStyle(color: Colors.red));
                   }
                   if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                     return Text('No past quizzes.');
                   }

                   final quizzes = snapshot.data!.docs;
                   return ListView.builder(
                     shrinkWrap: true,
                     physics: NeverScrollableScrollPhysics(),
                     itemCount: quizzes.length,
                     itemBuilder: (context, index) {
                       final quizData = quizzes[index].data() as Map<String, dynamic>;
                        final timestamp = quizData['timestamp'] as Timestamp?;
                       final formattedTimestamp = timestamp != null
                           ? timestamp.toDate().toString().split('.')[0] // Corrected conversion
                           : 'N/A';
                       return Card(
                         elevation: 1.0,
                         margin: EdgeInsets.symmetric(vertical: 4.0),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)), // Rounded corners
                         child: ListTile(
                           title: Text('Quiz from $formattedTimestamp'),
                            subtitle: Text(quizData['quiz'] ?? 'No quiz content', maxLines: 2, overflow: TextOverflow.ellipsis),
                            // onTap: () { /* TODO: Implement navigation to view full quiz */ },
                         ),
                       );
                     },
                   );
                 },
              ),

            ],
          ),
        ),
      );
    }
  }
}

class QuizQuestionWidget extends StatefulWidget {
  final String question;
  final String answer;
  final void Function(String userAnswer, bool isCorrect) onAnswered;

  QuizQuestionWidget({required this.question, required this.answer, required this.onAnswered});

  @override
  _QuizQuestionWidgetState createState() => _QuizQuestionWidgetState();
}

class _QuizQuestionWidgetState extends State<QuizQuestionWidget> {
  final TextEditingController _controller = TextEditingController();
  bool _submitted = false;
  bool _isCorrect = false;

  void _submit() {
    setState(() {
      _submitted = true;
      _isCorrect = _controller.text.trim().toLowerCase() == widget.answer.trim().toLowerCase();
    });
    widget.onAnswered(_controller.text, _isCorrect);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.question, style: TextStyle(fontWeight: FontWeight.bold)),
            if (!_submitted)
              TextField(
                controller: _controller,
                decoration: InputDecoration(labelText: 'Your Answer'),
              ),
            if (!_submitted)
              ElevatedButton(
                onPressed: _submit,
                child: Text('Submit'),
              ),
            if (_submitted)
              Text(
                _isCorrect ? 'Correct!' : 'Incorrect. Correct answer: \'${widget.answer}\'',
                style: TextStyle(
                  color: _isCorrect ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
} 