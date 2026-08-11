import type { Metadata } from "next";
import LegalPage from "@/components/LegalPage";
import { site } from "@/lib/content";
import { privacyPolicy } from "@/lib/legal";

export const metadata: Metadata = {
  title: `Privacy Policy — ${site.name}`,
  description: `How ${site.name} collects, uses, and stores information.`,
};

export default function Privacy() {
  return <LegalPage doc={privacyPolicy} />;
}
