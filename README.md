# Imposter PWA

**Progressive Web App implementation of the classic "Imposter" multiplayer game** – my final project for Web Development class. Fully offline-capable, installable, and responsive.

![PWA Badge](https://img.shields.io/badge/PWA-Ready-brightgreen) ![React](https://img.shields.io/badge/React-18-blue) ![Vite](https://img.shields.io/badge/Vite-5-orange) ![TypeScript](https://img.shields.io/badge/TypeScript-Strict-blueviolet)

## 🎮 Features (Planned)

- **Multiplayer Imposter gameplay** (dedicated servers or P2P).
- **Offline mode**: Solo practice, cached assets via Service Worker.
- **Installable**: Add to home screen (manifest + icons).
- **Responsive**: Mobile-first design (desktop too).
- **Push notifications**: Game invites/updates.
- **Auto-updates**: Seamless SW updates.
- **Performance**: Lighthouse PWA score 100% target.

## 🛠 Tech Stack

| Frontend | Build | PWA | Tools |
|----------|-------|-----|-------|
| React 18 + TS | Vite 5 | `vite-plugin-pwa` (generateSW) | ESLint, TailwindCSS (future) |

## 🚀 Quick Start

```bash
# Clone & install
git clone <your-repo> imposter-pwa
