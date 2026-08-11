import Image from "next/image";
import CheckIcon from "@/components/CheckIcon";
import PhoneFrame from "@/components/PhoneFrame";
import Reveal from "@/components/Reveal";
import type { DeepDive } from "@/lib/content";

export default function FeatureSection({ item }: { item: DeepDive }) {
  // Copy slides in from the side it sits on; the phone comes from the opposite side.
  const textFrom = item.reversed ? "right" : "left";
  const imageFrom = item.reversed ? "left" : "right";

  return (
    <div className="rounded-4xl bg-white p-8 shadow-sm md:p-10">
      <div
        className={`flex flex-col items-center gap-8 ${
          item.reversed ? "md:flex-row-reverse" : "md:flex-row"
        }`}
      >
        <div className="flex-1 space-y-4">
          <Reveal direction={textFrom}>
            <div className="inline-flex items-center rounded-full bg-brand/10 px-3 py-1 text-sm font-semibold text-brand">
              {item.pill}
            </div>
          </Reveal>

          <Reveal direction={textFrom} delay={80}>
            <h3 className="text-3xl font-bold leading-snug tracking-tight text-gray-900 md:text-4xl">
              {item.headline}{" "}
              <span className="text-brand">{item.headlineAccent}</span>
            </h3>
          </Reveal>

          <Reveal direction={textFrom} delay={160}>
            <p className="text-[16px] leading-relaxed text-gray-500">
              {item.body}
            </p>
          </Reveal>

          <ul className="space-y-2.5">
            {item.bullets.map((bullet, i) => (
              <Reveal key={bullet} direction={textFrom} delay={240 + i * 80}>
                <li className="flex items-start gap-3">
                  <CheckIcon />
                  <span className="text-[15px] text-gray-600">{bullet}</span>
                </li>
              </Reveal>
            ))}
          </ul>
        </div>

        <Reveal direction={imageFrom} delay={100} className="w-full flex-1">
          <PhoneFrame rotate={item.rotate}>
            <Image
              src={item.image}
              alt={item.alt}
              fill
              sizes="264px"
              className="object-cover object-top"
            />
          </PhoneFrame>
        </Reveal>
      </div>
    </div>
  );
}
