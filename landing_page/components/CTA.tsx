import Reveal from "@/components/Reveal";
import { cta } from "@/lib/content";

export default function CTA() {
  return (
    <section id="download" className="bg-white px-6 py-20">
      <div className="mx-auto max-w-2xl text-center">
        <Reveal>
          <h2 className="mb-3 text-4xl font-bold leading-tight tracking-tight text-gray-900 md:text-5xl">
            {cta.headline}
            <br />
            <span className="text-brand">{cta.headlineAccent}</span>
          </h2>
        </Reveal>

        <Reveal delay={150}>
          <p className="text-[17px] leading-relaxed text-gray-500">
            {cta.subhead}
          </p>
        </Reveal>
      </div>
    </section>
  );
}
