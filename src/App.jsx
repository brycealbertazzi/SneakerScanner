import { useState } from 'react';
import BarcodeScanner from './components/BarcodeScanner';
import './App.css';

function App() {
  const [lastScan, setLastScan] = useState(null);
  const [scanHistory, setScanHistory] = useState([]);
  const [copied, setCopied] = useState(false);

  const handleScanSuccess = (code, format) => {
    const scanResult = {
      code,
      format,
      timestamp: new Date().toLocaleTimeString(),
    };

    setLastScan(scanResult);
    setScanHistory((prev) => [scanResult, ...prev].slice(0, 10));
  };

  const copyToClipboard = async (text) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (err) {
      console.error('Failed to copy:', err);
    }
  };

  return (
    <div className="app">
      <header className="app-header">
        <h1>Sneaker Scanner</h1>
        <p className="subtitle">Scan barcodes from sneaker boxes</p>
      </header>

      <main className="app-main">
        <BarcodeScanner onScanSuccess={handleScanSuccess} />

        {lastScan && (
          <div className="scan-result">
            <h2>Last Scan</h2>
            <div className="result-card">
              <div className="result-code">{lastScan.code}</div>
              <div className="result-meta">
                <span className="result-format">{lastScan.format}</span>
                <span className="result-time">{lastScan.timestamp}</span>
              </div>
              <button
                className="copy-button"
                onClick={() => copyToClipboard(lastScan.code)}
              >
                {copied ? 'Copied!' : 'Copy'}
              </button>
            </div>
          </div>
        )}

        {scanHistory.length > 0 && (
          <div className="scan-history">
            <h2>Scan History</h2>
            <ul className="history-list">
              {scanHistory.map((scan, index) => (
                <li key={index} className="history-item">
                  <span className="history-code">{scan.code}</span>
                  <span className="history-meta">
                    {scan.format} - {scan.timestamp}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        )}
      </main>
    </div>
  );
}

export default App;
