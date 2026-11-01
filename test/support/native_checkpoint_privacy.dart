import 'dart:convert';

String nativeSnapshotWithoutPrivateSlots(Map<String, List<String>> snapshot) =>
    jsonEncode({
      for (final entry in snapshot.entries)
        entry.key: [
          for (final encoded in entry.value)
            () {
              final row = (jsonDecode(encoded) as Map).cast<String, Object?>();
              if (entry.key == 'learning_sessions' &&
                  row['accepted_plan_id'] is String &&
                  (row['accepted_plan_id']! as String).startsWith(
                    'native-plan-v1:',
                  )) {
                row.remove('accepted_plan_json');
                row.remove('checkpoint_json');
              }
              return row;
            }(),
        ],
    });
