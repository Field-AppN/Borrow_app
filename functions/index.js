// Firebase Functions v2 + CommonJS
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const { onObjectFinalized } = require("firebase-functions/v2/storage");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const { DateTime } = require("luxon");
const crypto = require("crypto");

admin.initializeApp();

/* -------------------- Secrets -------------------- */
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASS = defineSecret("SMTP_PASS");
const ADMIN_EMAIL = defineSecret("ADMIN_EMAIL");

/* --------------------------- Helpers --------------------------- */
// คืนค่าตัวแรกที่มีจริงจากหลายคีย์
function valOf(obj, ...keys) {
  for (const k of keys) {
    const v = obj && obj[k];
    if (v !== undefined && v !== null && String(v).trim() !== "") return v;
  }
  return undefined;
}

// แปลง Timestamp/Date -> dd/MM/yyyy (โซนไทย)
function formatDateTH(ts) {
  try {
    if (!ts) return "-";
    let d = null;
    if (typeof ts?.toDate === "function") d = ts.toDate();
    else if (ts && ts._seconds) d = new Date(ts._seconds * 1000);
    else if (ts instanceof Date) d = ts;
    if (!d) return "-";
    return DateTime.fromJSDate(d).setZone("Asia/Bangkok").toFormat("dd/MM/yyyy");
  } catch {
    return "-";
  }
}

// ส่วนต่างวันจากวันนี้ถึงวันเป้าหมาย
function daysLeftTH(ts) {
  try {
    if (!ts) return undefined;
    let d = null;
    if (typeof ts?.toDate === "function") d = ts.toDate();
    else if (ts && ts._seconds) d = new Date(ts._seconds * 1000);
    else if (ts instanceof Date) d = ts;
    if (!d) return undefined;
    const now = DateTime.now().setZone("Asia/Bangkok").startOf("day");
    const due = DateTime.fromJSDate(d).setZone("Asia/Bangkok").startOf("day");
    return Math.ceil(due.diff(now, "days").days);
  } catch {
    return undefined;
  }
}

/**
 * สร้าง HTML สำหรับส่งเมล
 * @param {object} data Firestore document data
 * @param {string} title หัวข้อในเนื้อหา
 * @param {object} opts { hideEqCode?:boolean, preferModel?:boolean }
 */
function buildHtmlFromDoc(data, title, opts = {}) {
  const { hideEqCode = false, preferModel = false } = opts;

  const has = (k) =>
    data && data[k] !== undefined && data[k] !== null && String(data[k]).trim() !== "";

  const serial = valOf(data, "serial", "Serial", "SerialNo", "SN", "sn", "Serial No");
  const withdraw = valOf(
    data,
    "withdraw_date",
    "issued_date",
    "issuedAt",
    "createdAt",
    "created_at"
  );

  const equipmentCode =
    valOf(
      data,
      "equipmentCode",
      "EquipmentCode",
      "Equipment Code",
      "equipment_code",
      "EQCode",
      "eq_code",
      "Code",
      "code"
    ) || "-";

  const latestCal = valOf(data, "performDate", "PerformDate", "latest_cal", "LatestCal");
  const nextCal = valOf(data, "dueDate", "DueDate", "next_cal", "NextCal");
  const nextLeft = daysLeftTH(nextCal);

  const lines = [];
  if (has("Borrower")) lines.push(`ผู้ยืม/ผู้รับผิดชอบ: <b>${data.Borrower}</b>`);
  if (has("Team")) lines.push(`ทีม/แผนก: <b>${data.Team}</b>`);
  if (has("Equipment")) lines.push(`อุปกรณ์: <b>${data.Equipment}</b>`);
  if (has("Brand")) lines.push(`ยี่ห้อ: <b>${data.Brand}</b>`);

  // แสดง "Model" เป็นหลักสำหรับ Infusion (หรือ fallback ไปที่ Type)
  if (preferModel) {
    const model = valOf(data, "Model", "Type");
    if (model) lines.push(`ประเภท/รุ่น: <b>${model}</b>`);
  } else {
    if (has("Type")) lines.push(`ประเภท/รุ่น: <b>${data.Type}</b>`);
    else if (has("Model")) lines.push(`ประเภท/รุ่น: <b>${data.Model}</b>`);
  }

  if (serial) lines.push(`Serial: <b>${serial}</b>`);
  if (has("Location")) lines.push(`สถานที่ใช้งาน: <b>${data.Location}</b>`);

  if (!hideEqCode) lines.push(`Equipment Code: <b>${equipmentCode}</b>`);

  if (latestCal) lines.push(`Perform Date (ล่าสุด): <b>${formatDateTH(latestCal)}</b>`);
  if (nextCal)
    lines.push(
      `Due Date (ครั้งถัดไป): <b>${formatDateTH(nextCal)}</b>${
        typeof nextLeft === "number" ? ` (<b>อีก ${nextLeft} วัน</b>)` : ""
      }`
    );
  if (has("borrow_date")) lines.push(`วันที่ยืม: <b>${formatDateTH(data.borrow_date)}</b>`);
  if (has("return_date")) lines.push(`วันที่คืน: <b>${formatDateTH(data.return_date)}</b>`);

  // Cleaning Supplies
  if (has("Item")) lines.push(`รายการ: <b>${data.Item}</b>`);
  if (has("Requester")) lines.push(`ผู้ขอเบิก: <b>${data.Requester}</b>`);
  if (has("Taken") || has("Total")) {
    const taken = has("Taken") ? data.Taken : "-";
    const total = has("Total") ? data.Total : "-";
    lines.push(`จำนวนที่เบิก: <b>${taken}</b> จากทั้งหมด: <b>${total}</b>`);
  }
  if (withdraw) lines.push(`วันที่เบิก: <b>${formatDateTH(withdraw)}</b>`);
  if (has("timestamp")) lines.push(`บันทึกเมื่อ: <b>${formatDateTH(data.timestamp)}</b>`);

  const li = lines.map((t) => `<li>${t}</li>`).join("");
  return `
    <div style="font-family:Arial,sans-serif;font-size:14px;color:#222">
      <h2 style="color:#002366;margin:0 0 8px">${title}</h2>
      <ul>${li}</ul>
      <p style="margin-top:12px;color:#888">อีเมลนี้ส่งอัตโนมัติจากระบบ Asset Management</p>
    </div>
  `;
}

// ทำความสะอาด email list
function toList(x) {
  if (!x) return [];
  if (Array.isArray(x)) return x.map((s) => String(s).trim()).filter(Boolean);
  return String(x)
    .split(/[;,]/)
    .map((s) => s.trim())
    .filter(Boolean);
}

/* --------- Document ID = วันที่-เดือน-ปี-เวลาปัจจุบัน-สถานที่-โค้ด --------- */
function makeDocIdNow(meta = {}) {
  const now = DateTime.now().setZone("Asia/Bangkok").setLocale("th");
  const datePart = now.toFormat("dd-LLL-yyyy-HH.mm"); // เลี่ยง ":" ในเวลา
  const clean = (s, { keepSpaces = true } = {}) =>
    String(s ?? "")
      .normalize("NFKC")
      .replace(/\s+/g, keepSpaces ? " " : "")
      .replace(/[\/#?\[\]\\]+/g, "-")
      .trim();
  const place = clean(meta.location || meta.Location || "UNKNOWN");
  const code = clean((meta.equipmentCode || meta.EquipmentCode || "NO-CODE").toUpperCase(), {
    keepSpaces: false,
  });
  const rand = crypto.randomBytes(2).toString("hex").toUpperCase(); // กันชนกัน
  return `${datePart}-${place}-${code}-${rand}`;
}

/* ---------------------- Nodemailer transporter ---------------------- */
function getTransporter() {
  const user = SMTP_USER.value();
  const pass = SMTP_PASS.value();
  return nodemailer.createTransport({
    service: "gmail",
    auth: { user, pass },
  });
}

/* ---------------------- Queue: mail_jobs ---------------------- */
async function enqueueMail(db, msg, meta = {}) {
  // ลบ key undefined/null ออกจาก msg เพื่อกัน error Firestore
  const safe = {};
  for (const [k, v] of Object.entries(msg || {})) {
    if (v === undefined || v === null) continue;
    if (Array.isArray(v) && v.length === 0) continue;
    safe[k] = v;
  }

  const docId = makeDocIdNow(meta);
  await db.collection("mail_jobs").doc(docId).set({
    attempts: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    meta,
    msg: safe,
  });
  console.log(`📬 Enqueued mail job: ${docId}`);
  return docId;
}

/* ---------------------- สร้าง recipients ---------------------- */
function buildRecipients(data, adminEmail) {
  const to = String(data?.BorrowerEmail || adminEmail).trim();
  const bcc = [
    ...new Set([
      ...toList(data?.notifyEmails),
      ...toList(data?.NotifyEmails),
      adminEmail, // audit เสมอ
    ]),
  ].filter((e) => e && e !== to);
  return { to, bcc };
}

/* ---------------------- ผู้ส่งอีเมลแบบ worker (ทุก 30 นาที) ---------------------- */
exports.mailWorker = onSchedule(
  {
     schedule: "*/1 * * * *",          // ทุก 1 นาที -> "*/1 * * * *" ทุก 30 นาที  -> "0,30 * * * *"
    timeZone: "Asia/Bangkok",
    region: "asia-southeast1",
    secrets: [SMTP_USER, SMTP_PASS, ADMIN_EMAIL],
    timeoutSeconds: 300,
  },
  async () => {
    const db = admin.firestore();
    const transporter = getTransporter();
    const snap = await db.collection("mail_jobs")
      .orderBy("createdAt", "asc")
      .limit(25)
      .get();

    if (snap.empty) { console.log("mailWorker: no jobs"); return true; }

    for (const doc of snap.docs) {
      const job = doc.data() || {};
      const attempts = Number(job.attempts || 0);

      if (attempts >= 5) { await doc.ref.delete(); continue; }

      try {
        await transporter.sendMail(job.msg);
        await doc.ref.delete();
      } catch (e) {
        await doc.ref.set({
          attempts: attempts + 1,
          lastError: String(e?.message || e),
          lastTriedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
    }
    return true;
  }
);

/* --------------------------- Firestore triggers --------------------------- */
// Masters: เติม perform/due จาก master_devices แล้ว "เข้าคิวส่งอีเมล"
exports.sendEmailOnMaster = onDocumentCreated(
  {
    document: "Masters/{docId}",
    region: "asia-southeast1",
    secrets: [SMTP_USER, SMTP_PASS, ADMIN_EMAIL],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return null;

    const db = admin.firestore();
    const adminEmail = ADMIN_EMAIL.value();
    const data = snap.data() || {};

    // enrich จาก master_devices
    const code = (valOf(data, "equipmentCode", "EquipmentCode", "Equipment Code", "eq_code", "Code") || "")
      .toString()
      .trim();

    const enrich = {};
    try {
      if (code) {
        const m = await db.collection("master_devices").doc(code).get();
        if (m.exists) {
          const md = m.data() || {};
          if (md.performDate) enrich.performDate = md.performDate;
          if (md.dueDate) enrich.dueDate = md.dueDate;
          if (md.team && !data.Team) enrich.Team = md.team;
          if (md.equipmentCode && !data.EquipmentCode) enrich.EquipmentCode = md.equipmentCode;
          if (md.Location && !data.Location) enrich.Location = md.Location;
          if (md.NotifyEmails && !data.notifyEmails) enrich.notifyEmails = md.NotifyEmails;
        }
      }
      if (Object.keys(enrich).length) await snap.ref.set(enrich, { merge: true });
    } catch (err) {
      console.error("sendEmailOnMaster enrichment failed:", err);
    }

    const d = { ...data, ...enrich };
    const { to, bcc } = buildRecipients(d, adminEmail);

    const meta = {
      equipmentCode:
        valOf(d, "equipmentCode", "EquipmentCode", "Equipment Code", "eq_code", "Code") || "-",
      location: d.Location || "",
      performDate: d.performDate || d.latest_cal || null,
      dueDate: d.dueDate || d.next_cal || null,
    };

    const subject = "มีการยืม-คืน มาสเตอร์ใหม่";
    await enqueueMail(
      db,
      {
        to,
        bcc,
        subject,
        html: buildHtmlFromDoc(
          { ...d, performDate: meta.performDate, dueDate: meta.dueDate },
          subject
        ),
        text: undefined,
      },
      meta
    );

    return true;
  }
);

// Infusion Pump (ซ่อน Equipment Code และใช้ Model แทน Type)
exports.sendEmailOnBorrow = onDocumentCreated(
  {
    document: "Infusion Pump/{docId}",
    region: "asia-southeast1",
    secrets: [SMTP_USER, SMTP_PASS, ADMIN_EMAIL],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return null;

    const db = admin.firestore();
    const adminEmail = ADMIN_EMAIL.value();
    const d = snap.data() || {};
    const { to, bcc } = buildRecipients(d, adminEmail);

    const subject = "มีการยืม-คืน Infusion Pump ใหม่";
    await enqueueMail(
      db,
      {
        to,
        bcc,
        subject,
        html: buildHtmlFromDoc(d, subject, { hideEqCode: true, preferModel: true }),
      },
      {
        equipmentCode: "-", // ไม่ใช้ในเมลนี้
        location: d.Location || "",
        performDate: d.borrow_date || null,
        dueDate: d.return_date || null,
      }
    );

    return true;
  }
);

// Cleaning Supplies (ซ่อน Equipment Code)
exports.sendEmailOnCleaning = onDocumentCreated(
  {
    document: "Cleaning Supplies/{docId}",
    region: "asia-southeast1",
    secrets: [SMTP_USER, SMTP_PASS, ADMIN_EMAIL],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return null;

    const db = admin.firestore();
    const adminEmail = ADMIN_EMAIL.value();
    const d = snap.data() || {};
    const { to, bcc } = buildRecipients(d, adminEmail);

    const subject = "มีการเบิกอุปกรณ์ทำความสะอาดใหม่";
    await enqueueMail(
      db,
      {
        to,
        bcc,
        subject,
        html: buildHtmlFromDoc(d, subject, { hideEqCode: true }),
      },
      { equipmentCode: "-", location: d.Location || "" }
    );

    return true;
  }
);

/* ----------------------- Scheduled reminder 15 วัน ----------------------- */
function getBangkokDayRangePlus(days) {
  const zone = "Asia/Bangkok";
  const start = DateTime.now().setZone(zone).plus({ days }).startOf("day");
  const end = start.endOf("day");
  return { start, end };
}

exports.dailyReminder15d = onSchedule(
  {
    schedule: "0 9 * * *", // ทุกวัน 09:00
    timeZone: "Asia/Bangkok",
    region: "asia-southeast1",
    secrets: [SMTP_USER, SMTP_PASS, ADMIN_EMAIL],
  },
  async () => {
    const db = admin.firestore();
    const adminEmail = ADMIN_EMAIL.value();

    const { start, end } = getBangkokDayRangePlus(15);
    const startTs = admin.firestore.Timestamp.fromDate(start.toJSDate());
    const endTs = admin.firestore.Timestamp.fromDate(end.toJSDate());

    // Masters
    const byId = new Map();

    const q1 = await db.collection("Masters").where("dueDate", ">=", startTs).where("dueDate", "<=", endTs).get();
    q1.forEach((doc) => byId.set(doc.id, doc.data()));

    const q2 = await db.collection("Masters").where("next_cal", ">=", startTs).where("next_cal", "<=", endTs).get();
    q2.forEach((doc) => byId.set(doc.id, doc.data()));

    for (const [, d0] of byId) {
      const d = { ...d0 };
      const { to, bcc } = buildRecipients(d, adminEmail);

      const latestCal = d.performDate || d.latest_cal || null;
      const nextCal = d.dueDate || d.next_cal || null;

      await enqueueMail(
        db,
        {
          to,
          bcc,
          subject: "แจ้งเตือนล่วงหน้า 15 วัน: ถึงกำหนดสอบเทียบอุปกรณ์ (Masters)",
          html: buildHtmlFromDoc(
            { ...d, performDate: latestCal, dueDate: nextCal },
            "เตือนสอบเทียบอุปกรณ์"
          ),
        },
        {
          equipmentCode:
            valOf(d, "equipmentCode", "EquipmentCode", "Equipment Code", "eq_code", "Code") || "-",
          location: d.Location || "",
          performDate: latestCal,
          dueDate: nextCal,
        }
      );
    }

    // Infusion Pump: ถึงกำหนดคืน
    const infusionSnap = await db
      .collection("Infusion Pump")
      .where("return_date", ">=", startTs)
      .where("return_date", "<=", endTs)
      .get();

    for (const doc of infusionSnap.docs) {
      const d = doc.data();
      const { to, bcc } = buildRecipients(d, adminEmail);

      await enqueueMail(
        db,
        {
          to,
          bcc,
          subject: "แจ้งเตือนล่วงหน้า 15 วัน: ถึงกำหนดคืน Infusion Pump",
          html: buildHtmlFromDoc(d, "เตือนกำหนดคืน Infusion Pump", {
            hideEqCode: true,
            preferModel: true,
          }),
        },
        { equipmentCode: "-", location: d.Location || "" }
      );
    }

    console.log("✅ enqueued 15d reminders");
    return true;
  }
);

/* ================= Excel → Firestore (Storage Trigger) ================= */
/* LAZY-LOAD โมดูลหนัก ๆ ภายในฟังก์ชันเท่านั้น */
exports.importMasterDevicesFromExcel = onObjectFinalized(
  { region: "asia-southeast1", memory: "512MiB", timeoutSeconds: 300 },
  async (event) => {
    // ↓↓↓ ย้าย require หนัก ๆ มาไว้ตรงนี้ ↓↓↓
    const { Storage } = require("@google-cloud/storage");
    const XLSX = require("xlsx");
    const path = require("path");
    const os = require("os");
    const fs = require("fs");
    const gcsExcel = new Storage();
    // ↑↑↑

    const file = event.data;
    const filePath = file.name || "";
    const bucketName = file.bucket || "";

    // รับเฉพาะ imports/*.xlsx|xls
    if (!filePath.startsWith("imports/")) return;
    if (!/\.xlsx?$/i.test(filePath)) return;

    const bucket = gcsExcel.bucket(bucketName);
    const tmp = path.join(os.tmpdir(), path.basename(filePath));
    await bucket.file(filePath).download({ destination: tmp });

    try {
      const wb = XLSX.readFile(tmp);
      const sheetNames = wb.SheetNames;
      const chosenSheet = sheetNames.includes("MASTER") ? "MASTER" : sheetNames[0];
      const ws = wb.Sheets[chosenSheet];

      // --- ขยายช่วง !ref ให้ครอบคลุมเซลล์จริง ---
      const addrs = Object.keys(ws).filter((k) => /^[A-Z]+[0-9]+$/.test(k));
      const colToNum = (col) =>
        col.split("").reduce((n, ch) => n * 26 + (ch.charCodeAt(0) - 64), 0);
      let maxR = 0, maxC = 0;
      for (const a of addrs) {
        const m = a.match(/^([A-Z]+)([0-9]+)$/);
        if (!m) continue;
        const c = colToNum(m[1]);
        const r = parseInt(m[2], 10);
        if (r > maxR) maxR = r;
        if (c > maxC) maxC = c;
      }
      if (maxR && maxC) {
        ws["!ref"] = XLSX.utils.encode_range({ r: 0, c: 0 }, { r: maxR - 1, c: maxC - 1 });
      }

      const AOA = XLSX.utils.sheet_to_json(ws, { header: 1, blankrows: false, defval: "" });
      const CODE_HDR_RE = /^(equipment\s*code|eq\s*code|eqcode|code|รหัสอุปกรณ์|รหัส)$/i;

      // หาแถวหัวตาราง (มองหา column code ก่อน)
      let headerRowIdx = 0;
      for (let i = 0; i < Math.min(30, AOA.length); i++) {
        const row = (AOA[i] || []).map((x) => String(x).trim());
        if (row.some((c) => CODE_HDR_RE.test(c))) {
          headerRowIdx = i;
          break;
        }
      }

      const headers = (AOA[headerRowIdx] || []).map((h) => String(h).trim());
      const rows = [];
      for (let r = headerRowIdx + 1; r < AOA.length; r++) {
        const arr = AOA[r];
        if (!arr || arr.every((v) => String(v ?? "").trim() === "")) continue;
        const obj = {};
        for (let c = 0; c < headers.length; c++) obj[headers[c] || `COL_${c}`] = arr[c] ?? "";
        rows.push(obj);
      }

      console.log(`📦 Excel import: ${filePath} | Sheet="${chosenSheet}" | Rows=${rows.length}`);
      console.log(`ℹ️ Header row (1-based): ${headerRowIdx + 1}`);

      const normalize = (s) => String(s || "").toLowerCase().replace(/[\s_]/g, "").trim();
      const getByHeaderSet = (row, candidatesSet) => {
        for (const k of Object.keys(row)) {
          if (candidatesSet.has(normalize(k))) return row[k];
        }
        return undefined;
      };

      const monthIdx = (m) => {
        const map = {
          jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5,
          jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11,
        };
        const key = (m || "").slice(0, 3).toLowerCase();
        return Object.prototype.hasOwnProperty.call(map, key) ? map[key] : -1;
      };

      const parseExcelDate = (v) => {
        if (v === undefined || v === null || v === "") return undefined;

        if (typeof v === "number") {
          const ms = Math.round((v - 25569) * 86400 * 1000);
          return new Date(ms);
        }

        const s = String(v).trim();

        let m = s.match(/^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})$/);
        if (m) {
          let yyyy = +m[3];
          if (yyyy < 100) yyyy = 2000 + yyyy;
          return new Date(yyyy, +m[2] - 1, +m[1]);
        }

        m = s.match(/^(\d{1,2})[\/\-\s]([A-Za-z]{3,})[\/\-\s](\d{2,4})$/);
        if (m) {
          let yyyy = +m[3];
          if (yyyy < 100) yyyy = 2000 + yyyy;
          const mm = monthIdx(m[2]);
          if (mm >= 0) return new Date(yyyy, mm, +m[1]);
        }

        const d = new Date(s);
        return isNaN(d.getTime()) ? undefined : d;
      };

      const performHdrs = new Set(["performdate", "latestcal", "วันที่สอบเทียบล่าสุด"]);
      const dueHdrs = new Set(["duedate", "nextcal", "วันที่สอบเทียบครั้งถัดไป"]);
      const teamHdrs = new Set(["team", "group", "ทีม"]);
      const codeHdrs = new Set(["equipmentcode", "eqcode", "code", "รหัสอุปกรณ์", "รหัส"]);

      const db = admin.firestore();
      const bw = db.bulkWriter();

      let upserts = 0, missing = 0;
      const sampleMissing = [];
      let excelRowNo = headerRowIdx + 2;

      for (const row of rows) {
        const codeRaw = getByHeaderSet(row, codeHdrs);
        const code = (codeRaw || "").toString().trim();
        if (!code) {
          missing++;
          if (sampleMissing.length < 10)
            sampleMissing.push({ row: excelRowNo, peek: JSON.stringify(row).slice(0, 120) });
          excelRowNo++;
          continue;
        }

        const perform = parseExcelDate(getByHeaderSet(row, performHdrs));
        const due = parseExcelDate(getByHeaderSet(row, dueHdrs));
        const team = (getByHeaderSet(row, teamHdrs) || "").toString().trim();

        const ref = db.collection("master_devices").doc(code);
        const payload = {
          equipmentCode: code,
          ...(team ? { team } : {}),
          active: true,
          updatedFromExcelAt: admin.firestore.FieldValue.serverTimestamp(),
          sourceExcelPath: filePath,
          sourceExcelName: path.basename(filePath),
        };
        if (perform) payload.performDate = admin.firestore.Timestamp.fromDate(perform);
        if (due) payload.dueDate = admin.firestore.Timestamp.fromDate(due);

        // เก็บชื่ออุปกรณ์/ยี่ห้อ/รุ่น/ซีเรียลถ้ามีคอลัมน์พวกนี้
        const name =
          row["Equipment"] || row["equipment"] || row["Name"] || row["Type"] || row["Model"];
        const brand = row["Brand"] || row["Manufacturer"];
        const serial = row["Serial"] || row["SN"] || row["sn"];
        if (name) payload.Equipment = String(name);
        if (brand) payload.Brand = String(brand);
        if (serial) payload.Serial = String(serial);

        bw.set(ref, payload, { merge: true });
        upserts++;
        excelRowNo++;
      }

      await bw.close();
      console.log(`✅ Imported ${upserts} docs from ${filePath}`);
      console.log(`🧮 Summary: totalRows=${rows.length}, imported=${upserts}, missingCode=${missing}`);
      if (sampleMissing.length)
        console.log("⚠️ Rows without Equipment Code (first 10):", sampleMissing);
    } catch (e) {
      console.error("❌ Excel import failed:", e);
      throw e;
    } finally {
      try { fs.unlink(tmp, () => {}); } catch {}
    }
  }
);
