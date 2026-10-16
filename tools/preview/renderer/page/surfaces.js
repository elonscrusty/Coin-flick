// surfaces.js - draws SurfaceGuis in the 3D world.
//
// The Luau runtime lays every SurfaceGui out like Roblox (canvas = face studs x PixelsPerStud, or CanvasSize) and
// exports its paint list plus the face frame (centre, X = GUI right, Y = GUI up, Z = face normal). Here each one is
// painted into a 2D canvas (Frame / TextLabel / ImageLabel backgrounds, UICorner, UIStroke borders, text with
// TextStroke / contextual UIStroke outlines, image placeholders; avatar thumbnails (rbxthumb) as a neutral head
// placeholder) and put on a one-sided plane just off the face, depth tested like the parts. LightInfluence >= 0.5 is
// lit by the scene, below that it is drawn unlit (Roblox: 0 = full bright).
//
// Check pass (surfaceStats): the world is drawn flat black and each SurfaceGui's TEXT pixels (an ink mask: glyphs and
// their outlines only) in an id colour, once with the world (visible ink) and once without (unoccluded ink), so a
// regression can tell "no text", "text hidden behind geometry" and "text drawn on the wrong side" apart.
import * as THREE from 'three';
import { cframeMatrix } from './world.js';

function css(c, alphaMul = 1) {
  if (!c) return 'transparent';
  const a = (c.length > 3 ? c[3] : 1) * alphaMul;
  return `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a.toFixed(3)})`;
}

function roundRect(ctx, w, h, r) {
  ctx.beginPath();
  if (r > 0 && ctx.roundRect) ctx.roundRect(0, 0, w, h, Math.min(r, w / 2, h / 2));
  else ctx.rect(0, 0, w, h);
}

function fontOf(s) {
  return `${s.synth ? 'italic' : s.style} ${s.weight} ${s.size}px "${s.font}"`;
}

// Paints one item list. inkOnly: text glyphs (and their outlines) in white, nothing else (the check mask).
function paintList(ctx, items, scale, alpha, inkOnly) {
  for (const it of items) {
    if (it.t === 'group') { paintList(ctx, it.items, scale, alpha * it.alpha, inkOnly); continue; }
    if (it.t === 'path') continue;
    ctx.save();
    if (it.clip) {
      const [x0, y0, x1, y1] = it.clip;
      ctx.setTransform(scale, 0, 0, scale, 0, 0);
      ctx.beginPath();
      ctx.rect(x0, y0, x1 - x0, y1 - y0);
      ctx.clip();
    }
    const m = it.m;
    ctx.setTransform(scale * m[0], scale * m[1], scale * m[2], scale * m[3], scale * m[4], scale * m[5]);
    ctx.globalAlpha = alpha;
    if (!inkOnly) {
      if (it.bg) {
        ctx.fillStyle = css(it.bg);
        roundRect(ctx, it.w, it.h, it.radius || 0);
        ctx.fill();
      }
      if (it.image) {
        const src = it.image.src || '';
        if (src.startsWith('rbxthumb://')) {
          // avatar head shot: the real picture comes from Roblox; a neutral head placeholder here
          const r = Math.min(it.w, it.h) / 2;
          ctx.save();
          roundRect(ctx, it.w, it.h, it.radius || 0);
          ctx.clip();
          ctx.fillStyle = 'rgb(120,128,140)';
          ctx.fillRect(0, 0, it.w, it.h);
          ctx.fillStyle = 'rgb(232,200,150)';
          ctx.beginPath();
          ctx.arc(it.w / 2, it.h * 0.45, r * 0.42, 0, Math.PI * 2);
          ctx.fill();
          ctx.fillStyle = 'rgb(70,78,92)';
          ctx.fillRect(it.w * 0.2, it.h * 0.78, it.w * 0.6, it.h * 0.3);
          ctx.restore();
        } else {
          ctx.save();
          roundRect(ctx, it.w, it.h, it.radius || 0);
          ctx.clip();
          for (let x = -it.h; x < it.w; x += 12) {
            ctx.fillStyle = css(it.image.color, 0.45);
            ctx.beginPath();
            ctx.moveTo(x, it.h); ctx.lineTo(x + it.h, 0); ctx.lineTo(x + it.h + 6, 0); ctx.lineTo(x + 6, it.h);
            ctx.fill();
          }
          ctx.restore();
        }
      }
      if (it.border && it.border.w > 0) {
        ctx.strokeStyle = css(it.border.color);
        ctx.lineWidth = it.border.w;
        ctx.strokeRect(-it.border.w / 2, -it.border.w / 2, it.w + it.border.w, it.h + it.border.w);
      }
      if (it.stroke && it.stroke.thickness > 0 && it.stroke.color[3] > 0) {
        const t = it.stroke.thickness;
        const off = it.stroke.position === 'Inner' ? -t / 2 : it.stroke.position === 'Center' ? 0 : t / 2;
        ctx.save();
        ctx.translate(-off, -off);
        ctx.strokeStyle = css(it.stroke.color);
        ctx.lineWidth = t;
        roundRect(ctx, it.w + off * 2, it.h + off * 2, (it.radius || 0) + off);
        ctx.stroke();
        ctx.restore();
      }
    }
    if (it.text) {
      const t = it.text;
      ctx.translate(t.x, t.y);
      ctx.textBaseline = 'middle';
      ctx.textAlign = 'left';
      for (const line of t.lines) {
        for (const s of line.segs) {
          ctx.font = fontOf(s);
          const y = line.y + line.h / 2;
          const stroke = s.stroke || t.stroke || t.legacyStroke;
          if (stroke && stroke.thickness > 0 && stroke.color[3] > 0) {
            ctx.lineJoin = 'round';
            ctx.lineWidth = stroke.thickness * 2;
            ctx.strokeStyle = inkOnly ? '#fff' : css(stroke.color);
            ctx.strokeText(s.t, s.x, y);
          }
          ctx.fillStyle = inkOnly ? '#fff' : css(s.color);
          ctx.fillText(s.t, s.x, y);
        }
      }
    }
    ctx.restore();
  }
}

function textOf(items, out = []) {
  for (const it of items) {
    if (it.items) textOf(it.items, out);
    if (it.text) for (const l of it.text.lines) out.push(l.segs.map((s) => s.t).join(''));
  }
  return out;
}

export function surfaceFonts(surfaces) {
  const set = new Set();
  const walk = (items) => {
    for (const it of items) {
      if (it.items) walk(it.items);
      if (it.text) for (const l of it.text.lines) for (const s of l.segs) set.add(`${s.font}|${s.weight}|${s.style}`);
    }
  };
  for (const s of surfaces || []) walk(s.items);
  return [...set];
}

function canvasFor(s, inkOnly) {
  const [cw, ch] = s.canvas;
  // keep big boards sharp but bounded: at least ~768 px on the long side, at most 2048
  const longSide = Math.max(cw, ch);
  const scale = Math.min(2048 / longSide, Math.max(1, 768 / longSide));
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(cw * scale));
  canvas.height = Math.max(1, Math.round(ch * scale));
  const ctx = canvas.getContext('2d');
  paintList(ctx, s.items, scale, 1, inkOnly);
  return canvas;
}

function planeMatrix(s) {
  const m = cframeMatrix(s.cf);
  // a hair off the face so it never z-fights the part it sits on
  m.multiply(new THREE.Matrix4().makeTranslation(0, 0, 0.012));
  m.multiply(new THREE.Matrix4().makeScale(s.studs[0], s.studs[1], 1));
  return m;
}

const unitPlane = new THREE.PlaneGeometry(1, 1);

// three's NeutralToneMapping (the page's output tone mapping), per pixel in linear RGB.
function neutral(c0, exposure) {
  const start = 0.8 - 0.04, desat = 0.15;
  const c = [c0[0] * exposure, c0[1] * exposure, c0[2] * exposure];
  const x = Math.min(c[0], c[1], c[2]);
  const offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
  let r = c[0] - offset, g = c[1] - offset, b = c[2] - offset;
  const peak = Math.max(r, g, b);
  if (peak < start) return [r, g, b];
  const d = 1 - start;
  const newPeak = 1 - (d * d) / (peak + d - start);
  const k = newPeak / peak;
  r *= k; g *= k; b *= k;
  const gg = 1 - 1 / (desat * (peak - newPeak) + 1);
  return [r + (newPeak - r) * gg, g + (newPeak - g) * gg, b + (newPeak - b) * gg];
}
const toLinear = (v) => (v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4));

// Roblox draws a SurfaceGui with LightInfluence 0 in its own colours. The page tone maps the whole frame, so the
// unlit GUI texture is pre-distorted with the inverse of the tone mapping (and the exposure) (damped fixed point per colour, capped below
// the bloom threshold) and lands on screen in its nominal sRGB colour.
function untoneTexture(canvas, exposure) {
  const ctx = canvas.getContext('2d');
  const { width: w, height: h } = canvas;
  const src = ctx.getImageData(0, 0, w, h).data;
  const out = new Uint16Array(w * h * 4);
  const cache = new Map();
  const half = THREE.DataUtils.toHalfFloat;
  for (let p = 0; p < src.length; p += 4) {
    const key = (src[p] << 16) | (src[p + 1] << 8) | src[p + 2];
    let v = cache.get(key);
    if (!v) {
      const t = [toLinear(src[p] / 255), toLinear(src[p + 1] / 255), toLinear(src[p + 2] / 255)];
      const x = t.slice();
      for (let i = 0; i < 80; i++) {
        const n = neutral(x, exposure);
        for (let k = 0; k < 3; k++) {
          if (t[k] <= 1e-5) x[k] = 0;
          else x[k] = Math.min(1.85, Math.max(1e-6, x[k] * Math.sqrt(t[k] / Math.max(n[k], 1e-6))));
        }
      }
      v = [half(x[0]), half(x[1]), half(x[2])];
      cache.set(key, v);
    }
    // canvas rows run top-down, texture rows bottom-up
    const px = (p / 4) % w, py = Math.floor(p / 4 / w);
    const q = ((h - 1 - py) * w + px) * 4;
    out[q] = v[0]; out[q + 1] = v[1]; out[q + 2] = v[2]; out[q + 3] = half(src[p + 3] / 255);
  }
  const tex = new THREE.DataTexture(out, w, h, THREE.RGBAFormat, THREE.HalfFloatType);
  tex.colorSpace = THREE.NoColorSpace;
  tex.magFilter = THREE.LinearFilter;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.generateMipmaps = true;
  tex.needsUpdate = true;
  return tex;
}

// Adds every SurfaceGui to `scene` (call after fonts are loaded). Returns the records for the check pass.
export function addSurfaces(scene, surfaces, exposure = 1) {
  const out = [];
  for (const s of surfaces || []) {
    if (!s.enabled || !s.items.length) continue;
    const lit = s.lightInfluence >= 0.5;
    const canvas = canvasFor(s, false);
    let tex;
    if (lit) {
      tex = new THREE.CanvasTexture(canvas);
      tex.colorSpace = THREE.SRGBColorSpace;
    } else {
      tex = untoneTexture(canvas, exposure);
    }
    tex.anisotropy = 8;
    const opts = { map: tex, fog: false, transparent: true, depthWrite: false, side: THREE.FrontSide, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2, toneMapped: false };
    const mat = lit ? new THREE.MeshStandardMaterial({ ...opts, roughness: 0.9, metalness: 0, toneMapped: true }) : new THREE.MeshBasicMaterial(opts);
    if (s.alwaysOnTop) { mat.depthTest = false; }
    const mesh = new THREE.Mesh(unitPlane, mat);
    mesh.matrixAutoUpdate = false;
    mesh.matrix.copy(planeMatrix(s));
    mesh.renderOrder = s.alwaysOnTop ? 10 : 2;
    scene.add(mesh);
    out.push({ s, mesh });
  }
  return out;
}

// Visible / unoccluded text pixels per SurfaceGui from the camera (see the header).
export function surfaceStats(renderer, scene, cam, added, W, H) {
  if (!added.length) return [];
  const target = new THREE.WebGLRenderTarget(W, H, { samples: 0 });
  const idScene = new THREE.Scene();
  const recs = added.map((a, i) => {
    const mask = new THREE.CanvasTexture(canvasFor(a.s, true));
    const mat = new THREE.MeshBasicMaterial({ color: new THREE.Color().setRGB(((i + 1) % 256) / 255, 1, Math.floor((i + 1) / 256) / 255, THREE.LinearSRGBColorSpace), alphaMap: mask, alphaTest: 0.5, side: THREE.FrontSide, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2, toneMapped: false });
    const mesh = new THREE.Mesh(unitPlane, mat);
    mesh.matrixAutoUpdate = false;
    mesh.matrix.copy(a.mesh.matrix);
    idScene.add(mesh);
    return { a, mesh };
  });
  const savedTone = renderer.toneMapping;
  const savedAuto = renderer.autoClear;
  const savedBg = scene.background;
  const savedFog = scene.fog;
  renderer.toneMapping = THREE.NoToneMapping;
  const hidden = [];
  for (const a of added) { a.mesh.visible = false; }
  scene.traverse((o) => { if ((o.isSprite || o.isPoints || o.isLine) && o.visible) { o.visible = false; hidden.push(o); } });
  scene.overrideMaterial = new THREE.MeshBasicMaterial({ color: 0x000000 });
  scene.background = new THREE.Color(0, 0, 0);
  scene.fog = null;
  const count = () => {
    const buf = new Uint8Array(W * H * 4);
    renderer.readRenderTargetPixels(target, 0, 0, W, H, buf);
    const n = new Array(recs.length + 1).fill(0);
    for (let p = 0; p < buf.length; p += 4) {
      if (buf[p + 1] > 200) { const id = buf[p] + 256 * buf[p + 2]; if (id > 0 && id <= recs.length) n[id]++; }
    }
    return n;
  };
  renderer.setRenderTarget(target);
  renderer.setClearColor(0x000000, 1);
  renderer.clear();
  renderer.render(scene, cam);
  renderer.autoClear = false;
  renderer.render(idScene, cam);
  const visible = count();
  renderer.autoClear = true;
  renderer.clear();
  renderer.render(idScene, cam);
  const open = count();
  renderer.setRenderTarget(null);
  scene.overrideMaterial = null;
  scene.background = savedBg;
  scene.fog = savedFog;
  renderer.toneMapping = savedTone;
  renderer.autoClear = savedAuto;
  for (const o of hidden) o.visible = true;
  for (const a of added) a.mesh.visible = true;
  target.dispose();
  return recs.map((r, i) => ({ path: r.a.s.path, face: r.a.s.face, text: textOf(r.a.s.items).join(' | '), inkPx: visible[i + 1], openPx: open[i + 1] }));
}
