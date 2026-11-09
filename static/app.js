const MAX_FILE_SIZE = 10 * 1024 * 1024;
const SUPPORTED_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);

const fileInput = document.querySelector("#fileInput");
const dropZone = document.querySelector("#dropZone");
const previewImage = document.querySelector("#previewImage");
const previewEmpty = document.querySelector("#previewEmpty");
const fileName = document.querySelector("#fileName");
const errorMessage = document.querySelector("#errorMessage");
const extractButton = document.querySelector("#extractButton");
const resultSection = document.querySelector("#resultSection");
const palette = document.querySelector("#palette");
const statusMessage = document.querySelector("#statusMessage");
const toast = document.querySelector("#toast");
const versionBadge = document.querySelector("#versionBadge");
let selectedFile = null;
let objectUrl = null;
let toastTimer;

function showError(message) {
  errorMessage.textContent = message;
  errorMessage.hidden = false;
}
function clearError() { errorMessage.hidden = true; errorMessage.textContent = ""; }
function resetResults() { resultSection.hidden = true; palette.innerHTML = ""; statusMessage.textContent = ""; }
function clearPreview() {
  if (objectUrl) URL.revokeObjectURL(objectUrl);
  objectUrl = null; previewImage.removeAttribute("src"); previewImage.hidden = true; previewEmpty.hidden = false;
}
function validateFile(file) {
  if (!file) return "파일을 선택해 주세요.";
  if (!SUPPORTED_TYPES.has(file.type)) return "이미지 파일(JPG, PNG, WEBP, GIF)만 선택할 수 있습니다.";
  if (file.size > MAX_FILE_SIZE) return "파일 용량이 너무 큽니다. 10MB 이하의 이미지를 선택해 주세요.";
  return null;
}
function selectFile(file) {
  clearError(); resetResults();
  const problem = validateFile(file);
  if (problem) {
    selectedFile = null; fileInput.value = ""; fileName.textContent = "선택된 파일이 없습니다."; extractButton.disabled = true; clearPreview(); showError(problem); return;
  }
  selectedFile = file;
  fileName.textContent = `${file.name} · ${(file.size / 1024 / 1024).toFixed(2)}MB`;
  extractButton.disabled = false;
  clearPreview(); objectUrl = URL.createObjectURL(file); previewImage.src = objectUrl; previewImage.hidden = false; previewEmpty.hidden = true;
}
function showToast(message) { toast.textContent = message; toast.classList.add("visible"); clearTimeout(toastTimer); toastTimer = setTimeout(() => toast.classList.remove("visible"), 2200); }
async function copyHex(hex) {
  try { await navigator.clipboard.writeText(hex); showToast(`${hex} 복사 완료`); }
  catch { showToast("복사하지 못했습니다. 코드를 직접 선택해 주세요."); }
}
async function loadVersion() {
  try {
    const response = await fetch("/api/health", { cache: "no-store" });
    if (!response.ok) throw new Error("version unavailable");
    const body = await response.json();
    versionBadge.textContent = `배포 버전 ${body.version}`;
  } catch {
    versionBadge.textContent = "배포 버전 확인 불가";
  }
}
function renderPalette(colors) {
  palette.innerHTML = "";
  colors.forEach((color) => {
    const card = document.createElement("button");
    card.type = "button"; card.className = "color-card"; card.title = `${color.hex} 복사`; card.setAttribute("aria-label", `${color.hex} 코드 복사`);
    card.innerHTML = `<span class="swatch" style="background:${color.hex}"></span><span class="color-info"><strong class="hex">${color.hex}</strong><span class="rgb">${color.rgb}</span></span>`;
    card.addEventListener("click", () => copyHex(color.hex));
    palette.append(card);
  });
}
fileInput.addEventListener("change", (event) => selectFile(event.target.files[0]));
previewImage.addEventListener("error", () => {
  if (!selectedFile) return;
  selectedFile = null; fileInput.value = ""; fileName.textContent = "선택된 파일이 없습니다.";
  extractButton.disabled = true; clearPreview();
  showError("이미지를 열 수 없습니다. 파일이 손상되었거나 지원하지 않는 이미지입니다.");
});
["dragenter", "dragover"].forEach((eventName) => dropZone.addEventListener(eventName, (event) => { event.preventDefault(); dropZone.classList.add("dragover"); }));
["dragleave", "drop"].forEach((eventName) => dropZone.addEventListener(eventName, (event) => { event.preventDefault(); dropZone.classList.remove("dragover"); }));
dropZone.addEventListener("drop", (event) => { selectFile(event.dataTransfer.files[0]); });
extractButton.addEventListener("click", async () => {
  if (!selectedFile) return;
  clearError(); resetResults(); extractButton.disabled = true; extractButton.textContent = "분석 중…";
  statusMessage.textContent = "이미지의 색감을 분석하고 있습니다…"; resultSection.hidden = false;
  try {
    const data = new FormData(); data.append("file", selectedFile);
    const response = await fetch("/api/extract", { method: "POST", body: data });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.detail || "색상 추출 중 오류가 발생했습니다.");
    renderPalette(body.colors); statusMessage.textContent = "분석이 완료되었습니다.";
  } catch (err) {
    resetResults(); showError(err.message || "서버와 통신할 수 없습니다. 잠시 후 다시 시도해 주세요.");
  } finally { extractButton.disabled = false; extractButton.textContent = "색상 추출"; }
});
window.addEventListener("beforeunload", () => { if (objectUrl) URL.revokeObjectURL(objectUrl); });
loadVersion();
