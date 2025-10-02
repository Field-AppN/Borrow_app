// รูปแบบ: วันที่-เดือน-ปี-เวลา(ปัจจุบัน)-สถานที่-Serial

import '_id_common.dart';

String buildInfusionDocId({
  required String location,
  required String serial,
}) {
  final now = nowThai();
  final day  = pad2(now.day);
  final mon  = thMonths[now.month - 1];
  final year = '${now.year}';
  final hh   = pad2(now.hour), mm = pad2(now.minute), ss = pad2(now.second);

  final loc = sanitize(location).isEmpty ? '-' : sanitize(location);
  final sn  = sanitize(serial).isEmpty   ? '-' : sanitize(serial);

  return '$day-$mon-$year $hh:$mm:$ss $loc $sn';
}
