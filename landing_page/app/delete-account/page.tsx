import type { Metadata } from "next";
import { accountDeletion, site } from "@/lib/content";

export const metadata: Metadata = {
  title: `Delete Your Account — ${site.name}`,
  description: `How to permanently delete your ${site.name} account and the data associated with it.`,
};

const mailto = `mailto:${site.supportEmail}?subject=Delete%20my%20account`;

function SupportEmailLink() {
  return (
    <a
      href={mailto}
      className="font-medium text-brand underline underline-offset-2"
    >
      {site.supportEmail}
    </a>
  );
}

/** Splits copy on the support address so it can be rendered as a mailto link. */
function WithEmail({ text }: { text: string }) {
  const parts = text.split(site.supportEmail);
  return (
    <>
      {parts.map((part, i) => (
        <span key={i}>
          {part}
          {i < parts.length - 1 && <SupportEmailLink />}
        </span>
      ))}
    </>
  );
}

function Bullet() {
  return (
    <span
      aria-hidden="true"
      className="mt-[10px] h-1.5 w-1.5 shrink-0 rounded-full bg-brand"
    />
  );
}

export default function DeleteAccount() {
  return (
    <main className="bg-page px-6 pb-20 pt-28">
      <article className="mx-auto max-w-3xl rounded-4xl bg-white p-8 shadow-sm md:p-14">
        <h1 className="text-4xl font-bold tracking-tight text-gray-900 md:text-5xl">
          {accountDeletion.title}
        </h1>
        <p className="mt-3 text-[14px] text-gray-400">
          Last updated: {accountDeletion.updated}
        </p>
        <p className="mt-6 text-[17px] leading-relaxed text-gray-600">
          {accountDeletion.intro}
        </p>

        <div className="mt-10 space-y-6">
          {accountDeletion.methods.map((method) => (
            <section
              key={method.heading}
              className="rounded-3xl border border-gray-200 bg-page/60 p-6 md:p-8"
            >
              <span className="text-[12px] font-bold uppercase tracking-widest text-brand">
                {method.label}
              </span>
              <h2 className="mt-2 text-[22px] font-bold tracking-tight text-gray-900">
                {method.heading}
              </h2>
              <p className="mt-2 text-[16px] leading-relaxed text-gray-600">
                {method.body}
              </p>

              <ol className="mt-5 space-y-3">
                {method.steps.map((step, i) => (
                  <li
                    key={step}
                    className="flex items-start gap-3 text-[16px] leading-relaxed text-gray-700"
                  >
                    <span className="mt-[2px] flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-brand text-[13px] font-bold text-white">
                      {i + 1}
                    </span>
                    <span>
                      <WithEmail text={step} />
                    </span>
                  </li>
                ))}
              </ol>

              <p className="mt-5 text-[15px] leading-relaxed text-gray-500">
                {method.note}
              </p>
            </section>
          ))}
        </div>

        <div className="mt-12 space-y-10">
          <section>
            <h2 className="mb-3 text-[22px] font-bold tracking-tight text-gray-900">
              {accountDeletion.deleted.heading}
            </h2>
            <p className="text-[16px] leading-relaxed text-gray-600">
              {accountDeletion.deleted.intro}
            </p>
            <ul className="mt-3 space-y-1.5 pl-1">
              {accountDeletion.deleted.items.map((item) => (
                <li
                  key={item}
                  className="flex items-start gap-3 text-[16px] leading-relaxed text-gray-600"
                >
                  <Bullet />
                  <span>{item}</span>
                </li>
              ))}
            </ul>
            <p className="mt-5 rounded-2xl bg-brand/10 px-5 py-4 text-[16px] font-medium leading-relaxed text-gray-800">
              {accountDeletion.deleted.warning}
            </p>
          </section>

          <section>
            <h2 className="mb-3 text-[22px] font-bold tracking-tight text-gray-900">
              {accountDeletion.retained.heading}
            </h2>
            <p className="text-[16px] leading-relaxed text-gray-600">
              {accountDeletion.retained.intro}
            </p>
            <ul className="mt-3 space-y-1.5 pl-1">
              {accountDeletion.retained.items.map((item) => (
                <li
                  key={item}
                  className="flex items-start gap-3 text-[16px] leading-relaxed text-gray-600"
                >
                  <Bullet />
                  <span>{item}</span>
                </li>
              ))}
            </ul>
            <p className="mt-3 text-[16px] leading-relaxed text-gray-600">
              {accountDeletion.retained.note}
            </p>
          </section>

          <section>
            <h2 className="mb-3 text-[22px] font-bold tracking-tight text-gray-900">
              {accountDeletion.subscriptionWarning.heading}
            </h2>
            <p className="text-[16px] leading-relaxed text-gray-600">
              {accountDeletion.subscriptionWarning.body}
            </p>
          </section>

          <section className="border-t border-gray-200 pt-8">
            <p className="text-[16px] leading-relaxed text-gray-600">
              {accountDeletion.footer.body} <SupportEmailLink />
            </p>
          </section>
        </div>
      </article>
    </main>
  );
}
