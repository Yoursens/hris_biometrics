// lib/data/local/dao/sync_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart'; // Added for debugPrint
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/database_service.dart';
import 'connectivity_service.dart';

enum SyncStatus { pending, syncing, synced, failed }
enum SyncType { clockIn, clockOut }

class SyncRecord {
  final String id;
  final SyncType type;
  final Map<String, dynamic> payload;
  final SyncStatus status;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? lastAttempt;
  final String? errorMessage;

  SyncRecord({
    required this.id,
    required this.type,
    required this.payload,
    required this.status,
    required this.retryCount,
    required this.createdAt,
    this.lastAttempt,
    this.errorMessage,
  });

  factory SyncRecord.fromMap(Map<String, dynamic> m) => SyncRecord(
    id: m['id'],
    type: SyncType.values.firstWhere((t) => t.name == m['type'],
        orElse: () => SyncType.clockIn),
    payload: jsonDecode(m['payload'] as String),
    status: SyncStatus.values.firstWhere((s) => s.name == m['status'],
        orElse: () => SyncStatus.pending),
    retryCount: (m['retry_count'] as int?) ?? 0,
    createdAt: DateTime.parse(m['created_at'] as String),
    lastAttempt: m['last_attempt'] != null
        ? DateTime.parse(m['last_attempt'] as String)
        : null,
    errorMessage: m['error_message'] as String?,
  );
}

class SyncEvent {
  final SyncEventType type;
  final int pendingCount;
  final int syncedCount;
  final String? message;

  SyncEvent({
    required this.type,
    this.pendingCount = 0,
    this.syncedCount = 0,
    this.message,
  });
}

enum SyncEventType {
  wentOffline,
  wentOnline,
  syncing,
  syncDone,
  syncFailed,
  queued
}

class SyncService {
  static SyncService? _instance;
  SyncService._();
  static SyncService get instance => _instance ??= SyncService._();

  final _uuid = const Uuid();
  StreamSubscription? _connectivitySub;
  bool _isSyncing = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final _eventController = StreamController<SyncEvent>.broadcast();
  Stream<SyncEvent> get events => _eventController.stream;

  // ── Init ─────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await _ensureTable();

    // Fix any records stuck in 'syncing' state from a previous crash
    await _resetStuckRecords();

    _connectivitySub =
        ConnectivityService.instance.onStatusChange.listen((online) async {
          if (online) {
            _eventController.add(SyncEvent(
                type: SyncEventType.wentOnline,
                message: 'Back online — uploading pending records...'));
            await syncPending();
          } else {
            final pending = await getPendingCount();
            _eventController.add(SyncEvent(
                type: SyncEventType.wentOffline,
                pendingCount: pending,
                message: 'Offline mode active'));
          }
        });

    // Try sync on startup if online
    if (ConnectivityService.instance.isOnline) {
      await syncPending();
    }
  }

  Future<void> _ensureTable() async {
    final db = await DatabaseService.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        retry_count INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        last_attempt TEXT,
        error_message TEXT
      )
    ''');
  }

  /// Resets any records that got stuck in 'syncing' due to a crash/force-close
  Future<void> _resetStuckRecords() async {
    final db = await DatabaseService.instance.database;
    await db.update(
      'sync_queue',
      {'status': SyncStatus.pending.name},
      where: "status = 'syncing'",
    );
  }

  void dispose() {
    _connectivitySub?.cancel();
    _eventController.close();
  }

  // ── Enqueue ───────────────────────────────────────────────────────────────

  /// Saves record to SQLite queue. Immediately syncs if online.
  Future<String> enqueue(SyncType type, Map<String, dynamic> payload) async {
    final db = await DatabaseService.instance.database;
    final id = _uuid.v4();
    await db.insert('sync_queue', {
      'id': id,
      'type': type.name,
      'payload': jsonEncode(payload),
      'status': SyncStatus.pending.name,
      'retry_count': 0,
      'created_at': DateTime.now().toIso8601String(),
    });

    final pending = await getPendingCount();
    _eventController.add(SyncEvent(
      type: SyncEventType.queued,
      pendingCount: pending,
      message: ConnectivityService.instance.isOnline
          ? 'Saved — uploading to server...'
          : 'Saved to device — will sync when online',
    ));

    if (ConnectivityService.instance.isOnline) {
      await syncPending();
    }

    return id;
  }

  // ── Sync ──────────────────────────────────────────────────────────────────

  Future<void> syncPending() async {
    if (_isSyncing) return;
    if (!ConnectivityService.instance.isOnline) return;

    final db = await DatabaseService.instance.database;

    // Only pick pending records (not failed — those stay until manually retried)
    final rows = await db.query(
      'sync_queue',
      where: "status = 'pending'",
      orderBy: 'created_at ASC',
    );

    if (rows.isEmpty) {
      // Clear the badge — nothing left to sync
      _eventController.add(SyncEvent(
        type: SyncEventType.syncDone,
        syncedCount: 0,
        pendingCount: 0,
      ));
      return;
    }

    _isSyncing = true;
    _eventController.add(SyncEvent(
      type: SyncEventType.syncing,
      pendingCount: rows.length,
      message: 'Syncing ${rows.length} record(s)...',
    ));

    int success = 0;
    int failed = 0;

    try {
      for (final row in rows) {
        final record = SyncRecord.fromMap(row);

        await db.update(
          'sync_queue',
          {
            'status': SyncStatus.syncing.name,
            'last_attempt': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [record.id],
        );

        try {
          // ── Upload to Firebase Firestore ─────────────────────────────────
          final uploaded = await _uploadToServer(record);

          if (uploaded) {
            await db.update(
              'sync_queue',
              {'status': SyncStatus.synced.name},
              where: 'id = ?',
              whereArgs: [record.id],
            );
            success++;
          } else {
            await _markFailed(db, record, 'Firebase rejected the record');
            failed++;
          }
        } catch (e) {
          await _markFailed(db, record, e.toString());
          failed++;
        }
      }
    } finally {
      _isSyncing = false;
    }

    final remaining = await getPendingCount();

    _eventController.add(SyncEvent(
      type: success > 0 ? SyncEventType.syncDone : SyncEventType.syncFailed,
      syncedCount: success,
      pendingCount: remaining,
      message: success > 0
          ? '$success record(s) saved to Firebase ✓'
          : 'Sync failed — tap Retry in queue',
    ));

    if (success > 0) await _cleanup(db);
  }

  /// Uploads attendance records to Firebase Firestore
  Future<bool> _uploadToServer(SyncRecord record) async {
    try {
      final collection = record.type == SyncType.clockIn ? 'clock_ins' : 'clock_outs';
      
      // Add record to Firestore
      await _firestore.collection(collection).doc(record.id).set({
        ...record.payload,
        'sync_id': record.id,
        'synced_at': FieldValue.serverTimestamp(),
      });
      
      return true;
    } catch (e) {
      debugPrint('Firestore upload error: $e');
      return false;
    }
  }

  Future<void> _markFailed(
      Database db, SyncRecord record, String error) async {
    // Mark permanently failed — won't auto-retry, user must tap Retry
    await db.update(
      'sync_queue',
      {
        'status': SyncStatus.failed.name,
        'retry_count': record.retryCount + 1,
        'error_message': error,
        'last_attempt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<void> _cleanup(Database db) async {
    // Keep synced records for 7 days, then auto-delete
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 7))
        .toIso8601String();
    await db.delete(
      'sync_queue',
      where: "status = 'synced' AND created_at < ?",
      whereArgs: [cutoff],
    );
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  Future<int> getPendingCount() async {
    final db = await DatabaseService.instance.database;
    final r = await db.rawQuery(
        "SELECT COUNT(*) as c FROM sync_queue WHERE status = 'pending'");
    return (r.first['c'] as int?) ?? 0;
  }

  Future<List<SyncRecord>> getRecentQueue({int limit = 30}) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query('sync_queue',
        orderBy: 'created_at DESC', limit: limit);
    return rows.map(SyncRecord.fromMap).toList();
  }

  /// Resets all FAILED records back to pending and retries immediately
  Future<void> retryFailed() async {
    final db = await DatabaseService.instance.database;
    await db.update(
      'sync_queue',
      {
        'status': SyncStatus.pending.name,
        'retry_count': 0,
        'error_message': null,
      },
      where: "status = 'failed'",
    );
    await syncPending();
  }

  /// Clears all synced records from the queue (housekeeping)
  Future<void> clearSynced() async {
    final db = await DatabaseService.instance.database;
    await db.delete('sync_queue', where: "status = 'synced'");
  }
}
