import {browserProxyFactory} from './new_tab_page_third_party.mojom-webui.js';

interface Pin {
  id: string;
  name: string;
  url: string;
}

interface Elements {
  add: HTMLButtonElement;
  date: HTMLTimeElement;
  editor: HTMLDialogElement;
  query: HTMLInputElement;
  'site-name': HTMLInputElement;
  'site-url': HTMLInputElement;
  'site-template': HTMLTemplateElement;
}

function select<K extends keyof Elements>(id: K): Elements[K];
function select(id: string): HTMLElement;
function select(id: string): HTMLElement {
  const node = document.getElementById(id);
  if (!node) throw new Error('Missing page control: ' + id);
  return node;
}
const pinsKey = "flint.pinnedSites.v1";
const defaultPins = [
  { id: "wikipedia", name: "Wikipedia", url: "https://www.wikipedia.org/" },
  { id: "github", name: "GitHub", url: "https://github.com/" },
  { id: "archive", name: "Internet Archive", url: "https://archive.org/" },
];
const editor = select("editor");
const query = select("query");
let editing: Pin|null = null;
let saving = false;

function feedback(id: string, message = "") {
  const region = select(id);
  region.textContent = message;
  region.hidden = !message;
}

function address(text: string, requireUrl: true): string;
function address(text: string, requireUrl?: false): string|null;
function address(text: string, requireUrl = false): string|null {
  const value = text.trim();
  const localHost = /^(?:localhost|127(?:\.\d{1,3}){3}|\[::1\])(?=[:/?#]|$)/i.test(value);
  const hostPort = /^(?:\[[a-fA-F\d:]+\]|[\w.-]+):\d+(?=[/?#]|$)/.test(value);
  const scheme = /^[a-z][a-z\d.+-]*:/i.test(value);
  const webScheme = /^https?:\/\//i.test(value);
  const queryOperator = /^(site|filetype|intitle|inurl|before|after):/i.test(value);
  if (!requireUrl && queryOperator) return null;
  if ((scheme && !webScheme && !hostPort) || /^[\\/]/.test(value)) {
    throw new Error("Enter an HTTP or HTTPS address.");
  }
  const hostLike = localHost || hostPort || /^[^\s/:?#]+\.[^\s/:?#]+(?:[/?#][^\s]*)?$/u.test(value)
    || /^\[[a-f\d:]+\](?=[/?#]|$)/i.test(value);
  if (!webScheme && !hostLike && !requireUrl) return null;
  if (!value || /[\s\\\u0000-\u001f]/u.test(value) || /^https?:\/{3}/i.test(value)) {
    throw new Error("Check the web address and try again.");
  }
  let parsed;
  try {
    parsed = new URL(webScheme ? value : (localHost ? "http://" : "https://") + value);
  } catch {
    throw new Error("Check the web address and try again.");
  }
  if (!parsed.hostname || parsed.username || parsed.password) {
    throw new Error("Use a web address without an embedded username or password.");
  }
  return parsed.href;
}

function readPins(): Pin[] {
  const data = localStorage.getItem(pinsKey);
  if (data === null) return defaultPins;
  const pins = JSON.parse(data);
  if (!Array.isArray(pins) || pins.some((pin) => !pin || typeof pin.id !== "string"
      || typeof pin.name !== "string" || !pin.name.trim() || typeof pin.url !== "string"
      || address(pin.url, true) !== pin.url)) {
    throw new Error("Saved sites could not be read.");
  }
  return pins;
}

function setMonogram(node: HTMLElement, name: string, host: string) {
  if (host === "wikipedia.org") {
    node.dataset['mark'] = "wiki";
    node.textContent = "W";
  } else if (host === "github.com") {
    node.dataset['mark'] = "code";
    node.textContent = "<>";
  } else if (host === "archive.org") {
    node.dataset['mark'] = "archive";
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    const use = document.createElementNS(svg.namespaceURI, "use");
    use.setAttribute("href", "#i-archive");
    svg.append(use);
    node.append(svg);
  } else {
    node.textContent = Array.from(name.trim())[0] ?? "";
  }
}

function renderPins() {
  const list = select("sites");
  try {
    const pins = readPins();
    const nodes = pins.map((pin) => {
      const item = select("site-template").content.firstElementChild!.cloneNode(true) as HTMLElement;
      const link = item.querySelector("a")!;
      link.href = pin.url;
      link.querySelector("strong")!.textContent = pin.name;
      const host = new URL(pin.url).host.replace(/^www\./i, "");
      link.querySelector("small")!.textContent = host;
      setMonogram(link.querySelector<HTMLElement>(".monogram")!, pin.name, host);
      const edit = item.querySelector("button")!;
      edit.dataset['id'] = pin.id;
      edit.title = "Edit " + pin.name;
      edit.setAttribute("aria-label", edit.title);
      edit.addEventListener("click", () => openEditor(pin));
      return item;
    });
    list.replaceChildren(...nodes);
    select("empty").hidden = pins.length !== 0;
    select("add").disabled = false;
    feedback("site-error");
  } catch {
    select("add").disabled = true;
    feedback("site-error", "Flint could not read the pinned sites in this profile.");
  }
}

function openEditor(pin: Pin|null = null) {
  editing = pin;
  select("editor-title").textContent = pin ? "Edit site" : "Add site";
  select("site-name").value = pin?.name ?? "";
  select("site-url").value = pin?.url ?? "";
  select("remove").hidden = !pin;
  feedback("editor-error");
  editor.showModal();
}

async function savePin(remove = false) {
  if (saving) return;
  saving = true;
  const original = editing;
  try {
    const name = select("site-name").value.trim();
    if (!remove && !name) throw new Error("Enter a site name.");
    const updated = remove ? null : {
      id: original?.id ?? crypto.randomUUID(),
      name,
      url: address(select("site-url").value, true),
    };
    await navigator.locks.request(pinsKey, () => {
      const pins = readPins().slice();
      if (original) {
        const index = pins.findIndex((pin) => pin.id === original.id);
        if (!pins[index] || pins[index].name !== original.name || pins[index].url !== original.url) {
          throw new Error("This site changed in another tab. Close this window and reopen it to edit.");
        }
        if (remove) pins.splice(index, 1);
        else if (updated) pins[index] = updated;
      } else if (updated) {
        pins.push(updated);
      }
      localStorage.setItem(pinsKey, JSON.stringify(pins));
    });
    editor.close();
    renderPins();
    const focusTarget = updated && [...document.querySelectorAll<HTMLButtonElement>(".edit")].find((button) => button.dataset['id'] === updated.id);
    (focusTarget || select("add")).focus();
  } catch (error) {
    feedback("editor-error", error instanceof Error && !(error instanceof DOMException) ? error.message : "Flint could not save the change in this profile.");
  } finally {
    saving = false;
  }
}

function displayDate() {
  const now = new Date();
  const time = select("date");
  time.dateTime = [now.getFullYear(), String(now.getMonth() + 1).padStart(2, "0"), String(now.getDate()).padStart(2, "0")].join("-");
  time.textContent = new Intl.DateTimeFormat(undefined, { weekday: "long", month: "long", day: "numeric" }).format(now);
}

select("search").addEventListener("submit", async (event) => {
  event.preventDefault();
  const text = query.value.trim();
  if (!text) return query.focus();
  try {
    const url = address(text);
    if (url) location.assign(url);
    else {
      try {
        const {started} = await browserProxyFactory.getInstance().handler.search(text);
        if (!started) throw new Error("Missing default search provider");
      } catch {
        feedback("search-error", "Search is unavailable. Check the default search engine in browser settings.");
      }
    }
  } catch (error) {
    feedback("search-error", error instanceof Error ? error.message : "Check the address and try again.");
  }
});
async function showSearchProvider() {
  try {
    const {name} = await browserProxyFactory.getInstance().handler.getSearchProviderName();
    if (name) {
      query.placeholder = "Search " + name + " or enter a URL";
      query.setAttribute("aria-label", query.placeholder);
    }
  } catch {
    // The generic field label also covers profiles without a search engine.
  }
}
query.addEventListener("input", () => {
  select("clear").hidden = !query.value;
  feedback("search-error");
});
select("clear").addEventListener("click", () => {
  query.value = "";
  query.dispatchEvent(new Event("input"));
  query.focus();
});
select("add").addEventListener("click", () => openEditor());
select("close").addEventListener("click", () => editor.close());
select("cancel").addEventListener("click", () => editor.close());
select("remove").addEventListener("click", () => savePin(true));
select("site-form").addEventListener("submit", (event) => {
  event.preventDefault();
  savePin();
});
window.addEventListener("storage", (event) => {
  if (event.key === pinsKey || event.key === null) renderPins();
});
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) displayDate();
});
displayDate();
renderPins();
void showSearchProvider();
