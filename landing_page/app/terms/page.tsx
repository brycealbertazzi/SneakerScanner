import type { Metadata } from "next";
import LegalPage from "@/components/LegalPage";
import { site } from "@/lib/content";
import { termsOfService } from "@/lib/legal";

export const metadata: Metadata = {
  title: `Terms of Service — ${site.name}`,
  description: `The terms that govern your use of ${site.name}.`,
};

export default function Terms() {
  return <LegalPage doc={termsOfService} />;
}
