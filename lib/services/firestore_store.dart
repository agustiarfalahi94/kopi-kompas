import 'package:cloud_firestore/cloud_firestore.dart';

import 'backup_service.dart';

/// The real Firestore, behind [RemoteStore]'s four methods.
///
/// The path shape `/users/{uid}/brews/{id}` is not cosmetic: it is what
/// `firestore.rules` matches on to make "only your own data" enforceable on
/// the server. Changing it here without changing the rules would open the
/// database.
class FirestoreStore implements RemoteStore {
  FirestoreStore([FirebaseFirestore? db])
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _brews(String uid) =>
      _db.collection('users').doc(uid).collection('brews');

  @override
  Future<void> put(String uid, String id, Map<String, Object?> data) =>
      _brews(uid).doc(id).set(data);

  @override
  Future<List<Map<String, Object?>>> all(String uid) async {
    final snap = await _brews(uid).get();
    return snap.docs.map((d) => d.data()).toList();
  }

  @override
  Future<void> delete(String uid, String id) => _brews(uid).doc(id).delete();
}
