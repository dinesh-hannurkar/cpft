import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreSignalingService {
  final FirebaseFirestore _db;
  FirestoreSignalingService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  static const String _digits = '0123456789';
  // Avoid ambiguous characters for readability
  static const String _alpha = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  String _randomCode(int length, {bool alphanumeric = false, Random? rng}) {
    final rand = rng ?? Random();
    final chars = alphanumeric ? _alpha : _digits;
    final buf = StringBuffer();
    for (var i = 0; i < length; i++) {
      buf.write(chars[rand.nextInt(chars.length)]);
    }
    return buf.toString();
  }

  /// Generate an available room id and reserve it by creating the doc if free.
  /// Tries up to [maxAttempts] codes to avoid collisions.
  Future<String> createAutoRoomId({int length = 4, bool alphanumeric = false, int maxAttempts = 32}) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final id = _randomCode(length, alphanumeric: alphanumeric);
      final docRef = _db.collection('webrtc_rooms').doc(id);
      final snap = await docRef.get();
      if (!snap.exists) {
        await docRef.set({'createdAt': FieldValue.serverTimestamp(), 'auto': true});
        return id;
      }
      // If exists but appears stale (> 10 minutes old), allow reuse by resetting marker
      final data = snap.data();
      final ts = (data?['updatedAt'] ?? data?['createdAt']);
      if (ts is Timestamp) {
        final last = ts.toDate();
        if (DateTime.now().difference(last) > const Duration(minutes: 10)) {
          await docRef.set({'createdAt': FieldValue.serverTimestamp(), 'auto': true}, SetOptions(merge: true));
          return id;
        }
      }
      // else: try next id
    }
    // Fallback to a longer id if all attempts failed
    final fallback = _randomCode(length + 2, alphanumeric: alphanumeric);
    final docRef = _db.collection('webrtc_rooms').doc(fallback);
    await docRef.set({'createdAt': FieldValue.serverTimestamp(), 'auto': true});
    return fallback;
  }

  /// Creates/joins a signaling document. Returns a controller with streams.
  Future<FirestoreSession> createSession(String roomId) async {
    final docRef = _db.collection('webrtc_rooms').doc(roomId);
    await docRef.set({'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    final iceRef = docRef.collection('ice');
    return FirestoreSession(docRef, iceRef);
  }

  /// Convenience: create a new auto-generated room and return the session.
  Future<FirestoreSession> createAutoSession({int length = 4, bool alphanumeric = false}) async {
    final id = await createAutoRoomId(length: length, alphanumeric: alphanumeric);
    final docRef = _db.collection('webrtc_rooms').doc(id);
    final iceRef = docRef.collection('ice');
    return FirestoreSession(docRef, iceRef);
  }
}

class FirestoreSession {
  final DocumentReference<Map<String, dynamic>> doc;
  final CollectionReference<Map<String, dynamic>> ice;

  FirestoreSession(this.doc, this.ice);

  Stream<Map<String, dynamic>?> onOffer() => doc.snapshots().map((s) => s.data()?['offer'] as Map<String, dynamic>?);
  Stream<Map<String, dynamic>?> onAnswer() => doc.snapshots().map((s) => s.data()?['answer'] as Map<String, dynamic>?);
  Stream<QuerySnapshot<Map<String, dynamic>>> onIce() => ice.snapshots();

  Future<void> writeOffer(Map<String, dynamic> offer) => doc.set({'offer': offer, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  Future<void> writeAnswer(Map<String, dynamic> answer) => doc.set({'answer': answer, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  Future<void> addIce(Map<String, dynamic> candidate) => ice.add({
        'candidate': candidate,
        // Duplicate key fields at top-level for easier filtering
        'role': candidate['role'],
        'sessionId': candidate['sessionId'],
        'ts': FieldValue.serverTimestamp(),
      });

  Future<void> cleanup() async {
    // Optional: delete ICE candidates and mark doc for TTL (use Firestore TTL policies)
    final batch = doc.firestore.batch();
    final snaps = await ice.get();
    for (final d in snaps.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
    await doc.set({'completedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> deleteRoom() async {
    // Delete ICE subcollection and the room document entirely
    final snaps = await ice.get();
    for (final d in snaps.docs) {
      await d.reference.delete();
    }
    await doc.delete();
  }

  /// Clears any previous offer/answer and ICE, and sets a new sessionId.
  Future<void> resetForNewSession(String sessionId) async {
    // Delete all ICE candidates
    final snaps = await ice.get();
    for (final d in snaps.docs) {
      await d.reference.delete();
    }
    // Clear offer/answer and set new session metadata
    await doc.set({
      'offer': FieldValue.delete(),
      'answer': FieldValue.delete(),
      'sessionId': sessionId,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}