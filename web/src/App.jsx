import React, { useState } from 'react';
import { Lock, Unlock, Copy, Check, AlertCircle } from 'lucide-react';
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
      // Small timeout to allow UI to update (show loading spinner if we wanted)
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

  const resetState = () => {
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
      <header>
        <h1>FL2601 Cipher</h1>
        <p className="subtitle">Passphrase Text Encryption</p>
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
              <label>Passphrase</label>
              <input
                type="password"
                value={encPassphrase}
                onChange={(e) => setEncPassphrase(e.target.value)}
                placeholder="Enter passphrase"
              />
            </div>
            
            <div className="form-group">
              <label>Confirm Passphrase</label>
              <input
                type="password"
                value={encConfirm}
                onChange={(e) => setEncConfirm(e.target.value)}
                placeholder="Confirm passphrase"
              />
              {encPassphrase && encConfirm && encPassphrase !== encConfirm && (
                <div className="error-msg">
                  <AlertCircle size={14} /> Passphrases do not match
                </div>
              )}
            </div>

            <div className="form-group">
              <label>Message</label>
              <textarea
                value={encMessage}
                onChange={(e) => setEncMessage(e.target.value)}
                placeholder="Type or paste the message to encrypt..."
              />
            </div>

            <button 
              className="btn-primary" 
              onClick={handleEncrypt}
              disabled={isProcessing || !encPassphrase || !encConfirm || !encMessage || (encPassphrase !== encConfirm)}
            >
              <Lock size={18} />
              {isProcessing ? 'Encrypting...' : 'Encrypt Text'}
            </button>

            {encError && (
              <div className="error-msg" style={{marginTop: '1rem'}}>
                <AlertCircle size={16} /> {encError}
              </div>
            )}

            {encResult && (
              <div className="result-container">
                <div className="result-header">
                  <span className="result-title">Encrypted Output</span>
                  <button className="btn-icon" onClick={() => handleCopy(encResult)}>
                    {copied ? <span className="success-msg"><Check size={16} /> Copied</span> : <><Copy size={16} /> Copy</>}
                  </button>
                </div>
                <div className="result-content">
                  {encResult}
                </div>
              </div>
            )}
          </div>
        )}

        {activeTab === 'decrypt' && (
          <div className="tab-content">
            <div className="form-group">
              <label>Passphrase</label>
              <input
                type="password"
                value={decPassphrase}
                onChange={(e) => setDecPassphrase(e.target.value)}
                placeholder="Enter passphrase"
              />
            </div>

            <div className="form-group">
              <label>Encrypted Message</label>
              <textarea
                value={decMessage}
                onChange={(e) => setDecMessage(e.target.value)}
                placeholder="Paste the FL2601 message block here..."
              />
            </div>

            <button 
              className="btn-primary" 
              onClick={handleDecrypt}
              disabled={isProcessing || !decPassphrase || !decMessage}
            >
              <Unlock size={18} />
              {isProcessing ? 'Decrypting...' : 'Decrypt Text'}
            </button>

            {decError && (
              <div className="error-msg" style={{marginTop: '1rem'}}>
                <AlertCircle size={16} /> {decError}
              </div>
            )}

            {decResult && (
              <div className="result-container">
                <div className="result-header">
                  <span className="result-title">Decrypted Message</span>
                  <button className="btn-icon" onClick={() => handleCopy(decResult)}>
                    {copied ? <span className="success-msg"><Check size={16} /> Copied</span> : <><Copy size={16} /> Copy</>}
                  </button>
                </div>
                <div className="result-content">
                  {decResult}
                </div>
              </div>
            )}
          </div>
        )}
      </main>
      
      {/* Keyboard shortcuts hints could go here, but omitted for clean mobile view */}
    </div>
  );
}

export default App;
