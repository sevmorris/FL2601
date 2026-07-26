// An independent implementation of the FL2601 v1 format, written against
// WebCrypto rather than CryptoKit.
//
// This exists to cross-check Services/CipherEngine.swift. Two implementations
// written against different crypto libraries agreeing on every byte is much
// stronger evidence of correctness than one implementation agreeing with
// itself — that is how the payload-length off-by-one was caught.
//
// Usage:
//   node reference-impl.mjs encrypt <password> <plaintext> [iterations]
//   node reference-impl.mjs decrypt <password> <ciphertext>

const MAGIC = new Uint8Array([0x46, 0x4c, 0x32, 0x36]); // "FL26"
const VERSION = 1;
const KDF_PBKDF2_HMAC_SHA256 = 1;

const HEADER_LEN = 10;
const SALT_LEN = 16;
const NONCE_LEN = 12;
const TAG_LEN = 16;
const MIN_PAYLOAD = HEADER_LEN + SALT_LEN + NONCE_LEN + TAG_LEN;

const DEFAULT_ITERATIONS = 600000;
const MIN_ITERATIONS = 10000;
const MAX_ITERATIONS = 10000000;

function makeHeader(iterations) {
  const header = new Uint8Array(HEADER_LEN);
  header.set(MAGIC, 0);
  header[4] = VERSION;
  header[5] = KDF_PBKDF2_HMAC_SHA256;
  header[6] = (iterations >>> 24) & 0xff;
  header[7] = (iterations >>> 16) & 0xff;
  header[8] = (iterations >>> 8) & 0xff;
  header[9] = iterations & 0xff;
  return header;
}

async function deriveKey(password, salt, iterations, usage) {
  const keyMaterial = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveKey']
  );
  return crypto.subtle.deriveKey(
    { name: 'PBKDF2', salt, iterations, hash: 'SHA-256' },
    keyMaterial,
    { name: 'AES-GCM', length: 256 },
    false,
    [usage]
  );
}

async function encrypt(plaintext, password, iterations = DEFAULT_ITERATIONS) {
  const salt = crypto.getRandomValues(new Uint8Array(SALT_LEN));
  const nonce = crypto.getRandomValues(new Uint8Array(NONCE_LEN));
  const header = makeHeader(iterations);
  const key = await deriveKey(password, salt, iterations, 'encrypt');

  // additionalData binds the header to the tag, matching CryptoKit's
  // `authenticating:` argument.
  const sealed = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce, additionalData: header },
    key,
    new TextEncoder().encode(plaintext)
  );

  const blob = new Uint8Array(HEADER_LEN + SALT_LEN + NONCE_LEN + sealed.byteLength);
  blob.set(header, 0);
  blob.set(salt, HEADER_LEN);
  blob.set(nonce, HEADER_LEN + SALT_LEN);
  blob.set(new Uint8Array(sealed), HEADER_LEN + SALT_LEN + NONCE_LEN);

  return Buffer.from(blob).toString('base64');
}

async function decrypt(ciphertext, password) {
  const cleaned = ciphertext.replace(/\s+/g, '');
  const blob = new Uint8Array(Buffer.from(cleaned, 'base64'));

  if (blob.length < MIN_PAYLOAD) throw new Error('This does not look like an FL2601 message.');
  for (let i = 0; i < MAGIC.length; i++) {
    if (blob[i] !== MAGIC[i]) throw new Error('This does not look like an FL2601 message.');
  }
  if (blob[4] !== VERSION) throw new Error(`Message uses format version ${blob[4]}; this app supports version ${VERSION}.`);
  if (blob[5] !== KDF_PBKDF2_HMAC_SHA256) throw new Error(`Message uses an unknown key derivation function (id ${blob[5]}).`);

  const iterations = ((blob[6] << 24) | (blob[7] << 16) | (blob[8] << 8) | blob[9]) >>> 0;
  if (iterations < MIN_ITERATIONS || iterations > MAX_ITERATIONS) {
    throw new Error(`Message declares ${iterations} iterations, outside the accepted range.`);
  }

  const header = blob.slice(0, HEADER_LEN);
  const salt = blob.slice(HEADER_LEN, HEADER_LEN + SALT_LEN);
  const nonce = blob.slice(HEADER_LEN + SALT_LEN, HEADER_LEN + SALT_LEN + NONCE_LEN);
  const sealed = blob.slice(HEADER_LEN + SALT_LEN + NONCE_LEN);

  const key = await deriveKey(password, salt, iterations, 'decrypt');
  try {
    const plaintext = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: nonce, additionalData: header },
      key,
      sealed
    );
    return new TextDecoder().decode(plaintext);
  } catch {
    throw new Error('Decryption failed. Check password and ciphertext.');
  }
}

const [mode, password, payload, iterations] = process.argv.slice(2);

try {
  if (mode === 'encrypt') {
    console.log(await encrypt(payload, password, iterations ? Number(iterations) : undefined));
  } else if (mode === 'decrypt') {
    console.log(await decrypt(payload, password));
  } else {
    throw new Error(`unknown mode: ${mode}`);
  }
} catch (e) {
  process.stderr.write(`ERROR: ${e.message}\n`);
  process.exit(1);
}
