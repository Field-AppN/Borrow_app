#!/usr/bin/env node
// ใช้แบบ:
//   node import_inventory.cjs "<path-to-excel>" [--soft-delete] [--sheet=MASTER]
//
// ตัวอย่าง:
//   node import_inventory.cjs ".\\รายการเครื่องมาตรฐาน.xlsx"
//   node import_inventory.cjs ".\\รายการเครื่องมาตรฐาน.xlsx" --soft-delete
//   node import_inventory.cjs ".\\รายการเครื่องมาตรฐาน.xlsx" --sheet=MASTER

const admin = require("firebase-admin");
const XLSX = require("xlsx");
const path = require("path");
const fs = require("fs");

// ---------- โหลด service account ----------
const serviceAccount = require("./serviceAccount.json");
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

/* ========================= Helpers ========================= */
function pick(obj, keys) {
  for (const k of keys) {
    const v = obj?.[k];
    if (v !== undefined && v !== null && String(v).trim() !== "") return v;
  }
  return undefined;
}
function excelCellToDate(v) {
  if (v === undefined || v === null || v === "") return undefined;
  if (typeof v === "number") {
    const ms = Math.round((v - 25569) * 86400 * 1000); // Excel serial -> JS Date
    return new Date(ms);
  }
  const s = String(v).trim();
  if (!s) return undefined;
  const m = s.match(/^(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{2,4})$/);
  if (m) {
    const dd = +m[1], mm = +m[2], yyyy = +m[3] < 100 ? 2000 + (+m[3]) : +m[3];
    return new Date(yyyy, mm - 1, dd);
  }
  const d = new Date(s);
  return isNaN(d.getTime()) ? undefined : d;
}
function parseEmails(v) {
  if (!v) return [];
  return String(v).split(/[;,]/).map(s => s.trim()).filter(Boolean);
}
// ตรวจว่าเป็นชื่อคอลัมน์ "Equipment Code"
const CODE_HEADER_RE = /^(equipment\s*code|eq\s*code|eqcode|code|รหัสอุปกรณ์|รหัส)$/i;

/* ========================= Arguments ========================= */
const excelPath = process.argv[2] || ".\\รายการเครื่องมาตรฐาน.xlsx";
const doSoftDelete = process.argv.includes("--soft-delete");
const sheetArg = (process.argv.find(a => a.startsWith("--sheet=")) || "").split("=")[1];

if (!fs.existsSync(excelPath)) {
  console.error(`❌ ไม่พบไฟล์: ${excelPath}`);
  process.exit(1);
}

/* ========================= Read Excel (robust) ========================= */
const wb = XLSX.readFile(excelPath);
const sheetNames = wb.SheetNames;

// เลือกชีท: --sheet=... > MASTER > ชีทแรก
const chosenSheet =
  (sheetArg && sheetNames.includes(sheetArg) && sheetArg) ||
  (sheetNames.includes("MASTER") ? "MASTER" : sheetNames[0]);

const ws = wb.Sheets[chosenSheet];

// อ่านเป็น array-of-arrays เพื่อหา "แถวหัวตาราง" จริง (กรณีมีหัวหลายแถว/มีบรรทัดโล่ง)
const AOA = XLSX.utils.sheet_to_json(ws, { header: 1, blankrows: false, defval: "" });

// หา index ของแถวหัวตารางจาก 20 แถวแรก (หรือทั้งหมดถ้าตารางสั้น)
let headerRowIdx = 0;
const scanLimit = Math.min(20, AOA.length);
for (let i = 0; i < scanLimit; i++) {
  const row = AOA[i].map(x => String(x).trim());
  if (!row.length) continue;
  // เจอแถวที่มีคำว่า equipment code/Code/รหัส...
  if (row.some(c => CODE_HEADER_RE.test(c))) {
    headerRowIdx = i;
    break;
  }
}

// สร้าง objects จาก headerRowIdx
const headers = AOA[headerRowIdx].map(h => String(h).trim());
const rows = [];
for (let r = headerRowIdx + 1; r < AOA.length; r++) {
  const arr = AOA[r];
  if (!arr || arr.every(v => String(v ?? "").trim() === "")) continue; // ข้ามแถวว่าง
  const obj = {};
  for (let c = 0; c < headers.length; c++) {
    const key = headers[c] || `COL_${c}`;
    obj[key] = arr[c] ?? "";
  }
  rows.push(obj);
}

// ดีบักให้เห็นไฟล์/ชีท/จำนวน/ท้ายไฟล์
console.log(`📄 ไฟล์: ${path.resolve(excelPath)}`);
console.log(`📑 ชีทที่อ่าน: "${chosenSheet}"  (หัวตารางที่แถว: ${headerRowIdx + 1})`);
console.log(`📦 แถวข้อมูลที่ประมวลผล: ${rows.length}`);
const tailCodes = rows
  .slice(-5)
  .map(r => pick(r, ["EquipmentCode","equipmentCode","Equipment Code","รหัสอุปกรณ์","รหัส","Code","code","EQCode"]));
console.log(`🔎 ตัวอย่าง EquipmentCode ท้ายไฟล์:`, tailCodes);

/* ========================= Upsert → master_devices ========================= */
(async () => {
  const bw = db.bulkWriter();
  const seenIds = new Set();
  let upserts = 0, skippedNoCode = 0;

  for (const r of rows) {
    const equipmentCode =
      pick(r, [
        "EquipmentCode",
        "equipmentCode",
        "Equipment Code",
        "รหัสอุปกรณ์",
        "รหัส",
        "Code",
        "code",
        "EQCode",
      ]) || "";

    if (!equipmentCode) {
      skippedNoCode++;
      continue; // ต้องมีคีย์หลัก
    }

    const perform = excelCellToDate(
      pick(r, ["PerformDate","perform_date","LatestCal","latest_cal","วันที่สอบเทียบล่าสุด"])
    );
    const due = excelCellToDate(
      pick(r, ["DueDate","due_date","NextCal","next_cal","วันที่สอบเทียบครั้งถัดไป"])
    );
    const team = pick(r, ["Team","team","Group","group","ทีม"]);
    const notifyEmails = parseEmails(
      pick(r, ["NotifyEmails","notifyEmails","Emails","email","อีเมลแจ้งเตือน"])
    );

    const ref = db.collection("master_devices").doc(String(equipmentCode).trim());
    const payload = {
      equipmentCode: String(equipmentCode).trim(),
      ...(team ? { team: String(team) } : {}),
      ...(notifyEmails.length ? { notifyEmails } : {}),
      active: true,
      updatedFromExcelAt: admin.firestore.FieldValue.serverTimestamp(),
      sourceExcelName: path.basename(excelPath),
    };
    if (perform) payload.performDate = admin.firestore.Timestamp.fromDate(perform);
    if (due) payload.dueDate = admin.firestore.Timestamp.fromDate(due);

    bw.set(ref, payload, { merge: true });
    seenIds.add(ref.id);
    upserts++;
  }

  await bw.close();
  console.log(`✅ upsert เรียบร้อย: ${upserts} รายการ`);
  if (skippedNoCode) console.log(`⚠️ ข้ามแถวเพราะไม่มี EquipmentCode: ${skippedNoCode} แถว`);

  // (ตัวเลือก) ให้ฐานข้อมูล “เหมือนกับไฟล์” โดย mark active=false สำหรับรหัสที่ไม่อยู่ในไฟล์
  if (doSoftDelete) {
    const col = db.collection("master_devices");
    const snap = await col.get();
    const delBw = db.bulkWriter();
    let soft = 0;
    for (const doc of snap.docs) {
      if (!seenIds.has(doc.id) && doc.data().active !== false) {
        delBw.set(
          doc.ref,
          { active: false, deactivatedAt: admin.firestore.FieldValue.serverTimestamp() },
          { merge: true }
        );
        soft++;
      }
    }
    await delBw.close();
    console.log(`🟠 soft-delete (active=false) รายการที่ไม่มีในไฟล์: ${soft}`);
  }

  console.log("🎉 เสร็จสิ้น");
  process.exit(0);
})().catch((e) => {
  console.error("❌ ผิดพลาด:", e);
  process.exit(1);
});
