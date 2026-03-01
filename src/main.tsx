import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.scss'
import App from './App.tsx'  // Fixed extension
import { useRegisterSW } from 'virtual:pwa-register/react'  // React hook

// Optional: ReloadPrompt component for UX (offline/refresh toasts)
function ReloadPrompt() {
  const {
    offlineReady: [offlineReady, setOfflineReady],
    needRefresh: [needRefresh, setNeedRefresh],
    updateServiceWorker,
  } = useRegisterSW({
    onRegisteredSW(swUrl, registration) {
      // Periodic updates (hourly check)
      swUrl && setInterval(() => {
        window.location.reload()
      }, 60 * 60 * 1000)
    },
    onOfflineReady() {
      setOfflineReady(true)
      // Add toast: "App ready to work offline"
      setTimeout(setOfflineReady.bind(null, false), 2000)
    },
  })

  return (
    <>
      {offlineReady && <div>App ready to work offline 🟢</div>}
      {needRefresh && (
        <div>
          New version available!{' '}
          <button onClick={() => updateServiceWorker(true)}>Refresh</button>
        </div>
      )}
    </>
  )
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
    <ReloadPrompt />  {/* Mount for PWA prompts */}
  </StrictMode>,
)
