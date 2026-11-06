// hooks/panel.tsx - the slots pane beside the Claude chat (nightmill, iteration 32).
// /nightmill-slots opens a read-only pane with every slot, free or busy, its agent (running, stalled, unknown),
// branch, skill, step and the age of the last report, and reads them again every worktrees.panelRefreshSeconds
// seconds while it is open; /nightmill-slots off, or the pane's close mark, closes it and stops the reading.
// Nothing runs until the command is given. The data comes only from scripts/panel.sh (scripts/panel.ps1 on
// Windows), which runs the slot script's porcelain status once per read; this module reads no file and decides
// nothing itself: it splits the script's lines and draws them. The rules are in docs/specs/iteration-32-panel.md.
import type { EngineInterface, Register, Timer } from 'claude-code'

type Engine = EngineInterface

const PANE_ID = 'nightmill-slots'
const PANE_TITLE = 'nightmill slots'
const AGENTS = ['running', 'stalled', 'unknown']
const UNREADABLE = 'the panel script printed a line the pane cannot read'

type Row = { slot: string; busy: boolean; agent: string; branch: string; skill: string; step: string; report: string }
type View =
  | { kind: 'reading' }
  | { kind: 'slots'; time: string; every: number; rows: Row[]; notes: string[] }
  | { kind: 'noslots'; time: string; every: number; notes: string[] }
  | { kind: 'unknown'; reason: string; time?: string; every?: number }

// module variables: a reload of the module starts them over, and the next read fills the view again
let view: View = { kind: 'reading' }
let timer: Timer | undefined = undefined
let everySeconds = 15
let isReading = false

function firstLine(text: string): string {
  for (const line of text.split('\n')) {
    const t = line.replace(/\r$/, '').replace(/ +$/, '')
    if (t !== '') return t
  }
  return ''
}

// the records of the panel script; a line out of order or of the wrong form makes the whole read unknown
function parse(stdout: string): View {
  const lines = stdout
    .split('\n')
    .map(line => line.replace(/\r$/, ''))
    .filter(line => line !== '')
  const bad: View = { kind: 'unknown', reason: UNREADABLE }
  if (lines.length < 2) return bad
  const t = lines[0]!.split('\t')
  if (t.length !== 2 || t[0] !== 'time' || !/^\d\d:\d\d:\d\d$/.test(t[1]!)) return bad
  const time = t[1]!
  const ev = lines[1]!.split('\t')
  if (ev.length !== 2 || ev[0] !== 'every' || !/^[1-9]\d{0,3}$/.test(ev[1]!)) return bad
  const every = Number(ev[1])
  if (every < 5 || every > 3600) return bad
  let i = 2
  const rows: Row[] = []
  let body: 'slots' | 'noslots' | 'unknown' | undefined
  let reason = ''
  const first = lines[i]?.split('\t')
  if (first && first[0] === 'noslots' && first.length === 1) {
    body = 'noslots'
    i++
  } else if (first && first[0] === 'unknown' && first.length === 2) {
    body = 'unknown'
    reason = first[1]!
    i++
  } else {
    while (i < lines.length) {
      const f = lines[i]!.split('\t')
      if (f[0] !== 'slot') break
      if (f.length !== 8) return bad
      if (f[2] === 'free') {
        if (f.slice(3).some(cell => cell !== '')) return bad
        rows.push({ slot: f[1]!, busy: false, agent: '', branch: '', skill: '', step: '', report: '' })
      } else if (f[2] === 'busy') {
        const agent = AGENTS.includes(f[3]!) ? f[3]! : 'unknown'
        rows.push({ slot: f[1]!, busy: true, agent, branch: f[4]!, skill: f[5]!, step: f[6]!, report: f[7]! })
      } else return bad
      i++
    }
    if (rows.length === 0) return bad
    body = 'slots'
  }
  const notes: string[] = []
  for (; i < lines.length; i++) {
    const f = lines[i]!.split('\t')
    if (f.length !== 2 || f[0] !== 'note') return bad
    notes.push(f[1]!)
  }
  if (body === 'unknown') return { kind: 'unknown', reason, time, every }
  if (body === 'noslots') return { kind: 'noslots', time, every, notes }
  return { kind: 'slots', time, every, rows, notes }
}

async function isOpen($: Engine): Promise<boolean> {
  const panes = await $.ui.panes()
  return panes.some(pane => pane.id === PANE_ID)
}

function startTimer($: Engine) {
  if (timer) return
  timer = $.clock.every(everySeconds * 1000, () => {
    void tick($)
  })
}

function stopTimer() {
  if (timer) timer.cancel()
  timer = undefined
}

async function tick($: Engine) {
  if (!(await isOpen($))) {
    stopTimer()
    return
  }
  if (!isReading) await readSlots($)
}

// one read: run the panel script, set the view from its answer, follow its interval, redraw
async function readSlots($: Engine) {
  isReading = true
  try {
    const isWindows = (await $.env.get('OS')) === 'Windows_NT'
    const root = $.plugin.root
    const argv = isWindows
      ? ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', `${root}/scripts/panel.ps1`]
      : ['bash', `${root}/scripts/panel.sh`]
    let next: View
    try {
      const ran = await $.process.run(argv, { cwd: await $.session.cwd(), timeoutMs: 20000 })
      if (ran.exitCode !== 0) {
        next = { kind: 'unknown', reason: firstLine(ran.stderr) || `panel script exited with code ${ran.exitCode}` }
      } else next = parse(ran.stdout)
    } catch (err) {
      const message = firstLine(String(err instanceof Error ? err.message : err)) || 'no message'
      next = { kind: 'unknown', reason: `the panel script did not run: ${message}` }
    }
    view = next
    if (next.kind !== 'reading' && next.every !== undefined && next.every !== everySeconds) {
      everySeconds = next.every
      if (timer) {
        stopTimer()
        startTimer($)
      }
    }
  } finally {
    isReading = false
  }
  await $.ui.invalidate('ui.render')
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    if (e.isInteractive) {
      await $.command.register({
        name: PANE_ID,
        description: 'Show the nightmill slots and their agents in a pane beside the chat (read-only)',
        argumentHint: '[off]',
        immediate: true,
      })
      // the pane stayed open across a reload of the module: keep reading
      if (await isOpen($)) {
        startTimer($)
        void readSlots($)
      }
    }
    return next(e)
  })

  on('command.run', { command: PANE_ID }, async ($, e) => {
    const args = String(e.args ?? '').trim()
    if (args === '') {
      const opened = await $.ui.open({ id: PANE_ID, title: PANE_TITLE })
      if (!opened.isPlaced) {
        return { text: `The slots pane cannot be shown here (${opened.reason}). /nightmill:status shows the same slots.` }
      }
      startTimer($)
      void readSlots($)
      return {
        text: `Slots pane opened; it reads the slots every ${everySeconds} s while it is open. /nightmill-slots off closes it.`,
      }
    }
    if (args === 'off') {
      if (!(await isOpen($))) return { text: 'The slots pane is not open.' }
      stopTimer()
      await $.ui.close({ id: PANE_ID })
      return { text: 'Slots pane closed.' }
    }
    return { text: 'usage: /nightmill-slots [off]' }
  })

  on('ui.close', { id: PANE_ID }, async ($, e, next) => {
    stopTimer()
    return next(e)
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'Pane', requestId: PANE_ID }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const v = view
    if (v.kind === 'reading') {
      return (
        <Box flexDirection="column">
          <Text dimColor>reading the slots...</Text>
        </Box>
      )
    }
    if (v.kind === 'unknown') {
      return (
        <Box flexDirection="column">
          {v.time !== undefined && <Text dimColor>read at {v.time}</Text>}
          <Text>unknown: the slots could not be read ({v.reason})</Text>
        </Box>
      )
    }
    const head = <Text dimColor>{`read at ${v.time}, every ${v.every} s`}</Text>
    const notes = v.notes.map(note => <Text dimColor>{`note: ${note}`}</Text>)
    if (v.kind === 'noslots') {
      return (
        <Box flexDirection="column">
          {head}
          <Text>No slots: .claude/nightmill.json has no worktrees section.</Text>
          {notes}
        </Box>
      )
    }
    const header = ['slot', 'State', 'Agent', 'Branch', 'Skill', 'Step', 'Report']
    const cells = v.rows.map(r =>
      r.busy ? [r.slot, 'busy', r.agent, r.branch, r.skill, r.step, r.report] : [r.slot, 'free', '', '', '', '', ''],
    )
    // (no variable is named h: JSX compiles against the global h)
    const widths = header.map((name, c) => Math.max(name.length, ...cells.map(row => row[c]!.length)) + 2)
    const agentColor = (agent: string) => (agent === 'running' ? 'success' : agent === 'stalled' ? 'warning' : 'inactive')
    const headerRow = (
      <Box flexDirection="row">
        {header.map((name, c) => (
          <Box width={widths[c]}>
            <Text wrap="truncate-end">{name}</Text>
          </Box>
        ))}
      </Box>
    )
    const rows = v.rows.map((r, n) => (
      <Box flexDirection="row">
        {cells[n]!.map((cell, c) => (
          <Box width={widths[c]}>
            {c === 1 && !r.busy ? (
              <Text wrap="truncate-end" dimColor>
                {cell}
              </Text>
            ) : c === 2 && r.busy ? (
              <Text wrap="truncate-end" color={agentColor(r.agent)}>
                {cell}
              </Text>
            ) : (
              <Text wrap="truncate-end">{cell}</Text>
            )}
          </Box>
        ))}
      </Box>
    ))
    return (
      <Box flexDirection="column">
        {head}
        {headerRow}
        {rows}
        {notes}
      </Box>
    )
  })
}
