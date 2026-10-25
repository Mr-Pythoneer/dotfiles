# chat-tools

Four slash commands for Claude Code that manage the chats in the current folder. Claude Code's look doesn't change.

| Command | Does |
| --- | --- |
| `/chats` | Numbered list of this folder's chats. Pinned ones (📌) come first, then the 25 newest; ▸ marks the chat you're in |
| `/open <number or name>` | Open a chat from that list |
| `/pin [number or name]` | Pin a chat, or unpin it if it's already pinned. No argument: the chat you're in |
| `/delete [number or name]` | Move a chat to the desktop trash, where you can restore it from your file manager. No argument: the chat you're in, which starts a new chat first |

A name is any part of a chat's title, as long as it matches one chat. Titles come from `/rename`, otherwise Claude
Code's own title, otherwise the first message. Pins are kept across sessions.

Claude Code's own `/resume` picker can't be reordered, so pins show in `/chats`, not in `/resume`.

## Install

```sh
claude plugin marketplace add ~/.local/src/claude-chat-tools
claude plugin install chat-tools@claude-chat-tools
```

Edits to `hooks/register.ts` take effect the next time Claude Code starts. To turn it off, run
`claude plugin disable chat-tools@claude-chat-tools`.

Needs `python3` (reads the chat list) and `gio` (the trash).
