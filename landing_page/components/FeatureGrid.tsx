import Reveal from "@/components/Reveal";
import { features, featuresIntro } from "@/lib/content";

export default function FeatureGrid() {
  return (
    <div className="bg-page px-6 pb-16 pt-14">
      <div className="mx-auto max-w-5xl">
        <Reveal className="mb-10 text-center">
          <div className="mb-5 inline-flex items-center rounded-full border border-gray-300 px-4 py-1.5 text-sm font-medium text-gray-500">
            {featuresIntro.pill}
          </div>
          <h2 className="mb-3 text-4xl font-bold tracking-tight text-gray-900 md:text-5xl">
            {featuresIntro.headline}
            <br />
            {featuresIntro.headlineSecondLine}
          </h2>
          <p className="mx-auto max-w-xl text-lg text-gray-500">
            {featuresIntro.subhead}
          </p>
        </Reveal>

        <div className="grid grid-cols-1 gap-5 md:grid-cols-3">
          {features.map((feature, i) => (
            <Reveal key={feature.title} delay={i * 80}>
              <div className="h-full rounded-2xl bg-white p-5 shadow-sm transition-shadow hover:shadow-md">
                <div className="mb-3 flex h-11 w-11 items-center justify-center rounded-xl bg-page text-2xl">
                  <span aria-hidden="true">{feature.emoji}</span>
                </div>
                <h3 className="mb-1.5 text-[16px] font-bold text-gray-900">
                  {feature.title}
                </h3>
                <p className="text-[14px] leading-relaxed text-gray-500">
                  {feature.body}
                </p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </div>
  );
}
