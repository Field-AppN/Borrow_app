import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'responsive.dart';
import '../utils/ids/master_id.dart';

const String sourceCollection = 'master_devices';
const String destinationCollection = 'Masters';

class MasterForm extends StatefulWidget {
  const MasterForm({Key? key}) : super(key: key);

  @override
  State<MasterForm> createState() => _MasterFormState();
}

class _MasterFormState extends State<MasterForm> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController borrowerController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController typeOfWorkController = TextEditingController(); // optional

  String? _selectedTeam;
  final List<String> _teams = [];
  bool _loadingTeams = false;

  final List<_EquipItem> _equipments = [];
  bool _loadingEquipments = false;

  DateTime? borrowDate;
  DateTime? returnDate;

  bool isSaving = false;

  // Progress bar
  double progressValue = 0.0;
  bool get _hasSelectedEquipment => _equipments.any((e) => e.selected);
  void _updateProgress() {
    int total = 6;
    int filled = 0;
    if (_selectedTeam != null && _selectedTeam!.isNotEmpty) filled++;
    if (borrowerController.text.trim().isNotEmpty) filled++;
    if (locationController.text.trim().isNotEmpty) filled++;
    if (borrowDate != null) filled++;
    if (returnDate != null) filled++;
    if (_hasSelectedEquipment) filled++;
    setState(() => progressValue = (filled / total).clamp(0, 1));
  }

  String _s(dynamic v) => v == null ? '' : v.toString().trim();
  String _pickFirstNonEmpty(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = _s(data[k]);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  Future<void> _pickDate(BuildContext context, ValueChanged<DateTime> onPicked) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: "Pick a date",
    );
    if (picked != null) {
      onPicked(picked);
      _updateProgress();
    }
  }

  Future<void> _loadTeams() async {
    setState(() => _loadingTeams = true);
    _teams.clear();
    try {
      final col = FirebaseFirestore.instance.collection(sourceCollection);
      Query<Map<String, dynamic>> base = col.where('active', isEqualTo: true);
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await base.orderBy('team').limit(10000).get();
      } on FirebaseException catch (e) {
        if (e.code == 'failed-precondition') {
          snap = await base.limit(10000).get();
        } else {
          rethrow;
        }
      }
      final setTeams = <String>{};
      for (final d in snap.docs) {
        final data = d.data();
        final v = _s(data['team']);
        if (v.isNotEmpty) setTeams.add(v);
      }
      _teams.addAll(setTeams.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
    } catch (e) {
      _showPopup("โหลดรายชื่อทีมไม่สำเร็จ: $e", false);
    } finally {
      setState(() => _loadingTeams = false);
    }
  }

  Future<void> _loadEquipmentsForTeam(String team) async {
    setState(() {
      _loadingEquipments = true;
      _equipments.clear();
    });
    try {
      final col = FirebaseFirestore.instance.collection(sourceCollection);
      Query<Map<String, dynamic>> base =
      col.where('team', isEqualTo: team).where('active', isEqualTo: true);

      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
      try {
        docs = (await base.orderBy('equipmentCode').get()).docs;
      } on FirebaseException catch (e) {
        if (e.code == 'failed-precondition') {
          final snap = await base.get();
          docs = snap.docs
            ..sort((a, b) => _s(a.data()['equipmentCode'])
                .compareTo(_s(b.data()['equipmentCode'])));
        } else {
          rethrow;
        }
      }

      for (final d in docs) {
        final data = d.data();
        final name = _pickFirstNonEmpty(data, [
          'Equipment', 'equipment', 'Name', 'name', 'EquipmentName', 'Type', 'Model',
        ]);
        final code = _pickFirstNonEmpty(data, ['equipmentCode', 'EquipmentCode']);
        final brand = _pickFirstNonEmpty(data, ['Brand', 'Manufacturer']);
        final serial = _pickFirstNonEmpty(data, ['Serial', 'SN', 'sn']);
        final location = _s(data['Location']);
        _equipments.add(_EquipItem(
          id: d.id,
          team: team,
          equipment: name.isNotEmpty ? name : code,
          equipmentCode: code,
          brand: brand,
          serial: serial,
          location: location,
        ));
      }
    } catch (e) {
      _showPopup("โหลดรายการเครื่องไม่สำเร็จ: $e", false);
    } finally {
      setState(() => _loadingEquipments = false);
      _updateProgress();
    }
  }

  // ====== ปรับเฉพาะ popup / logic การตรวจ ======
  Future<void> _save() async {
    // ยังไม่ได้เลือกทีม
    if (_selectedTeam == null || _selectedTeam!.isEmpty) {
      _showPopup('กรุณาเลือกทีม', false);
      return;
    }
    // ยังไม่ได้เลือกอุปกรณ์
    if (_equipments.where((e) => e.selected).isEmpty) {
      _showPopup('กรุณาเลือกอุปกรณ์', false);
      return;
    }
    // กรอกข้อมูลไม่ครบ
    if (!_formKey.currentState!.validate()) {
      _showPopup('กรุณากรอกข้อมูลให้ครบทุกช่อง', false);
      return;
    }
    // ยังไม่เลือกวันที่
    if (borrowDate == null || returnDate == null) {
      _showPopup('กรุณาเลือกวันที่ยืมและวันที่คืน', false);
      return;
    }

    setState(() => isSaving = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final coll = FirebaseFirestore.instance.collection(destinationCollection);

      for (final item in _equipments.where((e) => e.selected)) {
        final locToUse = locationController.text.trim().isEmpty
            ? item.location
            : locationController.text.trim();

        final docId = buildMastersDocId(
          location: locToUse,
          equipmentCode: item.equipmentCode,
        );
        final ref = coll.doc(docId);

        batch.set(ref, {
          'Team': _selectedTeam,
          'Equipment': item.equipment,
          'EquipmentCode': item.equipmentCode,
          'Brand': item.brand,
          'Serial': item.serial,
          'Location': locToUse,
          'Borrower': borrowerController.text.trim(),
          'TypeOfWork': typeOfWorkController.text.trim(), // optional
          'borrow_date': borrowDate,
          'return_date': returnDate,
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();

      // บันทึกสำเร็จ
      _showPopup('บันทึกข้อมูลเรียบร้อยแล้ว', true);

      setState(() {
        for (final e in _equipments) {
          e.selected = false;
        }
        borrowerController.clear();
        locationController.clear();
        typeOfWorkController.clear();
        borrowDate = null;
        returnDate = null;
      });
      _updateProgress();
    } catch (e) {
      _showPopup('การบันทึกล้มเหลว: $e', false);
    } finally {
      setState(() => isSaving = false);
    }
  }

  // Popup เดียวใช้ทุกเคส (หัวข้อ/สีเหมือนใน Windows)
  void _showPopup(String message, bool success) {
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
            Text(
              success ? 'สำเร็จ!' : 'กรอกข้อมูลไม่ครบ!',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }
  // ====== /ปรับเฉพาะ popup ======

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool requiredField = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        onChanged: (_) => _updateProgress(),
        validator: requiredField
            ? (v) => (v == null || v.trim().isEmpty) ? 'Please enter $label' : null
            : null,
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

  Widget _buildDateButton(String label, DateTime? date, ValueChanged<DateTime> onPicked) {
    return TextButton.icon(
      icon: const Icon(Icons.calendar_month, color: Colors.blue),
      label: Text(date == null ? label : "$label: ${date.day}/${date.month}/${date.year}"),
      onPressed: () => _pickDate(context, onPicked),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadTeams();
    _updateProgress();
  }

  @override
  Widget build(BuildContext context) {
    final tablet = isTablet(context);
    const gap = 12.0;

    Widget twoCol(Widget a, Widget b) => Row(
      children: [
        Expanded(child: a),
        const SizedBox(width: gap),
        Expanded(child: b),
      ],
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
          "Master Equipment Form",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Refresh teams',
            onPressed: _loadingTeams
                ? null
                : () async {
              await _loadTeams();
              _updateProgress();
            },
            icon: _loadingTeams
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
                : const Icon(Icons.refresh, color: Colors.white),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: CenteredBody(
        child: Padding(
          padding: responsivePagePadding(context),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Progress bar (red)
                  LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 6,
                    backgroundColor: Colors.grey[300],
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),

                  // Team
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: DropdownButtonFormField<String>(
                      value: _selectedTeam,
                      isExpanded: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.group, color: Colors.blue),
                        labelText: 'Team',
                        labelStyle: const TextStyle(color: Colors.black87),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.black26),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.blue, width: 2),
                        ),
                      ),
                      items: _teams
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (val) async {
                        setState(() => _selectedTeam = val);
                        _updateProgress();
                        if (val != null) await _loadEquipmentsForTeam(val);
                      },
                    ),
                  ),

                  // Borrower / Location / Type of work
                  if (!tablet) ...[
                    _buildTextField(
                        label: "Borrower",
                        controller: borrowerController,
                        icon: Icons.person),
                    _buildTextField(
                        label: "Location",
                        controller: locationController,
                        icon: Icons.location_on),
                    _buildTextField(
                      label: "Type of work",
                      controller: typeOfWorkController,
                      icon: Icons.work_outline,
                      requiredField: false,
                    ),
                  ] else ...[
                    twoCol(
                      _buildTextField(
                          label: "Borrower",
                          controller: borrowerController,
                          icon: Icons.person),
                      _buildTextField(
                          label: "Location",
                          controller: locationController,
                          icon: Icons.location_on),
                    ),
                    _buildTextField(
                      label: "Type of work",
                      controller: typeOfWorkController,
                      icon: Icons.work_outline,
                      requiredField: false,
                    ),
                  ],

                  const SizedBox(height: 8),

                  // Borrow/Return dates
                  Row(
                    children: [
                      Expanded(
                        child: _buildDateButton(
                            "Borrow date", borrowDate, (d) => setState(() => borrowDate = d)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildDateButton(
                            "Return date", returnDate, (d) => setState(() => returnDate = d)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Equipments
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _selectedTeam == null
                          ? 'Select a team to list equipments'
                          : 'Equipments in team: ${_selectedTeam!}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    constraints: BoxConstraints(maxHeight: tablet ? 380 : 300),
                    child: _loadingEquipments
                        ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                        : (_equipments.isEmpty
                        ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No items (or no team selected)'),
                      ),
                    )
                        : ListView.separated(
                      itemCount: _equipments.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = _equipments[i];
                        final subtitleParts = <String>[];
                        if (e.equipmentCode.isNotEmpty) {
                          subtitleParts.add('Code: ${e.equipmentCode}');
                        }
                        if (e.brand.isNotEmpty) {
                          subtitleParts.add('Brand: ${e.brand}');
                        }
                        if (e.serial.isNotEmpty) {
                          subtitleParts.add('S/N: ${e.serial}');
                        }
                        final subtitle = subtitleParts.join('  •  ');
                        return CheckboxListTile(
                          value: e.selected,
                          onChanged: (v) {
                            setState(() => e.selected = v ?? false);
                            _updateProgress();
                          },
                          title: Text(e.equipment.isEmpty ? '(Unnamed)' : e.equipment),
                          subtitle: subtitle.isEmpty ? null : Text(subtitle),
                        );
                      },
                    )),
                  ),

                  const SizedBox(height: 20),

                  // Save
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isSaving
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

class _EquipItem {
  _EquipItem({
    required this.id,
    required this.team,
    required this.equipment,
    required this.equipmentCode,
    required this.brand,
    required this.serial,
    required this.location,
    this.selected = false,
  });

  final String id;
  final String team;
  final String equipment;
  final String equipmentCode;
  final String brand;
  final String serial;
  final String location;

  bool selected;
}
