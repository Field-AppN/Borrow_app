// lib/utils/ids/master_id.dart
// รูปแบบ: วันที่-เดือน-ปี-เวลา(ปัจจุบัน)-สถานที่-โค้ดอุปกรณ์

import '_id_common.dart';

String buildMastersDocId({
  required String location,
  required String equipmentCode,
}) {
  final now = nowThai();
  final day  = pad2(now.day);
  final mon  = thMonths[now.month - 1];
  final year = '${now.year}';
  final hh   = pad2(now.hour), mm = pad2(now.minute), ss = pad2(now.second);

  final loc  = sanitize(location).isEmpty ? '-' : sanitize(location);
  final code = sanitize(equipmentCode).isEmpty ? '-' : sanitize(equipmentCode);

  return '$day-$mon-$year $hh:$mm:$ss $loc $code';
}
