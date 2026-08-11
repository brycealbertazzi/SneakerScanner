import { stores } from "@/lib/content";

function AppleIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="white" className="h-7 w-7 shrink-0">
      <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
    </svg>
  );
}

function PlayIcon() {
  return (
    <svg viewBox="30 336.7 120.9 129.2" className="h-[26px] w-[26px] shrink-0">
      <path
        fill="#00A0FF"
        d="M99.1,401.1l-64.3-64.3c-2.6,0.6-4.8,2.9-4.8,7.6c0,7.5,0,107.5,0,113.8c0,4.3,1.7,7.4,4.9,7.7L99.1,401.1z"
      />
      <path
        fill="#00E676"
        d="M99.1,401.1l20.1-20.2c0,0-74.6-40.7-79.1-43.1c-1.7-1-3.6-1.3-5.3-1L99.1,401.1z"
      />
      <path
        fill="#FF3A44"
        d="M99.1,401.1l-64.2,64.7c1.5,0.2,3.2-0.2,5.2-1.3c4.2-2.3,48.8-26.7,79.1-43.3L99.1,401.1z"
      />
      <path
        fill="#FFCE00"
        d="M119.2,421.2c15.3-8.4,27-14.8,28-15.3c3.2-1.7,6.5-6.2,0-9.7c-2.1-1.1-13.4-7.3-28-15.3l-20.1,20.2L119.2,421.2z"
      />
    </svg>
  );
}

const pill =
  "flex items-center gap-3 rounded-xl border border-white/10 bg-black px-4 py-2.5 text-white transition-colors hover:bg-gray-900 min-w-[172px]";

export default function StoreButtons() {
  return (
    <div className="flex flex-col items-center justify-center gap-3 sm:flex-row">
      <a
        href={stores.appStore}
        target="_blank"
        rel="noopener noreferrer"
        className={pill}
      >
        <AppleIcon />
        <div className="text-left">
          <div className="text-[10px] uppercase leading-none tracking-wide text-gray-400">
            Download on the
          </div>
          <div className="text-[19px] font-bold leading-snug tracking-tight">
            App Store
          </div>
        </div>
      </a>

      <a
        href={stores.googlePlay}
        target="_blank"
        rel="noopener noreferrer"
        className={pill}
      >
        <PlayIcon />
        <div className="text-left">
          <div className="text-[10px] uppercase leading-none tracking-wide text-gray-400">
            Get it on
          </div>
          <div className="text-[19px] font-bold leading-snug tracking-tight">
            Google Play
          </div>
        </div>
      </a>
    </div>
  );
}
