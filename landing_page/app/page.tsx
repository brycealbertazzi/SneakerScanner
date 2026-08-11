import CTA from "@/components/CTA";
import FeatureGrid from "@/components/FeatureGrid";
import FeatureSection from "@/components/FeatureSection";
import Hero from "@/components/Hero";
import { deepDives } from "@/lib/content";

export default function Home() {
  return (
    <main>
      <Hero />

      <section id="features">
        <FeatureGrid />

        <div className="bg-page px-6 pb-16">
          <div className="mx-auto max-w-5xl space-y-5">
            {deepDives.map((item) => (
              <FeatureSection key={item.pill} item={item} />
            ))}
          </div>
        </div>
      </section>

      <CTA />
    </main>
  );
}
