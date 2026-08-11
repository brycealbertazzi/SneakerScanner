import PhoneFrame, { VIDEO_ASPECT } from "@/components/PhoneFrame";
import StoreButtons from "@/components/StoreButtons";
import { hero } from "@/lib/content";

export default function Hero() {
  return (
    <section id="hero" className="bg-page px-6 pb-14 pt-28">
      <div className="mx-auto max-w-3xl text-center">
        <h1
          className="animate-fade-up mb-5 text-[44px] font-bold leading-[1.05] tracking-[-1.5px] text-gray-900 sm:text-[56px] sm:tracking-[-2px] md:text-[68px]"
          style={{ animationDelay: "0ms" }}
        >
          {hero.headline}
          <br />
          <span className="text-brand">{hero.headlineAccent}</span>
        </h1>

        <p
          className="animate-fade-up mx-auto mb-8 max-w-xl text-xl leading-relaxed text-gray-500"
          style={{ animationDelay: "150ms" }}
        >
          {hero.subhead}
        </p>

        <div className="animate-fade-up" style={{ animationDelay: "300ms" }}>
          <StoreButtons />
        </div>

        <div className="animate-fade-up mt-6" style={{ animationDelay: "450ms" }}>
          {/* bezelScale 1 keeps the bezel as slim as the smaller frames below,
              so the hero phone reads as tall rather than squat. */}
          <PhoneFrame width={320} screenAspect={VIDEO_ASPECT} bezelScale={1}>
            <video
              autoPlay
              muted
              loop
              playsInline
              preload="metadata"
              poster="/demo-poster.webp"
              aria-label="SneakScan demo: scanning a shoe box label and seeing resale prices"
              className="h-full w-full object-cover"
            >
              <source src="/demo.webm" type="video/webm" />
              <source src="/demo.mp4" type="video/mp4" />
            </video>
          </PhoneFrame>
        </div>
      </div>
    </section>
  );
}
