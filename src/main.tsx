import React from 'react';
import ReactDOM from 'react-dom/client';

function App() {
  return (
    <main style={{
      minHeight: '100vh',
      display: 'grid',
      placeItems: 'center',
      fontFamily: 'system-ui, sans-serif',
      padding: '24px',
      background: '#0b1020',
      color: '#f8fafc',
      textAlign: 'center'
    }}>
      <div>
        <h1 style={{ fontSize: '2rem', marginBottom: '0.75rem' }}>OpenClaw TUI</h1>
        <p style={{ margin: 0, opacity: 0.85 }}>
          The app shell is loading again. The previous white screen was caused by a missing <code>src/main.tsx</code> entry file.
        </p>
      </div>
    </main>
  );
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
