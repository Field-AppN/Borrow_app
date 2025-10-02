#!/usr/bin/env node
// ใช้แบบ: node auto_upload.cjs "<local-excel-path>" [--bucket=xxx.appspot.com] [--dest=imports/master_devices.xlsx]
const chokidar = require("chokidar");
const { Storage } = require("@google-cloud/storage");
const path = require("path");
const fs = require("fs");

// ใช้ serviceAccount เดิม (ข้างไฟล์นี้)
const sa = require("./serviceAccount.json");
const storage = new Storage({ credentials: sa, projectId: sa.project_id });
const defaultBucket = `${sa.project_id}.appspot.com`;

const localPath = process.argv[2];
const bucketName = (process.argv.find(a => a.startsWith("--bucket=")) || "").split("=")[1] || defaultBucket;
const dest = (process.argv.find(a => a.startsWith("--dest=")) || "").split("=")[1] || "imports/master_devices.xlsx";

if (!localPath) { console.error("ระบุ path ไฟล์ด้วย เช่น: node auto_upload.cjs \"C:\\ไฟล์.xlsx\""); process.exit(1); }
if (!fs.existsSync(localPath)) { console.error("ไม่พบไฟล์:", localPath); process.exit(1); }

const bucket = storage.bucket(bucketName);
let timer = null;

async function uploadOnce() {
  console.log(`⬆️  กำลังอัปโหลด → gs://${bucketName}/${dest}`);
  await bucket.upload(localPath, {
    destination: dest,
    contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    resumable: false,
    validation: false,
  });
  console.log(`✅ อัปโหลดเรียบร้อย ${new Date().toLocaleString()}`);
}

console.log("👀 Watching:", path.resolve(localPath));
await uploadOnce(); // อัปโหลดครั้งแรก
chokidar.watch(localPath, { ignoreInitial: true }).on("all", () => {
  clearTimeout(timer);
  timer = setTimeout(uploadOnce, 800); // debounce
});
