import type { LegalDoc } from "@/lib/legal";

export default function LegalPage({ doc }: { doc: LegalDoc }) {
  return (
    <main className="bg-page px-6 pb-20 pt-28">
      <article className="mx-auto max-w-3xl rounded-4xl bg-white p-8 shadow-sm md:p-14">
        <h1 className="text-4xl font-bold tracking-tight text-gray-900 md:text-5xl">
          {doc.title}
        </h1>
        <p className="mt-3 text-[14px] text-gray-400">
          Last updated: {doc.updated}
        </p>

        <div className="mt-10 space-y-10">
          {doc.sections.map((section) => (
            <section key={section.heading}>
              <h2 className="mb-3 text-[22px] font-bold tracking-tight text-gray-900">
                {section.heading}
              </h2>

              <div className="space-y-3">
                {section.blocks.map((block, i) =>
                  "p" in block ? (
                    <p
                      key={i}
                      className="text-[16px] leading-relaxed text-gray-600"
                    >
                      {block.p}
                    </p>
                  ) : (
                    <ul key={i} className="space-y-1.5 pl-1">
                      {block.ul.map((item) => (
                        <li
                          key={item}
                          className="flex items-start gap-3 text-[16px] leading-relaxed text-gray-600"
                        >
                          <span
                            aria-hidden="true"
                            className="mt-[10px] h-1.5 w-1.5 shrink-0 rounded-full bg-brand"
                          />
                          <span>{item}</span>
                        </li>
                      ))}
                    </ul>
                  ),
                )}
              </div>
            </section>
          ))}
        </div>
      </article>
    </main>
  );
}
