// ฟังก์ชัน/ค่าร่วมที่ใช้สร้าง Document ID

String pad2(int n) => n.toString().padLeft(2, '0');

const thMonths = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];

String sanitize(String s) =>
    s.trim().replaceAll('/', '-').replaceAll(RegExp(r'\s+'), ' ');

// เวลาไทย (UTC+7)
DateTime nowThai() => DateTime.now().toUtc().add(const Duration(hours: 7));
