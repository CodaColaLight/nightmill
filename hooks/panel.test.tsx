// hooks/panel.test.tsx - the slots pane of hooks/panel.tsx (iteration 32, #69), run by `claude plugin test .`.
// The engine is mocked beneath the module: every `$` call the module makes is answered by a hook here, the panel
// script's output is the bytes of tests/fixtures/panel/run-stall-old-free/expected.txt (written below as a string),
// and the clock is the kit's mock clock, so nothing sleeps. Each pane case is drawn on the terminal, the Desktop app
// and the VS Code extension.
import { expect, mock, test } from 'claude-code/testing'

const PANE_ID = 'nightmill-slots'
const PLUGIN = 'nightmill'

// The output of scripts/panel.sh for the fixture run-stall-old-free (tests/fixtures/panel/run-stall-old-free/expected.txt)
const GOOD = [
  'time\t12:00:00',
  'every\t15',
  'slot\t1\tbusy\trunning\tfeat/run\tnext/implementer\tcheck\t5m',
  'slot\t2\tbusy\tstalled\tfeat/stall\tfix/fixer\ttest\t2h',
  'slot\t3\tbusy\tunknown\tfeat/old\t?\t?\t-',
  'slot\t4\tfree\t\t\t\t\t',
  '',
].join('\n')

// the same slots a quarter of a minute later: slot 1 has moved on from check to test
const LATER = GOOD.replace('time\t12:00:00', 'time\t12:00:15').replace('next/implementer\tcheck\t5m', 'next/implementer\ttest\t5m')

const SURFACES = ['terminal', 'desktop', 'vscode'] as const
type Surface = (typeof SURFACES)[number]

type Answer = { value: { exitCode: number; stdout: string; stderr: string } } | { deny: string }
const ok = (stdout: string): Answer => ({ value: { exitCode: 0, stdout, stderr: '' } })
const failed = (code: number, stderr: string): Answer => ({ value: { exitCode: code, stdout: '', stderr } })

const COMMAND_INPUT = (args: string) => ({
  command: 'nightmill-slots',
  args,
  origin: { kind: 'composer' as const },
  presentation: { isFullscreen: true, columns: 180 },
})

const paneInput = (surface: Surface) =>
  ({
    plugin: PLUGIN,
    component: 'Pane',
    surface,
    requestId: PANE_ID,
    viewport: { columns: 180, rows: 48, isFullscreen: true },
    props: {
      title: 'nightmill slots',
      isFocused: false,
      bodyColumns: 100,
      placement: 'dock',
      scroll: { offset: 0, bodyRows: 44 },
      view: {},
    },
  }) as never

type Node = { type?: string; props?: Record<string, unknown>; children?: unknown[] } | string | null | undefined

const stringsOf = (node: Node): string[] => {
  if (node === null || node === undefined) return []
  if (typeof node === 'string') return [node]
  return (node.children ?? []).flatMap(child => stringsOf(child as Node))
}
const textOf = (node: Node): string => stringsOf(node).join('')
const elementsOf = (node: Node, type: string): Exclude<Node, string | null | undefined>[] => {
  if (node === null || node === undefined || typeof node === 'string') return []
  return [...(node.type === type ? [node] : []), ...(node.children ?? []).flatMap(child => elementsOf(child as Node, type))]
}
// the rows of the table: a Box laid out in a row that holds one cell per column (7)
const tableRows = (node: Node) =>
  elementsOf(node, 'Box').filter(box => box.props?.flexDirection === 'row' && (box.children ?? []).length === 7)

type World = {
  clock: ReturnType<typeof mock.clock>
  runs: { argv: string[]; init: { cwd?: string; timeoutMs?: number } }[]
  opened: { id: string; title?: string }[]
  closed: string[]
  registered: { name: string; description?: string; argumentHint?: string; immediate?: boolean }[]
  /** what the panel script answers; set it between reads */
  answer: { current: Answer }
  /** the panes `$.ui.panes()` lists */
  listed: { current: string[] }
  /** what `$.ui.open` answers */
  placed: { current: { isPlaced: boolean; reason?: string } }
  /** the answer to `$.env.get('OS')` */
  os: { current: string | undefined }
}

// The engine beneath the module, in memory: it answers every call and records what the module asked for.
function worldOf(on: any): World {
  const world: World = {
    clock: mock.clock(on),
    runs: [],
    opened: [],
    closed: [],
    registered: [],
    answer: { current: ok(GOOD) },
    listed: { current: [] },
    placed: { current: { isPlaced: true } },
    os: { current: undefined },
  }
  on('session.start', ($: any, e: any) => ({ cwd: e.cwd }))
  on('session.cwd', () => ({ value: '/work' }))
  on('env.get', ($: any, e: any) => ({ value: e.name === 'OS' ? world.os.current : undefined }))
  on('command.register', ($: any, e: any) => {
    world.registered.push({ name: e.name, description: e.description, argumentHint: e.argumentHint, immediate: e.immediate })
    return { value: { command: e.name } }
  })
  on('ui.open', ($: any, e: any) => {
    world.opened.push({ id: e.id, title: e.title })
    if (world.placed.current.isPlaced) world.listed.current = [e.id]
    return { value: world.placed.current }
  })
  on('ui.panes', () => ({ value: world.listed.current.map(id => ({ id, title: 'nightmill slots' })) }))
  on('ui.close', ($: any, e: any) => {
    world.closed.push(e.id)
    world.listed.current = world.listed.current.filter(id => id !== e.id)
    return { value: undefined }
  })
  on('ui.invalidate', () => ({ value: undefined }))
  on('process.run', ($: any, e: any) => {
    world.runs.push({ argv: e.argv, init: e.init ?? {} })
    return world.answer.current
  })
  return world
}

const START = { surface: 'terminal', isInteractive: true, cwd: '/work' } as never

async function openPane($: any, world: World) {
  await $.session.start(START)
  const answer = await $.command.run(COMMAND_INPUT(''))
  await world.clock.settle()
  return answer
}

async function drawn($: any, surface: Surface) {
  const tree = await $.ui.render(paneInput(surface))
  // the surface's element table must accept what the module drew
  const mounted = await ($ as any).ui.mount(paneInput(surface))
  await mounted.unmount()
  expect(mounted.surface, 'the pane is drawn on the surface it was mounted on').toBe(surface)
  return tree as Node
}

for (const surface of SURFACES) {
  test(`the pane shows every slot with its agent, branch, skill, step and report age on ${surface}`, async ($, on) => {
    const world = worldOf(on)
    await openPane($, world)

    const tree = await drawn($, surface)
    const text = textOf(tree)
    expect(text).toContain('read at 12:00:00, every 15 s')

    const rows = tableRows(tree)
    expect(rows.length, 'a header row and one row per slot').toBe(5)
    const [header, one, two, three, four] = rows.map(row => textOf(row))
    for (const column of ['slot', 'State', 'Agent', 'Branch', 'Skill', 'Step', 'Report']) expect(header).toContain(column)
    for (const cell of ['1', 'busy', 'running', 'feat/run', 'next/implementer', 'check', '5m']) expect(one).toContain(cell)
    for (const cell of ['2', 'busy', 'stalled', 'feat/stall', 'fix/fixer', 'test', '2h']) expect(two).toContain(cell)
    for (const cell of ['3', 'busy', 'unknown', 'feat/old', '?', '-']) expect(three).toContain(cell)
    expect(four).toContain('free')
    expect(four, 'a free slot has no agent').not.toContain('running')
    expect(four).not.toContain('stalled')
    expect(four).not.toContain('unknown')
  })
}

// every way a read can fail ends in unknown with a reason, and never in a free or a running slot
const FAILURES: [string, Answer][] = [
  ['a script that exits non-zero', failed(1, 'panel: no x (run /nightmill:init)')],
  ['a script that cannot start', { deny: 'spawn bash ENOENT' }],
  ['output the pane cannot parse', ok('time\t12:00:00\nevery\t15\nslot\t1\tfree\n')],
  ['a script that printed nothing', ok('')],
  ['a script that exited 3 with no message', failed(3, '')],
]

for (const surface of SURFACES) {
  for (const [name, answer] of FAILURES) {
    test(`unknown, never free, when the read fails with ${name}, on ${surface}`, async ($, on) => {
      const world = worldOf(on)
      world.answer.current = answer
      await openPane($, world)

      const tree = await drawn($, surface)
      const text = textOf(tree)
      expect(text).toContain('unknown: the slots could not be read (')
      expect(text, 'a slot that cannot be read is never free').not.toContain('free')
      expect(text).not.toContain('running')
      expect(text).not.toContain('stalled')
      expect(tableRows(tree).length, 'no slot rows').toBe(0)
    })
  }
}

test('a failed read drops the rows of the last good read', async ($, on) => {
  const world = worldOf(on)
  await openPane($, world)
  const before = textOf(await drawn($, 'terminal'))
  expect(before).toContain('feat/run')

  world.answer.current = failed(1, 'WORKER_SLOTS must be a number from 1 to 99')
  await world.clock.advance(15000)
  await world.clock.settle()
  const after = textOf(await drawn($, 'terminal'))
  expect(after).toContain('unknown')
  expect(after).toContain('WORKER_SLOTS must be a number from 1 to 99')
  expect(after, 'a stale table would show slots as running that may no longer be').not.toContain('feat/run')
  expect(after).not.toContain('running')
})

test('on Windows the pane runs scripts/panel.ps1 with Windows PowerShell', async ($, on) => {
  const world = worldOf(on)
  world.os.current = 'Windows_NT'
  await openPane($, world)
  expect(world.runs.length).toBeGreaterThanOrEqual(1)
  const argv = world.runs[0]!.argv
  expect(argv.slice(0, 5)).toEqual(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File'])
  expect(argv.length).toBe(6)
  expect(argv[5], 'the plugin folder, a slash, scripts/panel.ps1').toMatch(/^.+\/scripts\/panel\.ps1$/)
  expect(world.runs[0]!.init.cwd, 'the script runs in the session folder').toBe('/work')
  expect(world.runs[0]!.init.timeoutMs).toBe(20000)
})

test('elsewhere the pane runs scripts/panel.sh with bash', async ($, on) => {
  const world = worldOf(on)
  world.os.current = undefined
  await openPane($, world)
  expect(world.runs.length).toBeGreaterThanOrEqual(1)
  const argv = world.runs[0]!.argv
  expect(argv.length).toBe(2)
  expect(argv[0]).toBe('bash')
  expect(argv[1], 'the plugin folder, a slash, scripts/panel.sh').toMatch(/^.+\/scripts\/panel\.sh$/)
  expect(world.runs[0]!.init.cwd).toBe('/work')
  expect(world.runs[0]!.init.timeoutMs).toBe(20000)
})

test('nothing is opened, started or run until the person asks', async ($, on) => {
  const world = worldOf(on)
  await $.session.start(START)
  await world.clock.settle()
  await world.clock.advance(10 * 60 * 1000)
  await world.clock.settle()

  expect(world.opened, 'no pane opens by itself').toEqual([])
  expect(world.runs, 'no process runs and no timer was started').toEqual([])
  expect(world.registered.map(c => c.name), 'only the command is offered').toEqual([PANE_ID])
})

test('the command /nightmill-slots is offered in an interactive session, immediate, with the hint [off]', async ($, on) => {
  const world = worldOf(on)
  await $.session.start(START)
  expect(world.registered.length).toBe(1)
  expect(world.registered[0]!.name).toBe(PANE_ID)
  expect(world.registered[0]!.immediate, 'it can open the pane while a turn is running').toBe(true)
  expect(world.registered[0]!.argumentHint).toBe('[off]')
  expect(String(world.registered[0]!.description)).toContain('read-only')
})

test('a session that is not interactive is offered no command and nothing runs', async ($, on) => {
  const world = worldOf(on)
  await $.session.start({ surface: 'terminal', isInteractive: false, cwd: '/work' } as never)
  await world.clock.advance(120000)
  await world.clock.settle()
  expect(world.registered).toEqual([])
  expect(world.opened).toEqual([])
  expect(world.runs).toEqual([])
})

test('the command opens the pane and says how to close it', async ($, on) => {
  const world = worldOf(on)
  const answer = await openPane($, world)
  expect(world.opened).toEqual([{ id: PANE_ID, title: 'nightmill slots' }])
  expect(answer.text).toBe('Slots pane opened; it reads the slots every 15 s while it is open. /nightmill-slots off closes it.')
})

test('off closes the pane and stops the reading when it is open', async ($, on) => {
  const world = worldOf(on)
  await openPane($, world)
  expect(world.runs.length).toBe(1)

  const answer = await $.command.run(COMMAND_INPUT('off'))
  await world.clock.settle()
  expect(answer.text).toBe('Slots pane closed.')
  expect(world.closed).toEqual([PANE_ID])

  await world.clock.advance(10 * 60 * 1000)
  await world.clock.settle()
  expect(world.runs.length, 'the timer was cancelled: no read after off').toBe(1)
})

test('off says the pane is not open when it is not listed, and closes nothing', async ($, on) => {
  const world = worldOf(on)
  await $.session.start(START)
  const answer = await $.command.run(COMMAND_INPUT('off'))
  expect(answer.text).toBe('The slots pane is not open.')
  expect(world.closed).toEqual([])
})

test('an argument other than off answers the usage and opens nothing', async ($, on) => {
  const world = worldOf(on)
  await $.session.start(START)
  const answer = await $.command.run(COMMAND_INPUT('x'))
  await world.clock.advance(120000)
  await world.clock.settle()
  expect(answer.text).toBe('usage: /nightmill-slots [off]')
  expect(world.opened).toEqual([])
  expect(world.runs).toEqual([])
})

test('a pane that cannot be placed says so and starts no timer', async ($, on) => {
  const world = worldOf(on)
  world.placed.current = { isPlaced: false, reason: 'no surface' }
  await $.session.start(START)
  const answer = await $.command.run(COMMAND_INPUT(''))
  await world.clock.settle()
  expect(String(answer.text).startsWith('The slots pane cannot be shown here')).toBe(true)
  expect(answer.text).toContain('no surface')

  await world.clock.advance(10 * 60 * 1000)
  await world.clock.settle()
  expect(world.runs, 'no timer was started and nothing was read').toEqual([])
})

test('the interval follows the script: an every record of 30 restarts the timer at 30 seconds', async ($, on) => {
  const world = worldOf(on)
  world.answer.current = ok(GOOD.replace('every\t15', 'every\t30'))
  await openPane($, world)
  expect(world.runs.length).toBe(1)

  await world.clock.advance(15000)
  await world.clock.settle()
  expect(world.runs.length, 'the old 15 s timer is gone').toBe(1)

  await world.clock.advance(15000)
  await world.clock.settle()
  expect(world.runs.length, 'the new timer fires at 30 s').toBe(2)

  await world.clock.advance(30000)
  await world.clock.settle()
  expect(world.runs.length).toBe(3)
})

test('the pane updates while a run is going, without being asked again', async ($, on) => {
  const world = worldOf(on)
  await openPane($, world)
  expect(world.runs.length).toBe(1)
  const first = textOf(await drawn($, 'terminal'))
  expect(first).toContain('check')

  world.answer.current = ok(LATER)
  await world.clock.advance(15000)
  await world.clock.settle()
  expect(world.runs.length, 'the timer started a new read').toBe(2)

  for (const surface of SURFACES) {
    const text = textOf(await drawn($, surface))
    expect(text, `${surface}: redrawn from the new read`).toContain('read at 12:00:15')
    expect(text, `${surface}: the new step`).toContain('test')
    expect(text, `${surface}: the old step is gone`).not.toContain('check')
  }
})

test('the pane is read-only: it draws no button, input, select or link and no handler', async ($, on) => {
  const world = worldOf(on)
  await openPane($, world)
  for (const surface of SURFACES) {
    const tree = await drawn($, surface)
    for (const type of ['Button', 'Input', 'Select', 'Link']) {
      expect(elementsOf(tree, type), `${surface}: a ${type} was drawn`).toEqual([])
    }
    const everything = (node: Node): Exclude<Node, string | null | undefined>[] =>
      node === null || node === undefined || typeof node === 'string' ? [] : [node, ...(node.children ?? []).flatMap(c => everything(c as Node))]
    for (const element of everything(tree)) {
      for (const prop of Object.keys(element.props ?? {})) {
        expect(prop.startsWith('on'), `${surface}: ${element.type} has the handler prop ${prop}`).toBe(false)
      }
    }
  }
})

test('the pane shows the notes of the script and the empty case', async ($, on) => {
  const world = worldOf(on)
  world.answer.current = ok(GOOD + 'note\tworktrees.panelRefreshSeconds must be a whole number from 5 to 3600; using 15\n')
  await openPane($, world)
  const text = textOf(await drawn($, 'terminal'))
  expect(text).toContain('note: worktrees.panelRefreshSeconds must be a whole number from 5 to 3600; using 15')
  expect(text).toContain('feat/run')

  world.answer.current = ok('time\t12:00:00\nevery\t15\nnoslots\n')
  await world.clock.advance(15000)
  await world.clock.settle()
  const empty = textOf(await drawn($, 'terminal'))
  expect(empty).toContain('No slots: .claude/nightmill.json has no worktrees section.')
  expect(tableRows(await drawn($, 'terminal')).length).toBe(0)
})
