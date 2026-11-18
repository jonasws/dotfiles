import type { Register } from 'claude-code'

const SGR = (code: string, s: string) => `\x1b[${code}m${s}\x1b[0m`
const dim = (s: string) => SGR('2', s)

const MARKS: Record<string, string> = {
  running: SGR('36', '●'),
  completed: SGR('32', '✓'),
  failed: SGR('31', '✗'),
  killed: SGR('2', '■'),
}

const BARS = ['▂', '▃', '▄', '▅', '▆', '▇', '█']

const human = (n: number) =>
  n >= 1_000_000 ? `${Math.floor(n / 100_000) / 10}M`
  : n >= 1000 ? `${Math.floor(n / 100) / 10}k`
  : String(n)

const took = (ms: number) => {
  const s = Math.floor(ms / 1000)
  if (s >= 3600) return `${Math.floor(s / 3600)}h${Math.floor((s % 3600) / 60)}m`
  if (s >= 60) return `${Math.floor(s / 60)}m${s % 60}s`
  return `${s}s`
}

// Growth between samples, not the count itself, which only climbs: a run of ▁
// is a subagent that has stopped producing.
const spark = (samples: number[]) => {
  const d = samples.slice(1).map((v, i) => Math.max(0, v - (samples[i] ?? 0)))
  const top = Math.max(0, ...d)
  return d
    .map(v => (v === 0 ? '▁' : BARS[Math.min(6, Math.ceil((v / top) * 7) - 1)] ?? '█'))
    .join('')
}

const clip = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1)}…` : s)

export const register: Register = on => {
  let sessionCwd = ''

  on('session.start', async ($, e, next) => {
    sessionCwd = await $.session.cwd()
    return next(e)
  })

  on('ui.render', { component: 'AgentRow' }, ($, e, next) => {
    const a = e.props
    const mark = MARKS[a.status] ?? dim('○')
    const who = a.name ?? a.type ?? 'agent'
    const what = (a.label ?? a.description ?? '').replace(/\s+/g, ' ')

    const tokens = [
      spark(a.tokenSamples ?? []),
      human(a.tokenCount ?? 0),
      a.contextWindowSize ? `${Math.floor(((a.tokenCount ?? 0) * 100) / a.contextWindowSize)}%` : '',
    ].filter(Boolean).join(' ')

    const model = [
      (a.model ?? '').replace(/^claude-/, '').replace(/-\d{8}$/, '').replace(/\[.*\]$/, ''),
      a.effort === undefined ? '' : String(a.effort),
    ].filter(Boolean).join(' ')

    const figures = [
      tokens,
      model,
      a.startTime ? took(Date.now() - a.startTime) : '',
      a.cwd && sessionCwd && a.cwd !== sessionCwd ? `⎇ ${a.cwd.split('/').pop()}` : '',
    ].filter(Boolean).join(' · ')

    const room = (a.columns ?? 80) - who.length - figures.length - 8
    const body =
      `${mark} ${who}` +
      (room >= 8 && what ? ` · ${clip(what, room)}` : '') +
      dim(` · ${figures}`)

    return next({ ...e, props: { ...a, body } })
  })

  // Your prompts are yellow text behind a one-cell person mark, in the column
  // where a reply has its dot. A UserMessage that carries `task` or `from` is
  // not typed by you, so it keeps the stock drawing.
  const MAX_LINES = 14
  const USER_COLOR = '#f9e2af'
  const USER_MARK = '\u{F007}'

  on('ui.render', { component: 'UserMessage' }, async ($, e, next) => {
    if (e.props?.task || e.props?.from) return next(e)
    if (typeof e.props?.text !== 'string') return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const lines = e.props.text.trim().split('\n')
    const cut = !e.props.isExpanded && lines.length > MAX_LINES
    const shown = (cut ? lines.slice(0, MAX_LINES) : lines).join('\n')
    return Box({
      flexDirection: 'row',
      children: [
        Box({ width: 2, flexShrink: 0, children: [Text({ color: USER_COLOR, children: [USER_MARK] })] }),
        Box({
          flexDirection: 'column',
          flexGrow: 1,
          children: [
            Text({ color: USER_COLOR, children: [shown] }),
            ...(cut ? [Text({ dimColor: true, children: [`… +${lines.length - MAX_LINES} lines`] })] : []),
          ],
        }),
      ],
    })
  })

  // One dim line, no rule and no margin: the turn line costs a row, not four.
  // The clock is stamped the first time a turn line is drawn, so a redraw keeps it.
  const doneAt = new Map<string, string>()
  on('ui.render', { component: 'TurnDuration' }, async ($, e, next) => {
    const { Text } = $.ui.resolve(e)
    const key = String(e.requestId ?? e.props?.durationMs)
    if (!doneAt.has(key)) {
      const d = new Date()
      doneAt.set(key, `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`)
    }
    const ms = Number(e.props?.durationMs ?? 0)
    return Text({
      dimColor: true,
      children: [`✻ ${e.props?.word ?? 'Worked'} for ${took(ms)} · ${doneAt.get(key)}`],
    })
  })
}
