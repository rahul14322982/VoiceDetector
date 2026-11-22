import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Register a new user
  Future<UserCredential> register(
    String email,
    String password,
  ) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  // Sign in an existing user
  Future<UserCredential> login(
    String email,
    String password,
  ) async {
    return await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  // Sign out
  Future<void> logout() async {
    await _auth.signOut();
  }

  // Save a completed audio analysis
  Future<void> saveAnalysis({
    required String filename,
    required double aiScore,
    required String result,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('Please log in first.');
    }

    await _db.collection('analysis').add({
      'userId': user.uid,
      'filename': filename,
      'aiScore': aiScore,
      'result': result,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // Load the current user's analysis history
  Future<List<Map<String, dynamic>>> loadRecentAnalysis() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('Please log in first.');
    }

    final snapshot = await _db
        .collection('analysis')
        .where('userId', isEqualTo: user.uid)
        .get();

    final records = snapshot.docs.map((doc) {
      return {
        'id': doc.id,
        ...doc.data(),
      };
    }).toList();

    records.sort((a, b) {
      final aTime = a['timestamp'] as Timestamp?;
      final bTime = b['timestamp'] as Timestamp?;

      if (aTime == null) return 1;
      if (bTime == null) return -1;

      return bTime.compareTo(aTime);
    });

    return records;
  }
}