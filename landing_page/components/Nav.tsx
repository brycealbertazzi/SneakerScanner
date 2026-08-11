import Image from "next/image";
import Link from "next/link";
import { site } from "@/lib/content";

export default function Nav() {
  return (
    <nav className="fixed left-0 right-0 top-0 z-50 bg-white transition-all duration-300">
      <div className="mx-auto flex h-[64px] max-w-5xl items-center justify-between px-6">
        <Link href="/" className="group flex items-center gap-2.5">
          <Image
            src="/logo.png"
            alt={site.name}
            width={32}
            height={32}
            className="rounded-[8px]"
          />
          <span className="text-[17px] font-bold tracking-tight text-gray-900">
            {site.name}
          </span>
        </Link>

        <div className="hidden items-center gap-8 md:flex">
          <Link
            href="/#features"
            className="text-[15px] font-medium text-gray-500 transition-colors hover:text-gray-900"
          >
            Features
          </Link>
        </div>
      </div>
    </nav>
  );
}
