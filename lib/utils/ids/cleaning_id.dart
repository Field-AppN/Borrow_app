// lib/utils/ids/cleaning_id.dart
// รูปแบบ: วันที่-เดือน-ปี-เวลา(ปัจจุบัน)-item-requester

import '_id_common.dart';

String buildCleaningDocId({
  required String item,
  required String requester,
}) {
  final now = nowThai();
  final day  = pad2(now.day);
  final mon  = thMonths[now.month - 1];
  final year = '${now.year}';
  final hh   = pad2(now.hour), mm = pad2(now.minute), ss = pad2(now.second);

  final it  = sanitize(item).isEmpty      ? '-' : sanitize(item);
  final req = sanitize(requester).isEmpty ? '-' : sanitize(requester);

  return '$day-$mon-$year $hh:$mm:$ss $it $req';
}
