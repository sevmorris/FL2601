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

async function deriveKey(passphrase, salt, iterations, usage) {
  const keyMaterial = await window.crypto.subtle.importKey(
    'raw', new TextEncoder().encode(passphrase), 'PBKDF2', false, ['deriveKey']
  );
  return window.crypto.subtle.deriveKey(
    { name: 'PBKDF2', salt, iterations, hash: 'SHA-256' },
    keyMaterial,
    { name: 'AES-GCM', length: 256 },
    false,
    [usage]
  );
}

// Convert Uint8Array to base64
function bufferToBase64(buffer) {
  let binary = '';
  const bytes = new Uint8Array(buffer);
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return window.btoa(binary);
}

// Convert base64 to Uint8Array
function base64ToBuffer(base64) {
  const binary_string = window.atob(base64);
  const len = binary_string.length;
  const bytes = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    bytes[i] = binary_string.charCodeAt(i);
  }
  return bytes;
}

export async function encryptMessage(plaintext, passphrase, iterations = DEFAULT_ITERATIONS) {
  const salt = window.crypto.getRandomValues(new Uint8Array(SALT_LEN));
  const nonce = window.crypto.getRandomValues(new Uint8Array(NONCE_LEN));
  const header = makeHeader(iterations);
  const key = await deriveKey(passphrase, salt, iterations, 'encrypt');

  const sealed = await window.crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce, additionalData: header },
    key,
    new TextEncoder().encode(plaintext)
  );

  const blob = new Uint8Array(HEADER_LEN + SALT_LEN + NONCE_LEN + sealed.byteLength);
  blob.set(header, 0);
  blob.set(salt, HEADER_LEN);
  blob.set(nonce, HEADER_LEN + SALT_LEN);
  blob.set(new Uint8Array(sealed), HEADER_LEN + SALT_LEN + NONCE_LEN);

  const base64 = bufferToBase64(blob);

  // Wrap it in the standard FL2601 format
  return `-----BEGIN FL2601 MESSAGE-----
Comment: Encrypted with FL2601 Cipher Tool
Comment: https://github.com/sevmorris/FL2601

${base64}
-----END FL2601 MESSAGE-----`;
}

export async function decryptMessage(ciphertext, passphrase) {
  // Extract base64 from wrapper if it exists, or just use the raw text if no wrapper
  let rawBase64 = ciphertext;
  
  // Find everything between BEGIN and END if present
  const beginMatch = ciphertext.indexOf('-----BEGIN FL2601 MESSAGE-----');
  const endMatch = ciphertext.indexOf('-----END FL2601 MESSAGE-----');
  
  if (beginMatch !== -1 && endMatch !== -1 && endMatch > beginMatch) {
    const block = ciphertext.substring(beginMatch, endMatch);
    // Find the blank line separating comments from base64
    const parts = block.split('\n\n');
    if (parts.length >= 2) {
      rawBase64 = parts.slice(1).join('\n\n');
    } else {
       // fallback if no blank line, try to extract last line before END
       const lines = block.split('\n');
       rawBase64 = lines[lines.length - 1]; // This is fragile, let's just strip known headers
    }
  }

  // Clean the input of whitespace and standard comments
  const cleaned = ciphertext
    .replace(/-----BEGIN FL2601 MESSAGE-----/g, '')
    .replace(/-----END FL2601 MESSAGE-----/g, '')
    .replace(/Comment:.*?\n/g, '')
    .replace(/\s+/g, '');

  let blob;
  try {
    blob = base64ToBuffer(cleaned);
  } catch (e) {
    throw new Error('Invalid base64 payload.');
  }

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

  const key = await deriveKey(passphrase, salt, iterations, 'decrypt');
  try {
    const plaintext = await window.crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: nonce, additionalData: header },
      key,
      sealed
    );
    return new TextDecoder().decode(plaintext);
  } catch {
    throw new Error('Decryption failed. Check passphrase and ciphertext.');
  }
}
