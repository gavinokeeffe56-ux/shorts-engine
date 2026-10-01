import React from 'react';
import {
  AbsoluteFill, Audio, Img, OffthreadVideo, Sequence, staticFile, useCurrentFrame, useVideoConfig,
  interpolate, spring, Easing, continueRender, delayRender,
} from 'remotion';

// ---------- fonts (local files, loaded before first frame) ----------
const fontHandle = delayRender('fonts');
Promise.all(
  [500, 700, 800, 900].map((w) =>
    new FontFace('Inter', `url(${staticFile(`fonts/inter-latin-${w}-normal.woff2`)})`, {weight: String(w)})
      .load()
      .then((f) => document.fonts.add(f)),
  ),
).then(() => continueRender(fontHandle)).catch(() => continueRender(fontHandle));

// ---------- tokens ----------
const C = {
  bg: '#0d0e11', ink: '#ffffff', ink2: '#c3c2b7', muted: '#7d7c75', grid: '#23252a',
  dot: '#55544f', accent: '#3987e5', warm: '#ffc857',
};
const FONT = 'Inter, "Liberation Sans", sans-serif';
// Layout per platform. TikTok keeps clear of its UI: top 130px, bottom 484px, right 140px.
const LAYOUTS: Record<string, {rect: {x0: number; x1: number; y0: number; y1: number}; overlayTop: number; capTop: number}> = {
  youtube: {rect: {x0: 150, x1: 930, y0: 660, y1: 1240}, overlayTop: 250, capTop: 1390},
  tiktok: {rect: {x0: 150, x1: 920, y0: 570, y1: 1050}, overlayTop: 190, capTop: 1200},
};

// ---------- types ----------
type Word = {text: string; start: number; end: number; emph: boolean};
type Beat = {t: number; target?: string; pan?: number; overview?: boolean; zoom?: number; headline?: string;
  label?: string; counter?: number; prefix?: string; suffix?: string; chip?: string; big?: string; bigSub?: string; connector?: string[];
  card?: boolean; cardLine?: string; cardAccent?: string};
type Point = {name: string; year: number; cost: number; value?: number};
export type Timeline = {
  slug: string; series: string; layout?: string; fps: number; width: number; height: number; duration: number;
  narration: string; music: string;
  chart: {type?: string; valueSuffix?: string; xMin: number; xMax: number; yMin: number; yMax: number; yTicks: number[]; yTickLabels: string[]; xTicks: number[]; yLabel: string};
  dataset: {source: string; units: string; note?: string};
  points: Point[];
  segments: {start: number; end: number; words: Word[]; beats: Beat[]}[];
  captions: {start: number; end: number; words: Word[]}[];
  speech: [number, number][];
  sfx: {t: number; name: string; vol: number}[];
  endCard: {start: number; question: string; prompt: string; follow: string};
  hookClip?: {src: string; end: number};
  shots?: Shot[];
};
type Shot = {start: number; end: number; src: string; kind: string; motion: string; offset: number; missing?: boolean;
  size?: 'wide' | 'medium' | 'close'; focus?: [number, number]; tin?: 'cut' | 'slide' | 'zoom' | 'inverse'; dir?: number};

const clamp01 = (x: number) => Math.max(0, Math.min(1, x));
const ease = (x: number) => Easing.bezier(0.22, 1, 0.36, 1)(clamp01(x));
const lerp = (a: number, b: number, p: number) => a + (b - a) * p;
const fmtNum = (v: number) => (v < 10 && Math.abs(v - Math.round(v)) > 0.05 ? v.toFixed(1) : Math.round(v).toLocaleString('en-US'));

type Cam = {cx: number; cy: number; z: number};

export const Short: React.FC<{timeline: Timeline}> = ({timeline: T}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const t = frame / fps;
  const ch = T.chart;
  const L = LAYOUTS[T.layout ?? 'youtube'] ?? LAYOUTS.youtube;
  const RECT = L.rect;
  const beats: Beat[] = T.segments.flatMap((s) => s.beats).sort((a, b) => a.t - b.t);
  const byName = new Map(T.points.map((p) => [p.name, p]));
  const highlightNames = Array.from(new Set(beats.filter((b) => b.target).map((b) => b.target!)));
  const firstSeen = new Map<string, number>();
  beats.forEach((b) => b.target && !firstSeen.has(b.target) && firstSeen.set(b.target, b.t));

  // ----- camera -----
  const lyMin = Math.log10(ch.yMin), lyMax = Math.log10(ch.yMax);
  const home: Cam = {cx: (ch.xMin + ch.xMax) / 2, cy: (lyMin + lyMax) / 2, z: 1};
  const camKeys: {t: number; cam: Cam}[] = [{t: 0, cam: home}];
  const isBars = ch.type === 'bars';
  for (const b of (isBars ? [] : beats)) {
    if (b.target && byName.get(b.target)) {
      const p = byName.get(b.target)!;
      camKeys.push({t: b.t, cam: {cx: lerp(home.cx, p.year, 0.7), cy: lerp(home.cy, Math.log10(p.cost), 0.7), z: b.zoom ?? 1.35}});
    } else if (b.pan !== undefined) {
      camKeys.push({t: b.t, cam: {cx: lerp(home.cx, b.pan, 0.6), cy: home.cy - 0.25, z: b.zoom ?? 1.1}});
    } else if (b.overview) {
      camKeys.push({t: b.t, cam: home});
    }
  }
  let cam = home;
  for (let i = 1; i < camKeys.length; i++) {
    if (t < camKeys[i].t) break;
    const p = ease((t - camKeys[i].t) / 0.9);
    const from = cam; // value at the moment this move began (approx: previous resolved)
    cam = {cx: lerp(from.cx, camKeys[i].cam.cx, p), cy: lerp(from.cy, camKeys[i].cam.cy, p), z: lerp(from.z, camKeys[i].cam.z, p)};
  }
  const pxPerYear = (RECT.x1 - RECT.x0) / (ch.xMax - ch.xMin);
  const pxPerDec = (RECT.y1 - RECT.y0) / (lyMax - lyMin);
  const rcx = (RECT.x0 + RECT.x1) / 2, rcy = (RECT.y0 + RECT.y1) / 2;
  const sx = (year: number) => rcx + (year - cam.cx) * pxPerYear * cam.z;
  const sy = (cost: number) => rcy - (Math.log10(cost) - cam.cy) * pxPerDec * cam.z;

  // ----- state from beats -----
  const past = beats.filter((b) => b.t <= t);
  const lastWith = (k: keyof Beat) => [...past].reverse().find((b) => b[k] !== undefined);
  const cardBeat = lastWith('card');
  const cardOn = !!cardBeat;
  const chartStart = T.hookClip ? T.hookClip.end : 0;
  const chartOpacity = cardOn ? 1 - clamp01((t - cardBeat!.t) / 0.4) : clamp01((t - chartStart) / 0.5);
  const endOn = t >= T.endCard.start;
  const hasShots = !!(T.shots && T.shots.length);
  // chart shows (as a glass card over the visuals) only during segments that use it
  const chartSegs = T.segments.filter((s) => s.beats.some((b) => b.target || b.overview || b.connector || b.pan !== undefined));
  const chartWin = chartSegs.find((s) => t >= s.start - 0.2 && t < s.end + 0.35);
  const chartVis = !hasShots ? 1 : chartWin ? ease((t - (chartWin.start - 0.2)) / 0.35) * (1 - clamp01((t - chartWin.end) / 0.35)) : 0;
  // punch-in on emphasised words
  const allWords = T.segments.flatMap((s) => s.words);
  const lastEmph = [...allWords].reverse().find((w) => w.emph && w.start <= t);
  const punch = lastEmph ? Math.max(0, 1 - (t - lastEmph.start) / 0.45) * clamp01((t - lastEmph.start) / 0.08) : 0;
  const currentTarget = lastWith('target')?.target;

  // counter animation
  const counterBeats = beats.filter((b) => b.counter !== undefined);
  const ci = counterBeats.filter((b) => b.t <= t).length - 1;
  const overlayBeatCounter = ci >= 0 ? counterBeats[ci] : undefined;
  let counterVal = 0;
  if (ci >= 0) {
    const cb = counterBeats[ci];
    const prev = ci > 0 ? counterBeats[ci - 1].counter! : cb.counter! * 0.1;
    const p = ease((t - cb.t) / 0.75);
    counterVal = Math.exp(lerp(Math.log(prev), Math.log(cb.counter!), p));
  }

  // top overlay: the latest beat carrying overlay content
  // a pan with no overlay of its own clears the previous number off screen
  const lastAny = past[past.length - 1];
  const panClears = !!lastAny && lastAny.pan !== undefined && !lastAny.label && !lastAny.big && !lastAny.headline;
  const overlayBeat = panClears ? undefined : [...past].reverse().find((b) => b.headline || b.label || b.big);
  const chipBeat = [...past].reverse().find((b) => b.chip || b.label || b.big);
  const overlayAge = overlayBeat ? t - overlayBeat.t : 0;
  // the hook overlay is on screen from the very first frame
  const overlayIn = overlayBeat && overlayBeat === beats[0] ? 1 : ease(overlayAge / 0.35);

  // ----- captions -----
  const cap = T.captions.find((c) => t >= c.start && t < c.end);
  const capAge = cap ? t - cap.start : 0;
  // critically damped: smooth settle, no bounce
  const capScale = spring({frame: Math.round(capAge * fps), fps, config: {damping: 200, stiffness: 320}, from: 0.86, to: 1});

  // music ducking
  const inSpeech = (x: number) => T.speech.some(([a, b]) => x >= a - 0.15 && x <= b + 0.15);

  return (
    <AbsoluteFill style={{backgroundColor: C.bg, fontFamily: FONT}}>
      {hasShots ? <ShotLayer T={T} t={t} punch={punch} /> : <Stars t={t} cam={cam} />}
      {hasShots && t < 3 && (
        <div style={{position: 'absolute', top: 150, right: 60, color: C.ink2, fontSize: 22, fontWeight: 700, letterSpacing: 3,
          opacity: 0.75 * (1 - clamp01((t - 2.4) / 0.6))}}>AI VISUALS</div>
      )}
      {hasShots && chartVis > 0 && (
        <div style={{position: 'absolute', left: RECT.x0 - 120, right: 1080 - RECT.x1 - 50, top: RECT.y0 - 70, height: RECT.y1 - RECT.y0 + 180,
          borderRadius: 36, background: 'rgba(10,12,20,0.72)', backdropFilter: 'blur(18px)', border: '2px solid rgba(255,255,255,0.08)',
          opacity: chartVis, transform: `scale(${lerp(0.94, 1, chartVis)})`}} />
      )}
      {T.hookClip && t < T.hookClip.end + 0.6 && (
        <AbsoluteFill style={{opacity: 1 - clamp01((t - T.hookClip.end) / 0.6)}}>
          <OffthreadVideo src={staticFile(T.hookClip.src)} muted style={{width: '100%', height: '100%', objectFit: 'cover'}} />
          <AbsoluteFill style={{background: 'linear-gradient(180deg, rgba(13,14,17,.55) 0%, rgba(13,14,17,.15) 35%, rgba(13,14,17,.35) 60%, rgba(13,14,17,.85) 100%)'}} />
          <div style={{position: 'absolute', top: 150, right: 60, color: C.ink2, fontSize: 24, fontWeight: 700, letterSpacing: 3, opacity: 0.8}}>AI ILLUSTRATION</div>
        </AbsoluteFill>
      )}

      {/* ---------- chart ---------- */}
      <svg width={1080} height={1920} style={{position: 'absolute', opacity: chartOpacity * chartVis * (endOn ? 0.25 : 1)}}>
        <defs>
          <clipPath id="plot"><rect x={RECT.x0 - 140} y={RECT.y0 - 80} width={RECT.x1 - RECT.x0 + 240} height={RECT.y1 - RECT.y0 + 110} /></clipPath>
        </defs>
        {!isBars && (ch.yTicks ?? []).map((v, i) => {
          const y = sy(v);
          if (y < RECT.y0 - 40 || y > RECT.y1 + 20) return null;
          return (
            <g key={v}>
              <line x1={RECT.x0} x2={RECT.x1} y1={y} y2={y} stroke={C.grid} strokeWidth={2} />
              <text x={RECT.x0 - 16} y={y + 10} fill={C.muted} fontSize={28} fontWeight={600} textAnchor="end">{ch.yTickLabels[i]}</text>
            </g>
          );
        })}
        {!isBars && (ch.xTicks ?? []).map((v) => {
          const x = sx(v);
          if (x < RECT.x0 - 10 || x > RECT.x1 + 10) return null;
          return <text key={v} x={x} y={RECT.y1 + 52} fill={C.muted} fontSize={28} fontWeight={600} textAnchor="middle">{v}</text>;
        })}
        {isBars && <Bars T={T} beats={beats} past={past} t={t} frame={frame} fps={fps} rect={RECT} chartStart={chartStart} currentTarget={currentTarget} />}
        {!isBars && <g clipPath="url(#plot)">
          {T.points.filter((p) => !highlightNames.includes(p.name)).map((p, i) => {
            const s = spring({frame: frame - Math.round((0.15 + i * 0.012) * fps), fps, config: {damping: 12, stiffness: 180}});
            return <circle key={p.name} cx={sx(p.year)} cy={sy(p.cost)} r={9 * s * Math.sqrt(cam.z)} fill={C.dot} stroke={C.bg} strokeWidth={3} />;
          })}
          <Connector beats={past} byName={byName} sx={sx} sy={sy} t={t} />
          {highlightNames.map((n) => {
            const p = byName.get(n);
            const t0 = firstSeen.get(n)!;
            if (!p || t < t0) return null;
            const s = spring({frame: frame - Math.round(t0 * fps), fps, config: {damping: 9, stiffness: 200}});
            const lt = lastWith('target'), lo = lastWith('overview');
            const active = n === currentTarget && !!lt && lt.t > (lo?.t ?? -1);
            const x = sx(p.year), y = sy(p.cost);
            const right = x < rcx + 140;
            const pulse = active ? 1 + 0.5 * ((t * 1.4) % 1) : 0;
            return (
              <g key={n}>
                {active && <circle cx={x} cy={y} r={18 * pulse + 8} fill="none" stroke={C.accent} strokeWidth={3} opacity={1 - ((t * 1.4) % 1)} />}
                <circle cx={x} cy={y} r={15 * s} fill={C.accent} stroke={C.bg} strokeWidth={4} />
                <text x={x + (right ? 30 : -30)} y={y + 12} fill={active ? C.ink : C.ink2} fontSize={active ? 36 : 30}
                  fontWeight={800} textAnchor={right ? 'start' : 'end'} opacity={clamp01((t - t0) / 0.3)}
                  style={{paintOrder: 'stroke'}} stroke={C.bg} strokeWidth={8}>{n}</text>
              </g>
            );
          })}
        </g>}
        <text x={RECT.x0} y={RECT.y1 + 104} fill={C.muted} fontSize={22} fontWeight={500}>
          {`Source: ${T.dataset.source}${T.dataset.note ? ' · ' + T.dataset.note : ''}`}
        </text>
      </svg>

      {/* ---------- top overlay ---------- */}
      {!cardOn && !endOn && overlayBeat && (
        <div style={{position: 'absolute', top: L.overlayTop, left: 60, right: 60, textAlign: 'center',
          opacity: overlayIn, transform: `translateY(${(1 - overlayIn) * 24}px)`}}>
          {overlayBeat.headline && (
            <div style={{color: C.ink, fontSize: 104, fontWeight: 900, letterSpacing: -2, lineHeight: 1.05}}>
              {overlayBeat.headline}
            </div>
          )}
          {overlayBeat.label && (
            <>
              <div style={{color: C.ink2, fontSize: 40, fontWeight: 700, letterSpacing: 1}}>{overlayBeat.label}</div>
              <div style={{color: C.ink, fontSize: 132, fontWeight: 900, letterSpacing: -3, lineHeight: 1.1, fontVariantNumeric: 'tabular-nums'}}>
                {(overlayBeatCounter?.prefix ?? '$')}{fmtNum(counterVal)}
                <span style={{fontSize: 52, color: C.ink2, fontWeight: 700, letterSpacing: 0}}>{overlayBeatCounter?.suffix ?? ' /kg'}</span>
              </div>
            </>
          )}
          {overlayBeat.big && (
            <>
              <div style={{color: C.accent, fontSize: 200, fontWeight: 900, letterSpacing: -6, lineHeight: 1,
                transform: `scale(${spring({frame: Math.round(overlayAge * fps), fps, config: {damping: 10}, from: 0.6, to: 1})})`}}>
                {overlayBeat.big}
              </div>
              <div style={{color: C.ink2, fontSize: 40, fontWeight: 700, marginTop: 10}}>{overlayBeat.bigSub}</div>
            </>
          )}
          {chipBeat?.chip && (
            <div style={{display: 'inline-block', marginTop: 18, padding: '10px 26px', borderRadius: 40,
              border: `3px solid ${C.accent}`, color: C.ink, fontSize: 34, fontWeight: 700,
              opacity: ease((t - chipBeat.t) / 0.3), transform: `scale(${lerp(0.8, 1, ease((t - chipBeat.t) / 0.3))})`}}>
              {chipBeat.chip}
            </div>
          )}
        </div>
      )}

      {/* ---------- statement card ---------- */}
      {cardOn && !endOn && (
        <div style={{position: 'absolute', top: 560, left: 80, right: 80, textAlign: 'center'}}>
          <div style={{color: C.ink, fontSize: 84, fontWeight: 800, lineHeight: 1.15, letterSpacing: -1,
            opacity: ease((t - cardBeat!.t) / 0.4)}}>{cardBeat!.cardLine}</div>
          {(() => {
            const ab = lastWith('cardAccent');
            if (!ab) return null;
            const s = spring({frame: Math.round((t - ab.t) * fps), fps, config: {damping: 9, stiffness: 160}, from: 0.5, to: 1});
            return <div style={{color: C.accent, fontSize: 132, fontWeight: 900, letterSpacing: -4, lineHeight: 1.05, marginTop: 40, transform: `scale(${s})`}}>{ab.cardAccent}</div>;
          })()}
        </div>
      )}

      {/* ---------- end card ---------- */}
      {endOn && (() => {
        const p = ease((t - T.endCard.start) / 0.4);
        return (
          <div style={{position: 'absolute', top: 520, left: 70, right: 70, textAlign: 'center', opacity: p,
            transform: `translateY(${(1 - p) * 30}px)`}}>
            <div style={{color: C.ink, fontSize: 92, fontWeight: 900, lineHeight: 1.1, letterSpacing: -2}}>{T.endCard.question}</div>
            <div style={{color: C.accent, fontSize: 46, fontWeight: 700, marginTop: 30}}>{T.endCard.prompt} ↓</div>
            <div style={{marginTop: 120, color: C.ink, fontSize: 54, fontWeight: 900, letterSpacing: 6}}>{T.series.toUpperCase()}</div>
            <div style={{color: C.ink2, fontSize: 36, fontWeight: 600, marginTop: 12}}>{T.endCard.follow}</div>
          </div>
        );
      })()}

      {/* ---------- captions ---------- */}
      {cap && !cardOn && !endOn && (
        <div style={{position: 'absolute', top: L.capTop, left: 50, right: 50, display: 'flex', justifyContent: 'center',
          flexWrap: 'wrap', gap: '6px 18px', transform: `scale(${capScale})`}}>
          {cap.words.map((w, i) => {
            const next = cap.words[i + 1];
            const on = t >= w.start - 0.03 && t < (next ? next.start : cap.end);
            return (
              <span key={i} style={{
                fontSize: 82, fontWeight: 900, letterSpacing: -1, lineHeight: 1.15,
                color: on ? C.ink : w.emph ? C.warm : C.ink,
                background: on ? C.accent : 'transparent', borderRadius: 18, padding: '0 14px',
                textShadow: on ? 'none' : '0 4px 0 #000, 0 0 18px rgba(0,0,0,.8)',
                transform: on ? 'scale(1.06)' : 'scale(1)',
              }}>{w.text}</span>
            );
          })}
        </div>
      )}

      {/* brand bug */}
      {!endOn && (
        <div style={{position: 'absolute', top: 150, left: 60, color: C.ink2, fontSize: 28, fontWeight: 800,
          letterSpacing: 5, opacity: 0.55}}>{T.series.toUpperCase()}</div>
      )}

      {/* ---------- audio ---------- */}
      <Audio src={staticFile(T.narration)} />
      <Audio src={staticFile(T.music)} loop volume={(f) => {
        const x = f / fps;
        const fadeIn = clamp01(x / 0.6), fadeOut = clamp01((T.duration - x) / 1.4);
        return (inSpeech(x) ? 0.075 : 0.2) * fadeIn * fadeOut;
      }} />
      {T.sfx.map((s, i) => (
        <Sequence key={i} from={Math.round(s.t * fps)} durationInFrames={Math.round(1.3 * fps)}>
          <Audio src={staticFile(`sfx/${s.name}.wav`)} volume={s.vol} />
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};

const Connector: React.FC<{beats: Beat[]; byName: Map<string, Point>; sx: (y: number) => number; sy: (c: number) => number; t: number}> =
  ({beats, byName, sx, sy, t}) => {
    const b = [...beats].reverse().find((x) => x.connector);
    if (!b) return null;
    const [a, c] = b.connector!.map((n) => byName.get(n)!);
    const p = ease((t - b.t - 0.3) / 1.0);
    const x1 = sx(a.year), y1 = sy(a.cost), x2 = sx(c.year), y2 = sy(c.cost);
    return <line x1={x1} y1={y1} x2={lerp(x1, x2, p)} y2={lerp(y1, y2, p)} stroke={C.accent} strokeWidth={6}
      strokeDasharray="4 14" strokeLinecap="round" />;
  };

// deterministic star field with slight parallax
const STARS = Array.from({length: 90}, (_, i) => {
  const r = (n: number) => { const x = Math.sin(i * 12.9898 + n * 78.233) * 43758.5453; return x - Math.floor(x); };
  return {x: r(1) * 1080, y: r(2) * 1920, s: 1 + r(3) * 2.2, o: 0.06 + r(4) * 0.22, d: 0.3 + r(5)};
});
const Stars: React.FC<{t: number; cam: Cam}> = ({t, cam}) => (
  <svg width={1080} height={1920} style={{position: 'absolute'}}>
    {STARS.map((s, i) => (
      <circle key={i} cx={(s.x - (cam.cx - 1990) * 3 * s.d + 1080) % 1080} cy={(s.y + t * 6 * s.d) % 1920} r={s.s}
        fill="#fff" opacity={s.o * (0.7 + 0.3 * Math.sin(t * 2 + i))} />
    ))}
  </svg>
);

const Bars: React.FC<{T: Timeline; beats: Beat[]; past: Beat[]; t: number; frame: number; fps: number;
  rect: {x0: number; x1: number; y0: number; y1: number}; chartStart: number; currentTarget?: string}> =
  ({T, beats, past, t, frame, fps, rect, chartStart, currentTarget}) => {
    const pts = T.points;
    const max = Math.max(...pts.map((p) => p.value ?? 0)) || 1;
    const n = pts.length, gap = 40;
    const bw = (rect.x1 - rect.x0 - gap * (n - 1)) / n;
    const base = rect.y1 - 40, top = rect.y0 + 60;
    const first = (name: string) => beats.find((b) => b.target === name)?.t;
    return (
      <g>
        <line x1={rect.x0} x2={rect.x1} y1={base} y2={base} stroke={C.grid} strokeWidth={3} />
        {pts.map((p, i) => {
          const t0 = first(p.name) ?? chartStart + 0.2 + i * 0.15;
          const x0 = rect.x0 + i * (bw + gap);
          if (t < t0) {
            // teaser: dashed outline with a question mark until the bar is revealed
            if (t < chartStart) return null;
            const hf = ((p.value ?? 0) / max) * (base - top);
            const [m1, m2] = p.name.split(' · ');
            return (
              <g key={p.name} opacity={0.45 * clamp01((t - chartStart) / 0.5)}>
                <rect x={x0} y={base - hf} width={bw} height={hf} rx={10} fill="none" stroke={C.muted} strokeWidth={3} strokeDasharray="10 10" />
                <text x={x0 + bw / 2} y={base - hf - 18} fill={C.muted} fontSize={40} fontWeight={900} textAnchor="middle">?</text>
                <text x={x0 + bw / 2} y={base + 42} fill={C.muted} fontSize={28} fontWeight={800} textAnchor="middle">{m1}</text>
                {m2 && <text x={x0 + bw / 2} y={base + 76} fill={C.muted} fontSize={24} fontWeight={600} textAnchor="middle">{m2}</text>}
              </g>
            );
          }
          const g = spring({frame: frame - Math.round(t0 * fps), fps, config: {damping: 14, stiffness: 90}});
          const h = ((p.value ?? 0) / max) * (base - top) * g;
          const x = rect.x0 + i * (bw + gap);
          const active = p.name === currentTarget;
          const [l1, l2] = p.name.split(' · ');
          return (
            <g key={p.name}>
              <rect x={x} y={base - h} width={bw} height={Math.max(h, 2)} rx={10} fill={active ? C.accent : C.dot} opacity={active ? 1 : 0.85} />
              <text x={x + bw / 2} y={base - h - 18} fill={active ? C.ink : C.ink2} fontSize={active ? 44 : 36} fontWeight={900}
                textAnchor="middle">{`${fmtNum((p.value ?? 0) * g)}${T.chart.valueSuffix ?? ''}`}</text>
              <text x={x + bw / 2} y={base + 42} fill={active ? C.ink : C.ink2} fontSize={28} fontWeight={800} textAnchor="middle">{l1}</text>
              {l2 && <text x={x + bw / 2} y={base + 76} fill={C.muted} fontSize={24} fontWeight={600} textAnchor="middle">{l2}</text>}
            </g>
          );
        })}
      </g>
    );
  };

// ---------- AI shot layer ----------
// Framing changes by shot size (wide -> close -> medium) instead of Ken Burns drifts; holds are near-still with a
// low-amplitude handheld float. Transitions are chosen by story job: hard cut for a re-frame of the same image,
// whip (cut-the-curve) while an idea continues, zoom-through at a new segment, inverse zoom for the payoff.
const SIZE: Record<string, number> = {wide: 1.04, medium: 1.2, close: 1.38};
const VSIZE: Record<string, number> = {wide: 1.02, medium: 1.12, close: 1.22};
const expoOut = Easing.bezier(0.16, 1, 0.3, 1);
const pow3In = Easing.bezier(0.32, 0, 0.67, 0);
const quartInOut = Easing.bezier(0.76, 0, 0.24, 1);
const WHIP = 0.16; // half-window of a whip transition (s)
const PRE = 8; // frames a shot is mounted early so it can appear during a transition

type Fx = {x: number; mul: number; blur: number; op: number};
const NOFX: Fx = {x: 0, mul: 1, blur: 0, op: 1};

const ShotFrame: React.FC<{sh: Shot; idx: number; t: number; fx: Fx; punch: number; fps: number}> = ({sh, idx, t, fx, punch, fps}) => {
  const dur = Math.max(sh.end - sh.start, 0.1);
  const p = clamp01((t - sh.start) / dur);
  const isVid = sh.kind === 'video';
  // clips are 720p upscaled, so they are re-framed less aggressively than stills
  const base = (isVid ? VSIZE : SIZE)[sh.size ?? 'wide'] ?? 1.04;
  const scale = Math.max(1, base * (1 + (isVid ? 0.01 : 0.018) * p) * fx.mul) * (1 + 0.05 * punch);
  // keep the focus point centred when framed tighter
  const [fxp, fyp] = sh.focus ?? [0, 0];
  const ox = -fxp * (scale - 1) * 540, oy = -fyp * (scale - 1) * 960;
  // handheld float, a few px only
  const jx = isVid ? 0 : 5 * Math.sin(t * 0.83 + idx * 1.7), jy = isVid ? 0 : 4 * Math.cos(t * 0.61 + idx * 2.3);
  const style: React.CSSProperties = {width: '100%', height: '100%', objectFit: 'cover',
    transform: `translate(${ox + jx}px, ${oy + jy}px) scale(${scale})`};
  const from = Math.max(0, Math.round(sh.start * fps) - PRE);
  const lead = Math.round(sh.start * fps) - from;
  return (
    <AbsoluteFill style={{transform: `translateX(${fx.x}px)`, filter: fx.blur > 0.2 ? `blur(${fx.blur}px)` : undefined,
      opacity: fx.op, overflow: 'hidden'}}>
      <Sequence from={from} layout="none">
        {sh.missing ? (
          <AbsoluteFill style={{background: 'linear-gradient(160deg,#1b2a4a,#3b1f2b)', ...style, justifyContent: 'center', alignItems: 'center',
            color: '#ffffff55', fontSize: 40, fontWeight: 800}}>{sh.src.split('/').pop()}</AbsoluteFill>
        ) : isVid ? (
          // the clip's own clock starts when its Sequence mounts, so it actually plays (not a frozen last frame)
          <OffthreadVideo src={staticFile(sh.src)} muted startFrom={Math.max(0, Math.round(sh.offset * fps) - lead)} style={style} />
        ) : (
          <Img src={staticFile(sh.src)} style={style} />
        )}
      </Sequence>
    </AbsoluteFill>
  );
};

const ShotLayer: React.FC<{T: Timeline; t: number; punch: number}> = ({T, t, punch}) => {
  const {fps} = useVideoConfig();
  const shots = T.shots!;
  let i = shots.findIndex((x) => t >= x.start && t < x.end);
  if (i < 0) i = t < shots[0].start ? 0 : shots.length - 1;
  const cur = shots[i], nxt = shots[i + 1], prv = shots[i - 1];
  const layers: {sh: Shot; idx: number; fx: Fx}[] = [];
  let curFx: Fx = {...NOFX};
  // outgoing side of the next boundary
  if (nxt) {
    const tb = nxt.start, kind = nxt.tin ?? 'cut', dir = nxt.dir ?? 1;
    if (kind === 'slide' && t >= tb - WHIP) {
      const e = quartInOut(clamp01((t - (tb - WHIP)) / (2 * WHIP)));
      const b = 20 * Math.sin(Math.PI * e);
      curFx = {x: -dir * 1080 * e, mul: 1, blur: b, op: 1};
      layers.push({sh: nxt, idx: i + 1, fx: {x: dir * 1080 * (1 - e), mul: 1, blur: b, op: 1}});
    } else if (kind === 'zoom' && t >= tb - 0.2) {
      const e = pow3In(clamp01((t - (tb - 0.2)) / 0.2));
      curFx = {x: 0, mul: 1 + 0.2 * e, blur: 10 * e, op: 1 - 0.85 * e};
    } else if (kind === 'inverse' && t >= tb - 0.2) {
      const e = pow3In(clamp01((t - (tb - 0.2)) / 0.2));
      curFx = {x: 0, mul: 1 - 0.12 * e, blur: 10 * e, op: 1 - 0.6 * e};
    }
  }
  // incoming side of the previous boundary
  if (prv) {
    const age = t - cur.start, kind = cur.tin ?? 'cut', dir = cur.dir ?? 1;
    if (kind === 'slide' && age < WHIP) {
      const e = quartInOut(clamp01((age + WHIP) / (2 * WHIP)));
      const b = 20 * Math.sin(Math.PI * e);
      curFx = {...curFx, x: dir * 1080 * (1 - e), blur: Math.max(curFx.blur, b)};
      layers.push({sh: prv, idx: i - 1, fx: {x: -dir * 1080 * e, mul: 1, blur: b, op: 1}});
    } else if (kind === 'zoom' && age < 0.5) {
      const e = expoOut(clamp01(age / 0.5));
      curFx = {...curFx, mul: curFx.mul * lerp(0.86, 1, e), blur: Math.max(curFx.blur, 10 * (1 - e))};
    } else if (kind === 'inverse' && age < 0.5) {
      const e = expoOut(clamp01(age / 0.5));
      curFx = {...curFx, mul: curFx.mul * lerp(1.25, 1, e), blur: Math.max(curFx.blur, 10 * (1 - e))};
    } else if (kind === 'cut' && age < 0.25) {
      // tiny settle so a re-frame cut lands rather than pops
      curFx = {...curFx, mul: curFx.mul * lerp(1.025, 1, expoOut(clamp01(age / 0.25)))};
    }
  }
  layers.push({sh: cur, idx: i, fx: curFx});
  return (
    <AbsoluteFill style={{backgroundColor: C.bg, overflow: 'hidden'}}>
      <AbsoluteFill style={{filter: 'contrast(1.06) saturate(1.08)'}}>
        {layers.map((l) => (
          <ShotFrame key={l.idx} sh={l.sh} idx={l.idx} t={t} fx={l.fx} punch={l.sh === cur ? punch : 0} fps={fps} />
        ))}
      </AbsoluteFill>
      <Grade t={t} />
    </AbsoluteFill>
  );
};

// One grade over everything so stills, clips and chart read as one film: legibility gradient, vignette, fine grain.
const Grade: React.FC<{t: number}> = ({t}) => {
  const seed = Math.floor(t * 12) % 16;
  return (
    <>
      <AbsoluteFill style={{background: 'linear-gradient(180deg, rgba(8,10,16,.68) 0%, rgba(8,10,16,.10) 26%, rgba(8,10,16,.04) 55%, rgba(8,10,16,.66) 100%)'}} />
      <AbsoluteFill style={{background: 'radial-gradient(ellipse 85% 70% at 50% 46%, rgba(0,0,0,0) 55%, rgba(0,0,0,.42) 100%)'}} />
      <svg width={1080} height={1920} style={{position: 'absolute', opacity: 0.07, mixBlendMode: 'overlay'}}>
        <filter id="grain"><feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves={2} seed={seed} stitchTiles="stitch" /></filter>
        <rect width="100%" height="100%" filter="url(#grain)" />
      </svg>
    </>
  );
};
