import React, { useState } from 'react';
import { encryptMessage, decryptMessage } from './crypto';

function App() {
  const [activeTab, setActiveTab] = useState('encrypt');

  // Encrypt State
  const [encPassphrase, setEncPassphrase] = useState('');
  const [encConfirm, setEncConfirm] = useState('');
  const [encMessage, setEncMessage] = useState('');
  const [encResult, setEncResult] = useState('');
  const [encError, setEncError] = useState('');

  // Decrypt State
  const [decPassphrase, setDecPassphrase] = useState('');
  const [decMessage, setDecMessage] = useState('');
  const [decResult, setDecResult] = useState('');
  const [decError, setDecError] = useState('');

  // Global State
  const [isProcessing, setIsProcessing] = useState(false);
  const [copied, setCopied] = useState(false);

  const handleCopy = async (text) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (err) {
      console.error('Failed to copy', err);
    }
  };

  const handleEncrypt = async () => {
    setEncError('');
    setEncResult('');
    
    if (!encPassphrase) {
      setEncError('Passphrase is required.');
      return;
    }
    if (encPassphrase !== encConfirm) {
      setEncError('Passphrases do not match.');
      return;
    }
    if (!encMessage) {
      setEncError('Message is required.');
      return;
    }

    setIsProcessing(true);
    try {
      await new Promise(resolve => setTimeout(resolve, 50));
      const ciphertext = await encryptMessage(encMessage, encPassphrase);
      setEncResult(ciphertext);
    } catch (err) {
      setEncError(err.message || 'Encryption failed.');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleDecrypt = async () => {
    setDecError('');
    setDecResult('');
    
    if (!decPassphrase) {
      setDecError('Passphrase is required.');
      return;
    }
    if (!decMessage) {
      setDecError('Message to decrypt is required.');
      return;
    }

    setIsProcessing(true);
    try {
      await new Promise(resolve => setTimeout(resolve, 50));
      const plaintext = await decryptMessage(decMessage, decPassphrase);
      setDecResult(plaintext);
    } catch (err) {
      setDecError(err.message || 'Decryption failed.');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleClear = () => {
    setEncPassphrase('');
    setEncConfirm('');
    setEncMessage('');
    setEncResult('');
    setEncError('');
    
    setDecPassphrase('');
    setDecMessage('');
    setDecResult('');
    setDecError('');
    setCopied(false);
  };

  return (
    <div className="app-container">
      <div className="main-card">
        <header>
          <h1>FL2601 — CIPHER TOOL</h1>
        </header>

        <div className="tabs">
          <button
            className={`tab-btn ${activeTab === 'encrypt' ? 'active' : ''}`}
            onClick={() => { setActiveTab('encrypt'); setCopied(false); }}
          >
            Encrypt
          </button>
          <button
            className={`tab-btn ${activeTab === 'decrypt' ? 'active' : ''}`}
            onClick={() => { setActiveTab('decrypt'); setCopied(false); }}
          >
            Decrypt
          </button>
        </div>

        <main>
          {activeTab === 'encrypt' && (
            <div className="tab-content">
              <div className="form-group">
                <label>Access Passphrase</label>
                <input
                  type="password"
                  value={encPassphrase}
                  onChange={(e) => setEncPassphrase(e.target.value)}
                  placeholder="Enter passphrase..."
                />
              </div>
              
              <div className="form-group">
                <label>Confirm Passphrase</label>
                <input
                  type="password"
                  value={encConfirm}
                  onChange={(e) => setEncConfirm(e.target.value)}
                  placeholder="Re-enter passphrase..."
                />
                {encPassphrase && encConfirm && encPassphrase !== encConfirm && (
                  <div className="error-msg">Passphrases do not match</div>
                )}
              </div>

              <div className="form-group">
                <label>Plaintext Letter</label>
                <textarea
                  value={encMessage}
                  onChange={(e) => setEncMessage(e.target.value)}
                  placeholder="Type or paste text here..."
                />
              </div>

              <div className="button-group">
                <button 
                  className="btn-primary" 
                  onClick={handleEncrypt}
                  disabled={isProcessing || !encPassphrase || !encConfirm || !encMessage || (encPassphrase !== encConfirm)}
                >
                  {isProcessing ? 'PROCESSING...' : 'ENCRYPT TEXT'}
                </button>
                <button 
                  className="btn-secondary" 
                  onClick={handleClear}
                >
                  CLEAR
                </button>
              </div>

              {encError && (
                <div className="error-msg">{encError}</div>
              )}

              <div className="result-container">
                <div className="result-header">
                  <label>Result</label>
                  {encResult && (
                    <button className="copy-btn" onClick={() => handleCopy(encResult)}>
                      {copied ? 'COPIED' : 'COPY'}
                    </button>
                  )}
                </div>
                <div className="result-content">
                  {encResult ? encResult : <span className="result-placeholder">awaiting input</span>}
                </div>
              </div>
            </div>
          )}

          {activeTab === 'decrypt' && (
            <div className="tab-content">
              <div className="form-group">
                <label>Access Passphrase</label>
                <input
                  type="password"
                  value={decPassphrase}
                  onChange={(e) => setDecPassphrase(e.target.value)}
                  placeholder="Enter passphrase..."
                />
              </div>

              <div className="form-group">
                <label>Ciphertext Letter</label>
                <textarea
                  value={decMessage}
                  onChange={(e) => setDecMessage(e.target.value)}
                  placeholder="Paste the FL2601 message block here..."
                />
              </div>

              <div className="button-group">
                <button 
                  className="btn-primary" 
                  onClick={handleDecrypt}
                  disabled={isProcessing || !decPassphrase || !decMessage}
                >
                  {isProcessing ? 'PROCESSING...' : 'DECRYPT TEXT'}
                </button>
                <button 
                  className="btn-secondary" 
                  onClick={handleClear}
                >
                  CLEAR
                </button>
              </div>

              {decError && (
                <div className="error-msg">{decError}</div>
              )}

              <div className="result-container">
                <div className="result-header">
                  <label>Result</label>
                  {decResult && (
                    <button className="copy-btn" onClick={() => handleCopy(decResult)}>
                      {copied ? 'COPIED' : 'COPY'}
                    </button>
                  )}
                </div>
                <div className="result-content">
                  {decResult ? decResult : <span className="result-placeholder">awaiting input</span>}
                </div>
              </div>
            </div>
          )}
        </main>
        
        <footer>
          This tool uses PBKDF2 for key derivation (600,000 iterations, SHA-256) and AES-256-GCM for encryption.
        </footer>
      </div>
    </div>
  );
}

export default App;
