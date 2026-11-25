import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash, X509Certificate} from 'node:crypto';
import {mkdtemp, readFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {promisify} from 'node:util';

const run = promisify(execFile);
const [browser, scratch] = process.argv.slice(2);
const directory = await mkdtemp(join(scratch, 'network-'));
const keyPath = join(directory, 'fixture.key');
const certPath = join(directory, 'fixture.crt');
await run('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
  '-subj', '/CN=publisher.test', '-addext', 'subjectAltName=DNS:publisher.test,DNS:control.test,DNS:adsrvr.org',
  '-keyout', keyPath, '-out', certPath], {windowsHide: true});
const cert = await readFile(certPath);
const publicKey = new X509Certificate(cert).publicKey.export({format: 'der', type: 'spki'});
const fingerprint = createHash('sha256').update(publicKey).digest('base64');
const hits = new Set();

// Synchronous classic-script loads finish before Chromium dumps the DOM. A hit
// in the HTTPS server is independent evidence that a request left the browser.
const server = createServer({key: await readFile(keyPath), cert}, (request, response) => {
  const url = new URL(request.url, `https://${request.headers.host}`);
  const port = server.address().port;
  hits.add(url.href);
  response.setHeader('Cache-Control', 'no-store');
  if (url.pathname === '/publisher') {
    response.setHeader('Content-Type', 'text/html');
    response.end(`<!doctype html><title>Publisher fixture</title>
      <script src="https://adsrvr.org:${port}/pixel${url.search}"></script>
      <script src="https://control.test:${port}/control${url.search}"></script>
      <script src="https://control.test:${port}/redirect${url.search}"></script>`);
  } else if (url.pathname === '/redirect') {
    response.writeHead(302, {Location: `https://adsrvr.org:${port}/redirected-pixel${url.search}`});
    response.end();
  } else if (url.pathname === '/direct') {
    response.setHeader('Content-Type', 'text/html');
    response.end(`<!doctype html><title>First-party fixture</title><script src="/same-site${url.search}"></script>`);
  } else {
    response.setHeader('Content-Type', 'application/javascript');
    response.end('void 0');
  }
});
await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
const port = server.address().port;

async function visit(profile, url, title, featureSwitches = []) {
  const {stdout} = await run(browser, ['--headless', '--dump-dom', '--disable-extensions', '--no-first-run',
    '--no-default-browser-check', '--no-proxy-server', '--host-resolver-rules=MAP * 127.0.0.1',
    `--ignore-certificate-errors-spki-list=${fingerprint}`, `--user-data-dir=${profile}`,
    ...featureSwitches, url], {windowsHide: true, timeout: 60000});
  assert.ok(stdout.includes(`<title>${title}</title>`), `Unexpected result for ${url}: ${stdout.slice(0, 350)}`);
}

try {
  for (const mode of ['default', 'disabled']) {
    const profile = join(directory, mode);
    const switches = mode === 'default' ? [] : ['--disable-features=FlintTrackerBlocking'];
    const suffix = `?mode=${mode}`;
    await visit(profile, `https://publisher.test:${port}/publisher${suffix}`, 'Publisher fixture', switches);
    const sent = (host, path) => hits.has(`https://${host}:${port}/${path}${suffix}`);
    assert.equal(sent('adsrvr.org', 'pixel'), mode === 'disabled', `${mode}: cross-site tracker`);
    assert.equal(sent('control.test', 'control'), true, `${mode}: cross-site control`);
    assert.equal(sent('control.test', 'redirect'), true, `${mode}: redirect source`);
    assert.equal(sent('adsrvr.org', 'redirected-pixel'), mode === 'disabled', `${mode}: redirected tracker`);
    await visit(profile, `https://adsrvr.org:${port}/direct${suffix}`, 'First-party fixture', switches);
    assert.equal(sent('adsrvr.org', 'direct'), true, `${mode}: top-level navigation`);
    assert.equal(sent('adsrvr.org', 'same-site'), true, `${mode}: same-site script`);
    console.log(`Passed native ${mode} tests for direct and redirected tracker requests, unlisted requests, top-level navigation and same-site resources.`);
  }
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
