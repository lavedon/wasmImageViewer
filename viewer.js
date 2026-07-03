/* JS shim for the wasm image viewer. Wasm owns all pixels; this file only
 * handles login UI, fetching bytes, forwarding advance events, and blitting
 * the framebuffer wasm composites. */

"use strict";

const loginForm = document.getElementById("login-form");
const loginError = document.getElementById("login-error");
const loginBox = loginForm; /* the form is the whole login UI */
const loaderBox = document.getElementById("loader");
const loaderText = document.getElementById("loader-text");
const stage = document.getElementById("stage");
const canvas = document.getElementById("view");
const ctx = canvas.getContext("2d");

let wasm = null;

async function initWasm() {
  const res = await fetch("viewer.wasm");
  let result;
  try {
    result = await WebAssembly.instantiateStreaming(res, {});
  } catch {
    // dev servers sometimes mis-type .wasm; fall back to buffered compile
    result = await WebAssembly.instantiate(await (await fetch("viewer.wasm")).arrayBuffer(), {});
  }
  wasm = result.instance.exports;
}

/* Copy a JS string into wasm memory, return [ptr, len]. */
function pushString(s) {
  const bytes = new TextEncoder().encode(s);
  const ptr = wasm.wa_alloc(bytes.length);
  new Uint8Array(wasm.memory.buffer, ptr, bytes.length).set(bytes);
  return [ptr, bytes.length];
}

function checkLogin(user, pass) {
  const [uPtr, uLen] = pushString(user);
  const [pPtr, pLen] = pushString(pass);
  return wasm.wa_check_login(uPtr, uLen, pPtr, pLen) === 1;
}

/* All-or-nothing load: every manifest image is fetched, decoded, and
 * downscaled into wasm memory before the first image is shown. */
async function loadAll() {
  const manifest = await (await fetch("manifest.json")).json();
  const urls = manifest.images;
  let done = 0;
  loaderText.textContent = `Loading 0 / ${urls.length}…`;
  for (const url of urls) {
    const buf = await (await fetch(url)).arrayBuffer();
    const ptr = wasm.wa_alloc(buf.byteLength);
    new Uint8Array(wasm.memory.buffer, ptr, buf.byteLength).set(new Uint8Array(buf));
    if (!wasm.wa_load_image(ptr, buf.byteLength)) {
      console.warn(`failed to decode ${url}`);
    }
    done++;
    loaderText.textContent = `Loading ${done} / ${urls.length}…`;
  }
  const mb = (n) => (n / 1024 / 1024).toFixed(1) + " MB";
  console.log(
    `wasm container loaded: ${wasm.wa_image_count()} images, ` +
    `${mb(Number(wasm.wa_pixel_bytes()))} of pixels, ` +
    `${mb(Number(wasm.wa_heap_bytes()))} linear memory`
  );
}

function blit() {
  const w = wasm.wa_fb_width();
  const h = wasm.wa_fb_height();
  const ptr = wasm.wa_fb_ptr();
  if (!w || !h || !ptr) return;
  canvas.width = w;
  canvas.height = h;
  const px = new Uint8ClampedArray(wasm.memory.buffer, ptr, w * h * 4);
  ctx.putImageData(new ImageData(px, w, h), 0, 0);
}

function advance() {
  wasm.wa_advance();
  blit();
}

function isAdvanceKey(e) {
  if (["Shift", "Control", "Alt", "Meta"].includes(e.key)) return false;
  if (/^F([1-9]|1[0-2])$/.test(e.key)) return false; // keep refresh/devtools usable
  return true;
}

function startViewer() {
  advance(); // initial state: first image shown
  window.addEventListener("keydown", (e) => {
    if (!isAdvanceKey(e)) return;
    e.preventDefault();
    advance();
  });
  window.addEventListener("mousedown", () => advance());
}

loginForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  const user = document.getElementById("user").value;
  const pass = document.getElementById("pass").value;
  if (!checkLogin(user, pass)) {
    loginError.textContent = "Invalid credentials.";
    return;
  }
  loginBox.hidden = true;
  loaderBox.hidden = false;
  await loadAll();
  loaderBox.hidden = true;
  stage.hidden = false;
  startViewer();
});

initWasm().catch((err) => {
  loginError.textContent = "Failed to load wasm module.";
  console.error(err);
});
