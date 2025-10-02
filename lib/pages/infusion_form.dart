import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/ids/infusion_id.dart';   // ฟังก์ชันสร้าง Document ID
import 'responsive.dart';

class InfusionForm extends StatefulWidget {
  const InfusionForm({Key? key}) : super(key: key);

  @override
  State<InfusionForm> createState() => _InfusionFormState();
}

class _InfusionFormState extends State<InfusionForm> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _brandController    = TextEditingController();
  final TextEditingController _serialController   = TextEditingController();
  final TextEditingController _typeController     = TextEditingController(); // ใช้กรอก "Model"
  final TextEditingController _borrowerController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();

  DateTime? _borrowDate;
  DateTime? _returnDate;
  double progressValue = 0.0;

  // ---- Progress bar (ตัด Note ออกแล้ว) ----
  void updateProgress() {
    int totalFields = 7; // 6 ช่องกรอก + 1 คู่วันที่
    int filled = 0;
    if (_brandController.text.isNotEmpty) filled++;
    if (_serialController.text.isNotEmpty) filled++;
    if (_typeController.text.isNotEmpty) filled++;     // Model
    if (_borrowerController.text.isNotEmpty) filled++;
    if (_locationController.text.isNotEmpty) filled++;
    if (_quantityController.text.isNotEmpty) filled++;
    if (_borrowDate != null && _returnDate != null) filled++;
    setState(() => progressValue = filled / totalFields);
  }

  // ---- เลือกวันที่ ----
  Future<void> _selectDate(BuildContext context, bool isBorrowDate) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (pickedDate != null) {
      setState(() {
        if (isBorrowDate) {
          _borrowDate = pickedDate;
        } else {
          _returnDate = pickedDate;
        }
        updateProgress();
      });
    }
  }

  // ---- Save (บันทึกทั้ง Type และ Model) ----
  Future<void> saveData() async {
    if (!(_formKey.currentState!.validate() &&
        _borrowDate != null &&
        _returnDate != null)) {
      _showErrorPopup();
      return;
    }

    try {
      final docId = buildInfusionDocId(
        location: _locationController.text.trim(),
        serial: _serialController.text.trim(),
      );

      await FirebaseFirestore.instance
          .collection('Infusion Pump')
          .doc(docId)
          .set({
        'Brand'      : _brandController.text.trim(),
        'Serial'     : _serialController.text.trim(),
        'Model'      : _typeController.text.trim(),   // <- ใช้ controller ตัวเดิมแต่ map เป็น Model
        'Borrower'   : _borrowerController.text.trim(),
        'Location'   : _locationController.text.trim(),
        'Quantity'   : _quantityController.text.trim(),
        'borrow_date': _borrowDate,
        'return_date': _returnDate,
        'timestamp'  : FieldValue.serverTimestamp(),
      });

      _showSuccessPopup();
    } catch (_) {
      _showErrorPopup();
    }
  }


  // ---- Popups ----
  void _showSuccessPopup() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Text("สำเร็จ!", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text("บันทึกข้อมูลเรียบร้อยแล้ว"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text("ตกลง"),
          ),
        ],
      ),
    );
  }

  void _showErrorPopup() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: const [
            Icon(Icons.warning, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Text("กรอกข้อมูลไม่ครบ!", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text("กรุณากรอกข้อมูลให้ครบถ้วนทุกช่อง"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ตกลง")),
        ],
      ),
    );
  }

  // ---- TextField UI ----
  Widget buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        onChanged: (_) => updateProgress(),
        validator: (v) => (v == null || v.isEmpty) ? 'กรุณากรอก $label' : null,
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
        title: const Text(
          "Infusion pump Form",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
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

                  // ===== ฟิลด์กรอก (ตัด Note ออก) =====
                  if (!tablet) ...[
                    buildTextField(label: "Brand",    controller: _brandController,    icon: Icons.edit),
                    buildTextField(label: "Serial",   controller: _serialController,   icon: Icons.qr_code),
                    buildTextField(label: "Model",    controller: _typeController,     icon: Icons.category),
                    buildTextField(label: "Borrower", controller: _borrowerController, icon: Icons.person),
                    buildTextField(label: "Location", controller: _locationController, icon: Icons.location_on),
                    buildTextField(label: "Quantity", controller: _quantityController, icon: Icons.numbers),
                  ] else ...[
                    twoCol(
                      buildTextField(label: "Brand",  controller: _brandController,  icon: Icons.edit),
                      buildTextField(label: "Serial", controller: _serialController, icon: Icons.qr_code),
                    ),
                    const SizedBox(height: gap),
                    twoCol(
                      buildTextField(label: "Model",    controller: _typeController,     icon: Icons.category),
                      buildTextField(label: "Borrower", controller: _borrowerController, icon: Icons.person),
                    ),
                    const SizedBox(height: gap),
                    twoCol(
                      buildTextField(label: "Location", controller: _locationController, icon: Icons.location_on),
                      buildTextField(label: "Quantity", controller: _quantityController, icon: Icons.numbers),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Borrow/Return date
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          icon: const Icon(Icons.calendar_month, color: Colors.blue),
                          label: Text(
                            _borrowDate == null
                                ? "Borrow date"
                                : "Borrow date: ${_borrowDate!.day}/${_borrowDate!.month}/${_borrowDate!.year}",
                          ),
                          onPressed: () => _selectDate(context, true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextButton.icon(
                          icon: const Icon(Icons.calendar_month, color: Colors.blue),
                          label: Text(
                            _returnDate == null
                                ? "Return date"
                                : "Return date: ${_returnDate!.day}/${_returnDate!.month}/${_returnDate!.year}",
                          ),
                          onPressed: () => _selectDate(context, false),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: saveData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        "Save",
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
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
