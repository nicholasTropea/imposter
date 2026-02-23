/// <reference types="vite/client" />

// SVG imports as URLs (for <img>)
declare module '*.svg' {
  const content: string
  export default content
}

// PNG/JPG/etc imports as URLs
declare module '*.png' {
  const content: string
  export default content
}

declare module '*.jpg' {
  const content: string
  export default content
}
