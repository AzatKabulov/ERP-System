import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'intake_models.dart';

/// Keeps the goods being counted on the device, so a crash, a dead battery or a closed app
/// never loses a box that took a quarter of an hour to scan. One draft per person and business.
class IntakeDraftStore {
  IntakeDraftStore(
    this._prefs, {
    required String businessId,
    required String userId,
  }) : _key = 'intake_draft_${businessId}_$userId';

  final SharedPreferences _prefs;
  final String _key;

  IntakeDraft? load() {
    final text = _prefs.getString(_key);
    if (text == null || text.isEmpty) return null;
    try {
      final draft = IntakeDraft.fromJson(
        (jsonDecode(text) as Map).cast<String, dynamic>(),
      );
      return draft.entries.isEmpty ? null : draft;
    } catch (_) {
      return null; // a damaged draft is dropped, never allowed to block the screen
    }
  }

  Future<void> save(IntakeDraft draft) async {
    if (draft.entries.isEmpty) {
      await _prefs.remove(_key);
    } else {
      await _prefs.setString(_key, jsonEncode(draft.toJson()));
    }
  }

  Future<void> clear() => _prefs.remove(_key);
}
