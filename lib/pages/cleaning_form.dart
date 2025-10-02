import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/ids/cleaning_id.dart';    // <- ฟังก์ชันสร้าง Document ID
import 'responsive.dart';

class CleaningForm extends StatefulWidget {
  const CleaningForm({super.key});

  @override
  State<CleaningForm> createState() => _CleaningFormState();
}

class _CleaningFormState extends State<CleaningForm> {
  final _formKey = GlobalKey<FormState>();

  final controllers = {
    'Item': TextEditingController(),
    'Total': TextEditingController(),
    'Taken': TextEditingController(),
    'Requester': TextEditingController(), // คง key เดิมไว้ เพื่อไม่กระทบระบบอื่น
  };

  DateTime? _borrowDate; // วันที่เบิก
  double progressValue = 0.0;
  bool isLoading = false;

  // --- TextField สไตล์เดียวกับหน้าอื่น ---
  Widget buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool isNumber = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        validator: (v) => v == null || v.isEmpty ? 'กรุณากรอก $label' : null,
        onChanged: (_) => updateProgress(),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(icon, color: Colors.blue),
          labelText: label,
          labelStyle: const TextStyle(color: Colors.black87),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black26),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.blue, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
        ),
      ),
    );
  }

  // --- Progress ---
  void updateProgress() {
    int total = 5; // 4 ช่อง + วันที่เบิก
    int filled = controllers.values.where((c) => c.text.isNotEmpty).length;
    if (_borrowDate != null) filled++;
    setState(() => progressValue = filled / total);
  }

  // --- เลือกวันที่เบิก ---
  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _borrowDate = picked;
        updateProgress();
      });
    }
  }

  // --- บันทึก (ใช้ custom Document ID) ---
  Future<void> _saveData() async {
    if (!(_formKey.currentState?.validate() ?? false) || _borrowDate == null) {
      _showPopup("กรุณากรอกข้อมูลให้ครบถ้วน", false);
      return;
    }
    try {
      setState(() => isLoading = true);

      final docId = buildCleaningDocId(
        item: controllers['Item']!.text.trim(),
        requester: controllers['Requester']!.text.trim(),
      );

      await FirebaseFirestore.instance
          .collection('Cleaning Supplies')
          .doc(docId) // <-- ตั้ง Document ID เอง
          .set({
        'Item'       : controllers['Item']!.text.trim(),
        'Total'      : int.tryParse(controllers['Total']!.text) ?? 0,
        'Taken'      : int.tryParse(controllers['Taken']!.text) ?? 0,
        'Requester'  : controllers['Requester']!.text.trim(), // ชื่อฟิลด์ใน DB คงเดิม
        'borrow_date': _borrowDate,
        'createdAt'  : FieldValue.serverTimestamp(),
      });

      setState(() => isLoading = false);
      _showPopup("บันทึกข้อมูลเรียบร้อยแล้ว", true);

      // เคลียร์ฟอร์ม
      for (final c in controllers.values) c.clear();
      _borrowDate = null;
      updateProgress();
    } catch (e) {
      setState(() => isLoading = false);
      _showPopup("เกิดข้อผิดพลาด: $e", false);
    }
  }

  void _showPopup(String msg, bool success) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            Icon(success ? Icons.check_circle : Icons.warning,
                color: success ? Colors.green : Colors.red, size: 28),
            const SizedBox(width: 10),
            Text(success ? "สำเร็จ!" : "เกิดข้อผิดพลาด",
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ตกลง")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tablet = isTablet(context);
    const gap = 12.0;

    Widget twoCol(Widget a, Widget b) => Row(
      children: [Expanded(child: a), const SizedBox(width: gap), Expanded(child: b)],
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF002366),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Cleaning Supplies Form",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
      body: CenteredBody(
        child: Padding(
          padding: responsivePagePadding(context),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Progress bar สีแดง
                  LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 6,
                    backgroundColor: Colors.grey[300],
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),

                  if (!tablet) ...[
                    buildTextField(label: "Item", controller: controllers['Item']!, icon: Icons.cleaning_services),
                    buildTextField(label: "Total", controller: controllers['Total']!, icon: Icons.numbers, isNumber: true),
                    buildTextField(label: "Taken", controller: controllers['Taken']!, icon: Icons.remove_circle, isNumber: true),
                    // เปลี่ยนป้ายเป็น Borrower (คง controller เดิม)
                    buildTextField(label: "Borrower", controller: controllers['Requester']!, icon: Icons.person),
                  ] else ...[
                    twoCol(
                      buildTextField(label: "Item", controller: controllers['Item']!, icon: Icons.cleaning_services),
                      buildTextField(label: "Total", controller: controllers['Total']!, icon: Icons.numbers, isNumber: true),
                    ),
                    const SizedBox(height: gap),
                    twoCol(
                      buildTextField(label: "Taken", controller: controllers['Taken']!, icon: Icons.remove_circle, isNumber: true),
                      // เปลี่ยนป้ายเป็น Borrower (คง controller เดิม)
                      buildTextField(label: "Borrower", controller: controllers['Requester']!, icon: Icons.person),
                    ),
                  ],

                  const SizedBox(height: 10),

                  // เปลี่ยนข้อความปุ่มเลือกวันที่เป็น Borrow date
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.calendar_month, color: Colors.blue),
                      label: Text(
                        _borrowDate == null
                            ? "Borrow date"
                            : "Borrow date: ${_borrowDate!.day}/${_borrowDate!.month}/${_borrowDate!.year}",
                      ),
                      onPressed: () => _selectDate(context),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // เปลี่ยนข้อความปุ่มเป็น Save
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _saveData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text("Save",
                          style: TextStyle(fontSize: 18, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
