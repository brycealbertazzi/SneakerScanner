import type { ReactNode } from "react";

/** Aspect ratio (width / height) of a 1284x2778 iPhone screenshot. */
export const SCREENSHOT_ASPECT = 1284 / 2778;
/**
 * Aspect ratio of the demo recording (886x1920).
 *
 * Sourced from assets/SSASCUpdatedDemoFinalized.mp4, NOT assets/SSDemo19201080.mp4 —
 * the latter is the same 19s recording center-cropped to 9:16, which cuts the app's
 * top bar and its entire bottom button row out of frame.
 */
export const VIDEO_ASPECT = 886 / 1920;

/** Bezel proportions are authored against a 264px-wide frame and scale from there. */
const BASE_WIDTH = 264;

type Props = {
  children: ReactNode;
  /** Outer width of the device in px. */
  width?: number;
  /** Aspect ratio (w/h) of the content, so nothing gets cropped. */
  screenAspect?: number;
  /** Tilt in degrees. */
  rotate?: number;
  /**
   * Bezel thickness / corner radius / button scale. Defaults to tracking the
   * width, but a large frame can pass a smaller value to keep a slim bezel
   * instead of scaling up into a chunky one.
   */
  bezelScale?: number;
};

export default function PhoneFrame({
  children,
  width = BASE_WIDTH,
  screenAspect = SCREENSHOT_ASPECT,
  rotate = 0,
  bezelScale,
}: Props) {
  const s = bezelScale ?? width / BASE_WIDTH;
  const inset = 10 * s;
  const screenWidth = width - inset * 2;
  const screenHeight = screenWidth / screenAspect;
  const height = screenHeight + inset * 2;

  const px = (n: number) => `${n * s}px`;

  return (
    <div className="flex w-full items-center justify-center py-3">
      <div
        style={{
          transform: `rotate(${rotate}deg)`,
          filter:
            "drop-shadow(0 48px 64px rgba(0,0,0,0.22)) drop-shadow(0 12px 24px rgba(0,0,0,0.14))",
        }}
      >
        <div
          className="relative bg-[#1A1A1A]"
          style={{
            width,
            height,
            borderRadius: px(56),
            boxShadow:
              "inset 0 0 0 2px rgba(255,255,255,0.14), inset 0 0 0 6px rgba(0,0,0,0.65)",
          }}
        >
          {/* Silent switch + volume up/down */}
          <div
            className="absolute bg-[#333]"
            style={{
              left: px(-5),
              top: px(90),
              width: px(5),
              height: px(32),
              borderRadius: "4px 0 0 4px",
            }}
          />
          <div
            className="absolute bg-[#333]"
            style={{
              left: px(-5),
              top: px(142),
              width: px(5),
              height: px(58),
              borderRadius: "4px 0 0 4px",
            }}
          />
          <div
            className="absolute bg-[#333]"
            style={{
              left: px(-5),
              top: px(212),
              width: px(5),
              height: px(58),
              borderRadius: "4px 0 0 4px",
            }}
          />
          {/* Side button */}
          <div
            className="absolute bg-[#333]"
            style={{
              right: px(-5),
              top: px(160),
              width: px(5),
              height: px(84),
              borderRadius: "0 4px 4px 0",
            }}
          />

          {/* Screen */}
          <div
            className="absolute overflow-hidden bg-black"
            style={{ inset, borderRadius: px(46) }}
          >
            {children}
          </div>

          {/* Glass sheen */}
          <div
            className="pointer-events-none absolute inset-0"
            style={{
              borderRadius: px(56),
              background:
                "linear-gradient(145deg, rgba(255,255,255,0.08) 0%, transparent 50%)",
            }}
          />
        </div>
      </div>
    </div>
  );
}
