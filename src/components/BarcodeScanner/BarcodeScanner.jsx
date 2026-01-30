import { useEffect, useRef, useState } from 'react';
import { Html5Qrcode } from 'html5-qrcode';
import './BarcodeScanner.css';

function BarcodeScanner({ onScanSuccess }) {
  const [isScanning, setIsScanning] = useState(false);
  const [error, setError] = useState(null);
  const [cameras, setCameras] = useState([]);
  const [selectedCamera, setSelectedCamera] = useState(null);
  const scannerRef = useRef(null);
  const html5QrCodeRef = useRef(null);

  useEffect(() => {
    Html5Qrcode.getCameras()
      .then((devices) => {
        if (devices && devices.length > 0) {
          setCameras(devices);
          const backCamera = devices.find(
            (device) =>
              device.label.toLowerCase().includes('back') ||
              device.label.toLowerCase().includes('rear')
          );
          setSelectedCamera(backCamera ? backCamera.id : devices[0].id);
        } else {
          setError('No cameras found on this device');
        }
      })
      .catch((err) => {
        setError('Unable to access cameras: ' + err.message);
      });

    return () => {
      if (html5QrCodeRef.current && html5QrCodeRef.current.isScanning) {
        html5QrCodeRef.current.stop().catch(console.error);
      }
    };
  }, []);

  const startScanning = async () => {
    if (!selectedCamera) {
      setError('Please select a camera');
      return;
    }

    setError(null);

    if (!html5QrCodeRef.current) {
      html5QrCodeRef.current = new Html5Qrcode('scanner-region');
    }

    try {
      await html5QrCodeRef.current.start(
        selectedCamera,
        {
          fps: 10,
          qrbox: { width: 250, height: 150 },
        },
        (decodedText, decodedResult) => {
          onScanSuccess(decodedText, decodedResult.result.format.formatName);
        },
        () => {}
      );
      setIsScanning(true);
    } catch (err) {
      setError('Failed to start scanner: ' + err.message);
    }
  };

  const stopScanning = async () => {
    if (html5QrCodeRef.current && html5QrCodeRef.current.isScanning) {
      try {
        await html5QrCodeRef.current.stop();
        setIsScanning(false);
      } catch (err) {
        setError('Failed to stop scanner: ' + err.message);
      }
    }
  };

  const handleCameraChange = async (e) => {
    const newCameraId = e.target.value;
    if (isScanning) {
      await stopScanning();
    }
    setSelectedCamera(newCameraId);
  };

  return (
    <div className="barcode-scanner">
      {error && <div className="scanner-error">{error}</div>}

      {cameras.length > 1 && (
        <div className="camera-select">
          <label htmlFor="camera-select">Camera: </label>
          <select
            id="camera-select"
            value={selectedCamera || ''}
            onChange={handleCameraChange}
            disabled={isScanning}
          >
            {cameras.map((camera) => (
              <option key={camera.id} value={camera.id}>
                {camera.label || `Camera ${camera.id}`}
              </option>
            ))}
          </select>
        </div>
      )}

      <div
        id="scanner-region"
        ref={scannerRef}
        className={`scanner-region ${isScanning ? 'active' : ''}`}
      />

      <div className="scanner-controls">
        {!isScanning ? (
          <button
            onClick={startScanning}
            className="scan-button start"
            disabled={!selectedCamera}
          >
            Start Scanning
          </button>
        ) : (
          <button onClick={stopScanning} className="scan-button stop">
            Stop Scanning
          </button>
        )}
      </div>
    </div>
  );
}

export default BarcodeScanner;
