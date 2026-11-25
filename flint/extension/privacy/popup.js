'use strict';

const blocking = document.querySelector('#blocking');
const status = document.querySelector('#status');
const ruleset = 'flint_trackers';

async function readState() {
  blocking.disabled = true;
  const active = await chrome.declarativeNetRequest.getEnabledRulesets();
  blocking.checked = active.includes(ruleset);
  blocking.disabled = false;
}

blocking.addEventListener('change', async () => {
  blocking.disabled = true;
  status.textContent = '';
  try {
    const change = blocking.checked ? { enableRulesetIds: [ruleset] } : { disableRulesetIds: [ruleset] };
    await chrome.declarativeNetRequest.updateEnabledRulesets(change);
  } catch {
    status.textContent = 'Couldn’t save this change.';
  }
  await readState().catch(() => { status.textContent = 'Couldn’t read the blocking setting.'; });
});

document.querySelector('#settings').addEventListener('click', async () => {
  try {
    await chrome.tabs.create({ url: 'chrome://settings/privacy' });
    window.close();
  } catch {
    status.textContent = 'Open chrome://settings/privacy in the address bar.';
  }
});

async function showDomains() {
  const response = await fetch('trackers.json');
  if (!response.ok) throw new Error('Could not load domains');
  const rules = await response.json();
  const list = document.querySelector('#domains');
  for (const domain of rules[0].condition.requestDomains) {
    const item = document.createElement('li');
    item.textContent = domain;
    list.append(item);
  }
}

readState().catch(() => { status.textContent = 'Couldn’t read the blocking setting.'; });
showDomains().catch(() => { status.textContent = 'Couldn’t load the covered domains.'; });
