import type { EngineInterface, Register } from 'claude-code'

// /chats, /open, /pin and /delete for the chats in this folder. /chats numbers them, pinned ones first,
// so the other commands can name a chat by that number (or by part of its title; no argument = this
// chat). /delete moves the transcript to the desktop trash, where it can be restored.

type Chat = { id: string; title: string; modified: number; files: string[] }

// Lists the folder's chats the way Claude Code stores them, newest first
// (~/.claude/projects/<folder with every non-alphanumeric as "-">/<id>.jsonl, plus a <id>/ folder).
// Title: the /rename name, else Claude Code's own title, else the first prompt.
const LIST = String.raw`
import json, os, sys
folder = os.path.expanduser('~/.claude/projects/' + ''.join(c if c.isalnum() else '-' for c in sys.argv[1]))
try:
    names = [n for n in os.listdir(folder) if n.endswith('.jsonl')]
except OSError:
    names = []
rows = []
for name in names:
    try:
        rows.append((os.stat(os.path.join(folder, name)).st_mtime, name[:-6]))
    except OSError:
        pass
rows.sort(reverse=True)
out = []
for mtime, sid in rows:
    path = os.path.join(folder, sid + '.jsonl')
    custom = ai = first = None
    with open(path, 'rb') as f:
        for raw in f:
            if b'"custom-title"' in raw or b'"ai-title"' in raw:
                try:
                    o = json.loads(raw)
                except ValueError:
                    continue
                if o.get('type') == 'custom-title':
                    custom = o.get('customTitle') or custom
                elif o.get('type') == 'ai-title':
                    ai = o.get('aiTitle') or ai
            elif first is None and b'"type":"user"' in raw and b'"isMeta":true' not in raw:
                try:
                    o = json.loads(raw)
                except ValueError:
                    continue
                c = (o.get('message') or {}).get('content')
                if isinstance(c, str) and c.strip() and not c.lstrip().startswith('<'):
                    first = c
    title = custom or ai or first
    if not title:
        continue  # nothing typed in it: not a chat to list
    files = [path] + ([os.path.join(folder, sid)] if os.path.isdir(os.path.join(folder, sid)) else [])
    out.append({'id': sid, 'title': ' '.join(title.split())[:200], 'modified': int(mtime * 1000), 'files': files})
print(json.dumps(out))
`

// Removes a transcript that holds no messages (only Claude Code's bookkeeping lines).
const SWEEP = String.raw`
import os, sys
path = sys.argv[1]
if os.path.exists(path):
    with open(path, 'rb') as f:
        data = f.read()
    if b'"type":"user"' not in data and b'"type":"assistant"' not in data:
        os.remove(path)
`

/** How many unpinned chats /chats shows. */
const SHOWN = 25

async function listChats($: EngineInterface): Promise<Chat[]> {
  const cwd = await $.session.cwd()
  const run = await $.process.run(['python3', '-I', '-c', LIST, cwd], { timeoutMs: 30_000 })
  if (run.exitCode !== 0) return []
  try {
    return JSON.parse(run.stdout) as Chat[]
  } catch {
    return []
  }
}

async function pinnedIds($: EngineInterface): Promise<string[]> {
  const value = await $.store.get('pinned')
  return Array.isArray(value) ? value.filter((v): v is string => typeof v === 'string') : []
}

/** Pinned chats first (most recently pinned on top), then the rest, newest first. */
function ordered(chats: Chat[], pins: string[]): Chat[] {
  const pinned = pins.map(id => chats.find(c => c.id === id)).filter((c): c is Chat => c !== undefined)
  return [...pinned, ...chats.filter(c => !pins.includes(c.id)).slice(0, SHOWN)]
}

/** The chat an argument names: a number from the last /chats list, an ID, or part of a title. No argument: this chat. */
async function resolve($: EngineInterface, arg: string): Promise<Chat | string> {
  const chats = await listChats($)
  const text = arg.trim()
  if (!text) {
    const id = await $.session.id()
    return chats.find(c => c.id === id) ?? 'This chat has nothing saved yet. Send a message first.'
  }
  if (/^\d+$/.test(text)) {
    const last = await $.store.get('lastList')
    const id = Array.isArray(last) ? last[Number(text) - 1] : undefined
    return chats.find(c => c.id === id) ?? `There's no chat ${text}. Run /chats to see the numbers.`
  }
  const byId = text.length >= 8 ? chats.find(c => c.id.startsWith(text)) : undefined
  if (byId) return byId
  const matches = chats.filter(c => c.title.toLowerCase().includes(text.toLowerCase()))
  if (matches.length === 1) return matches[0]!
  if (matches.length > 1) return `"${text}" matches ${matches.length} chats. Use its number from /chats.`
  return `No chat matches "${text}". Run /chats to see them.`
}

/** Moves a chat's files to the desktop trash and unpins it. Returns an error message, or undefined. */
async function trash($: EngineInterface, chat: Chat): Promise<string | undefined> {
  const run = await $.process.run(['gio', 'trash', '--', ...chat.files], { timeoutMs: 15_000 })
  if (run.exitCode !== 0) return `Couldn’t delete “${chat.title}”: ${run.stderr.trim() || 'gio trash failed'}`
  await $.store.set('pinned', (await pinnedIds($)).filter(id => id !== chat.id))
  return undefined
}

function ago(ms: number): string {
  const minutes = Math.floor(ms / 60_000)
  if (minutes < 1) return 'now'
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  return days < 30 ? `${days}d ago` : `${Math.floor(days / 30)}mo ago`
}

function clip(text: string, width: number): string {
  return text.length > width ? text.slice(0, width - 1) + '…' : text.padEnd(width)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'chats', description: 'List the chats in this folder, pinned ones first, numbered' })
    await $.command.register({ name: 'open', description: 'Open a chat from /chats', argumentHint: '<number or name>' })
    await $.command.register({ name: 'pin', description: 'Pin or unpin a chat (no argument: this chat)', argumentHint: '[number or name]' })
    await $.command.register({ name: 'delete', description: 'Move a chat to the trash (no argument: this chat)', argumentHint: '[number or name]' })
    return next(e)
  })

  on('command.run', { command: 'chats' }, async $ => {
    const [chats, pins, current, now] = await Promise.all([listChats($), pinnedIds($), $.session.id(), $.clock.now()])
    if (chats.length === 0) return { text: 'No saved chats in this folder yet.' }
    const list = ordered(chats, pins)
    await $.store.set('lastList', list.map(c => c.id))
    const lines = list.map((chat, i) => {
      const mark = pins.includes(chat.id) ? '📌' : chat.id === current ? '▸ ' : '  '
      return `${mark} ${String(i + 1).padStart(2)}  ${clip(chat.title, 56)}  ${ago(now - chat.modified)}`
    })
    const more = chats.length - list.length
    const folder = (await $.session.cwd()).split('/').pop() || '/'
    return {
      text: [
        `Chats in ${folder}${pins.length ? ' (📌 pinned first)' : ''}:`,
        ...lines,
        ...(more > 0 ? [`        … and ${more} older (see /resume)`] : []),
        '',
        '/open 2 · /pin 2 · /delete 2 · /rename <name> renames this chat',
      ].join('\n'),
    }
  })

  on('command.run', { command: 'open' }, async ($, e) => {
    if (!e.args.trim()) return { text: 'Which chat? /open <number from /chats>, or /resume to pick from a list.' }
    const chat = await resolve($, e.args)
    if (typeof chat === 'string') return { text: chat }
    if (chat.id === (await $.session.id())) return { text: 'That’s this chat.' }
    // a command can't run another one while it runs: resume once this one has answered
    $.clock.after(0, () => void $.command.run({ command: 'resume', args: chat.id }))
    return {}
  })

  on('command.run', { command: 'pin' }, async ($, e) => {
    const chat = await resolve($, e.args)
    if (typeof chat === 'string') return { text: chat }
    const pins = await pinnedIds($)
    if (pins.includes(chat.id)) {
      await $.store.set('pinned', pins.filter(id => id !== chat.id))
      return { text: `Unpinned “${chat.title}”.` }
    }
    await $.store.set('pinned', [chat.id, ...pins])
    return { text: `📌 Pinned “${chat.title}”. It stays at the top of /chats.` }
  })

  on('command.run', { command: 'delete' }, async ($, e) => {
    const chat = await resolve($, e.args)
    if (typeof chat === 'string') return { text: chat }
    if (chat.id !== (await $.session.id())) {
      const result = await trash($, chat)
      return { text: result ?? `Deleted “${chat.title}” (moved to the trash; restore it from there if you need it back).` }
    }
    // the open chat: start a new one first, so nothing writes to the transcript as it goes. A command
    // can't run another one while it runs, so that happens once this one has answered.
    $.clock.after(0, () => {
      void (async () => {
        await $.command.run({ command: 'clear' })
        // Claude Code writes the old transcript's last lines (this command, cost totals) just after the
        // switch: trash it once that's done, and sweep up a stub of those lines if one turns up later
        $.clock.after(2500, () => {
          void (async () => {
            const result = await trash($, chat)
            $.ui.toast(result ?? `Deleted “${chat.title}” (moved to the trash)`)
            $.clock.after(3000, () => void $.process.run(['python3', '-I', '-c', SWEEP, chat.files[0]!], { timeoutMs: 5_000 }))
          })()
        })
      })()
    })
    return { text: `Deleting “${chat.title}” and starting a new chat…` }
  })
}
