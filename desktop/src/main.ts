import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

// The frontend drives the embedded stremio-core engine through the Tauri commands wired in lib.rs:
// dispatch actions, read model fields back as JSON, and re-render when the engine emits a NewState
// `core-event`. Flow: Home board (poster rails) -> click a poster -> meta details + streams ->
// click a direct/debrid stream -> play in an HTML5 video. The same engine the iOS/Apple TV apps use.

interface MetaItem {
  id: string;
  type: string;
  name: string;
  poster?: string;
  background?: string;
  description?: string;
  releaseInfo?: string;
}
interface Loadable<T> {
  type: string; // "Ready" | "Loading" | "Err"
  content?: T;
}
interface CatalogPage {
  request?: { path?: { id?: string; type?: string } };
  content?: Loadable<MetaItem[]>;
}
interface Board {
  catalogs?: CatalogPage[][];
}
interface Stream {
  url?: string;
  name?: string;
  description?: string;
}
interface MetaEntry {
  content?: Loadable<MetaItem>;
}
interface StreamGroup {
  content?: Loadable<Stream[]>;
}
interface MetaDetails {
  metaItems?: MetaEntry[];
  streams?: StreamGroup[];
}

// The id of the title whose detail overlay is open (null = showing the board).
let openDetailId: string | null = null;

async function dispatch(field: string, action: unknown): Promise<void> {
  await invoke("engine_dispatch", { actionJson: JSON.stringify({ field, action }) });
}
async function getState<T>(field: string): Promise<T | null> {
  const json = await invoke<string>("engine_get_state", { fieldJson: JSON.stringify(field) });
  try {
    return JSON.parse(json) as T;
  } catch {
    return null;
  }
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c] as string,
  );
}
function httpUrl(value: string | undefined): string {
  return value && /^https?:\/\//i.test(value) ? value : "";
}
function setStatus(text: string): void {
  const el = document.getElementById("status");
  if (el) el.textContent = text;
}
function el(id: string): HTMLElement | null {
  return document.getElementById(id);
}

// ---- Home board ----------------------------------------------------------

function renderBoard(board: Board | null): void {
  const content = el("content");
  if (!content || !board?.catalogs) return;
  const rails: string[] = [];
  for (const group of board.catalogs) {
    const page = group.find((p) => p.content?.type === "Ready" && (p.content.content?.length ?? 0) > 0);
    if (!page?.content?.content) continue;
    const id = page.request?.path?.id ?? "Catalog";
    const type = page.request?.path?.type ?? "";
    const title = escapeHtml(`${id} ${type}`.trim());
    const cards = page.content.content
      .slice(0, 30)
      .map((item) => {
        const name = escapeHtml(item.name ?? "");
        const art = httpUrl(item.poster);
        const inner = art
          ? `<img class="art" loading="lazy" src="${escapeHtml(art)}" alt="${name}" />`
          : `<div class="art"></div>`;
        return `<div class="poster" data-type="${escapeHtml(item.type)}" data-id="${escapeHtml(item.id)}" title="${name}">${inner}<div class="name">${name}</div></div>`;
      })
      .join("");
    rails.push(`<section><h2 class="rail-title">${title}</h2><div class="rail">${cards}</div></section>`);
  }
  if (rails.length) {
    content.innerHTML = rails.join("");
    setStatus("");
  }
}

// ---- Detail (meta + streams) --------------------------------------------

async function openDetail(type: string, id: string): Promise<void> {
  openDetailId = id;
  const overlay = el("detail");
  if (overlay) {
    overlay.classList.remove("hidden");
    overlay.innerHTML = `<div class="detail-loading">Loading…</div>`;
  }
  await dispatch("meta_details", {
    action: "Load",
    args: {
      model: "MetaDetails",
      args: { metaPath: { resource: "meta", type, id, extra: [] }, guessStream: true, streamPath: null },
    },
  });
  void getState<MetaDetails>("meta_details").then(renderDetail);
}

function closeDetail(): void {
  openDetailId = null;
  el("detail")?.classList.add("hidden");
  void dispatch("meta_details", { action: "Unload" });
}

function renderDetail(md: MetaDetails | null): void {
  const overlay = el("detail");
  if (!overlay || openDetailId === null) return;
  const meta = md?.metaItems?.map((m) => (m.content?.type === "Ready" ? m.content.content : null)).find(Boolean) as
    | MetaItem
    | undefined;
  if (!meta) return;

  const streams: Stream[] = (md?.streams ?? [])
    .flatMap((g) => (g.content?.type === "Ready" ? (g.content.content ?? []) : []))
    .filter((s) => httpUrl(s.url)); // direct/debrid only (server-less desktop)

  const bg = httpUrl(meta.background);
  const streamList = streams.length
    ? streams
        .map((s) => {
          const label = escapeHtml(s.name || s.description || "Stream");
          return `<button class="stream" data-url="${escapeHtml(s.url as string)}">${label}</button>`;
        })
        .join("")
    : `<p class="muted">No playable streams. Sign in or install a stream add-on (e.g. Torrentio) to play. (Torrent-only sources need the embedded server, which is Apple TV / iOS for now.)</p>`;

  overlay.innerHTML = `
    <div class="detail-bg" ${bg ? `style="background-image:linear-gradient(to bottom, rgba(14,11,20,.4), var(--bg)), url('${escapeHtml(bg)}')"` : ""}></div>
    <button class="back" data-action="close-detail">‹ Back</button>
    <div class="detail-body">
      <h1>${escapeHtml(meta.name ?? "")}</h1>
      <p class="meta-sub">${escapeHtml([meta.releaseInfo, meta.type].filter(Boolean).join(" · "))}</p>
      <p class="desc">${escapeHtml(meta.description ?? "")}</p>
      <h3>Streams</h3>
      <div class="streams">${streamList}</div>
    </div>`;
}

// ---- Player --------------------------------------------------------------

function openPlayer(url: string): void {
  const player = el("player");
  if (!player) return;
  player.classList.remove("hidden");
  player.innerHTML = `
    <button class="back" data-action="close-player">‹ Back</button>
    <video class="video" controls autoplay src="${escapeHtml(url)}"></video>`;
}
function closePlayer(): void {
  const player = el("player");
  if (!player) return;
  player.querySelector("video")?.pause();
  player.innerHTML = "";
  player.classList.add("hidden");
}

// ---- Wiring --------------------------------------------------------------

function wireClicks(): void {
  document.body.addEventListener("click", (ev) => {
    const target = ev.target as HTMLElement;
    const action = target.closest<HTMLElement>("[data-action]")?.dataset.action;
    if (action === "close-detail") return closeDetail();
    if (action === "close-player") return closePlayer();

    const stream = target.closest<HTMLElement>(".stream");
    if (stream?.dataset.url) return openPlayer(stream.dataset.url);

    const poster = target.closest<HTMLElement>(".poster");
    if (poster?.dataset.id && poster.dataset.type) {
      void openDetail(poster.dataset.type, poster.dataset.id);
    }
  });
}

async function start(): Promise<void> {
  wireClicks();
  // Re-render the visible surface whenever the engine reports new state.
  await listen("core-event", () => {
    if (openDetailId) void getState<MetaDetails>("meta_details").then(renderDetail);
    else void getState<Board>("board").then(renderBoard);
  });

  await dispatch("board", { action: "Load", args: { model: "CatalogsWithExtra", args: { type: null, extra: [] } } });
  await dispatch("board", {
    action: "CatalogsWithExtra",
    args: { action: "LoadRange", args: { start: 0, end: 30 } },
  });

  for (let i = 0; i < 8; i++) {
    setTimeout(() => {
      if (!openDetailId) void getState<Board>("board").then(renderBoard);
    }, i * 700);
  }
}

void start();
