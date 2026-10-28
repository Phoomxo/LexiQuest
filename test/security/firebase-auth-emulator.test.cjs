const { beforeEach, describe, it } = require('node:test');
const assert = require('node:assert/strict');

const projectId = 'demo-lexiquest-auth-test';
const apiKey = 'demo-api-key';
const authBase =
  'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const emulatorBase =
  `http://127.0.0.1:9099/emulator/v1/projects/${projectId}`;

async function request(path, body) {
  const response = await fetch(`${authBase}/${path}?key=${apiKey}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(`${response.status}: ${JSON.stringify(payload)}`);
  }
  return payload;
}

async function clearAccounts() {
  const response = await fetch(`${emulatorBase}/accounts`, {
    method: 'DELETE',
  });
  assert.equal(response.status, 200);
}

async function latestOobCode(email, requestType) {
  const response = await fetch(`${emulatorBase}/oobCodes`);
  assert.equal(response.status, 200);
  const payload = await response.json();
  const match = [...payload.oobCodes]
    .reverse()
    .find((entry) => entry.email === email && entry.requestType === requestType);
  assert.ok(match, `missing ${requestType} OOB code for ${email}`);
  return match.oobCode;
}

beforeEach(clearAccounts);

describe('Firebase account field journey', () => {
  it('registers, verifies email, signs in, changes password, and signs out', async () => {
    const email = 'participant@example.com';
    const password = 'initial-password';
    const registered = await request('accounts:signUp', {
      email,
      password,
      returnSecureToken: true,
    });
    assert.equal(registered.email, email);
    assert.ok(registered.idToken);

    await request('accounts:sendOobCode', {
      requestType: 'VERIFY_EMAIL',
      idToken: registered.idToken,
    });
    const verificationCode = await latestOobCode(email, 'VERIFY_EMAIL');
    await request('accounts:update', { oobCode: verificationCode });

    const signedIn = await request('accounts:signInWithPassword', {
      email,
      password,
      returnSecureToken: true,
    });
    assert.equal(signedIn.localId, registered.localId);

    await request('accounts:update', {
      idToken: signedIn.idToken,
      password: 'changed-password',
      returnSecureToken: true,
    });
    const signedInAgain = await request('accounts:signInWithPassword', {
      email,
      password: 'changed-password',
      returnSecureToken: true,
    });
    assert.equal(signedInAgain.localId, registered.localId);
  });

  it('resets a forgotten password using the generated email action code', async () => {
    const email = 'reset@example.com';
    await request('accounts:signUp', {
      email,
      password: 'before-reset',
      returnSecureToken: true,
    });
    await request('accounts:sendOobCode', {
      requestType: 'PASSWORD_RESET',
      email,
    });
    const resetCode = await latestOobCode(email, 'PASSWORD_RESET');
    await request('accounts:resetPassword', {
      oobCode: resetCode,
      newPassword: 'after-reset',
    });
    const signedIn = await request('accounts:signInWithPassword', {
      email,
      password: 'after-reset',
      returnSecureToken: true,
    });
    assert.equal(signedIn.email, email);
  });

  it('upgrades an anonymous credential to email without changing the uid', async () => {
    const anonymous = await request('accounts:signUp', {
      returnSecureToken: true,
    });
    const linked = await request('accounts:update', {
      idToken: anonymous.idToken,
      email: 'guest-upgrade@example.com',
      password: 'upgrade-password',
      returnSecureToken: true,
    });
    assert.equal(linked.localId, anonymous.localId);
    assert.equal(linked.email, 'guest-upgrade@example.com');
  });
});
