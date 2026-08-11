import Link from "next/link";
import { legalLinks, site } from "@/lib/content";

export default function Footer() {
  return (
    <footer className="border-t border-gray-200 bg-page px-8 py-12 sm:px-6">
      <div className="mx-auto max-w-5xl">
        <div className="mb-10 flex flex-col items-center gap-6 text-center">
          <div>
            <h4 className="mb-4 text-[12px] font-bold uppercase tracking-widest text-gray-400">
              Legal
            </h4>
            <div className="flex flex-row gap-6">
              {legalLinks.map((link) => (
                <Link
                  key={link.href}
                  href={link.href}
                  className="text-[14px] text-gray-500 transition-colors hover:text-gray-900"
                >
                  {link.label}
                </Link>
              ))}
            </div>
          </div>

          <div>
            <h4 className="mb-4 text-[12px] font-bold uppercase tracking-widest text-gray-400">
              Contact
            </h4>
            <a
              href={`mailto:${site.supportEmail}`}
              className="text-[14px] text-gray-500 transition-colors hover:text-gray-900"
            >
              {site.supportEmail}
            </a>
          </div>
        </div>

        <div className="flex flex-col items-center justify-between gap-3 border-t border-gray-200 pt-6 sm:flex-row">
          <p className="text-[13px] text-gray-400">
            © {new Date().getFullYear()} {site.name}. All rights reserved.
          </p>
          <p className="text-[13px] text-gray-400">{site.tagline}</p>
        </div>
      </div>
    </footer>
  );
}
