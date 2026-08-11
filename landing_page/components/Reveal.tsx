"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";

type Direction = "up" | "left" | "right";

const OFFSET: Record<Direction, string> = {
  up: "translateY(30px)",
  left: "translateX(-40px)",
  right: "translateX(40px)",
};

type Props = {
  children: ReactNode;
  /** Stagger in ms. */
  delay?: number;
  direction?: Direction;
  className?: string;
};

/**
 * Fades content in the first time it scrolls into view, then stops observing.
 *
 * Reduced-motion and no-JS are handled in CSS (see the `.reveal` rules in
 * globals.css) rather than here, so content is never left stuck at opacity 0.
 */
export default function Reveal({
  children,
  delay = 0,
  direction = "up",
  className,
}: Props) {
  const ref = useRef<HTMLDivElement>(null);
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          setShown(true);
          observer.disconnect();
        }
      },
      // threshold 0 so sections taller than the viewport still trigger
      { threshold: 0, rootMargin: "0px 0px -80px 0px" },
    );

    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return (
    <div
      ref={ref}
      className={className ? `reveal ${className}` : "reveal"}
      style={{
        opacity: shown ? 1 : 0,
        transform: shown ? "none" : OFFSET[direction],
        transition: `opacity 0.75s cubic-bezier(0.16, 1, 0.3, 1) ${delay}ms, transform 0.75s cubic-bezier(0.16, 1, 0.3, 1) ${delay}ms`,
      }}
    >
      {children}
    </div>
  );
}
