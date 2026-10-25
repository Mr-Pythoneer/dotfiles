# news-brief

Tech and politics news, twice a day. At 7:30 and 20:30 a notification asks
"Your morning news is ready, want to see it?" Clicking it opens a page with:

- **a short summary at the top**: one or two sentences on what matters most, then 3–5 points each for
  Tech and Politics. Each point has chips for the articles it was written from.
- **the sources below**: every story the summary was built from, newest first, in a Tech column and a
  Politics column. Click a story to read it at the outlet; Hacker News stories also link their discussion.

Stories come from the outlets' RSS feeds: Hacker News, Ars Technica, The Verge, TechCrunch and Wired for
tech; CBC, The Globe and Mail, National Post, NPR, Politico, Fox News and BBC World for politics. The
summary is written by Claude through the `claude` CLI, so it uses your Claude subscription and needs no
API key. Claude gets only the headlines and blurbs, with no tools. If Claude can't be reached, the page
still comes, without the summary.

The page uses the colours of the current Caelestia scheme.

## Usage

```
news-brief              fetch the news, write the summary and open the page now
news-brief --open       open the latest edition again
news-brief --build      build an edition without opening it (prints the path)
news-brief --scheduled  what the timer runs
```

## How the schedule works

`~/.config/systemd/user/news-brief.timer` fires at 7:28 and 20:28. The run fetches the feeds (~1 s),
writes the summary (~10 s), then waits for the half hour and sends one notification. Clicking the
notification, or its "Read the news" button, opens the page. It also stays in the notification centre.

- **Asleep or off at that time**: it runs when the laptop wakes (`Persistent=true`), so an evening
  you missed shows up when you next open the lid. If two runs land within 3 hours (a missed 20:30 caught
  up at 7:00), only the first one notifies.
- **Locked**: the notification waits until you unlock. If that's more than an hour later, the news is
  fetched again first.
- **Offline**: it waits up to 5 minutes for the network, then gives up quietly.

Each edition covers what happened since the previous one, at least 10 and at most 36 hours. Outlets
that are quiet (weekends) still show their 2 newest stories.

To change the times, edit `OnCalendar=` in the timer, keeping it 2 minutes before the time you want.
Then run `systemctl --user daemon-reload`.

## Files

- `~/.config/news-brief/config.toml`: feeds, model, story counts, who the summary is for
  (see `config.example.toml`)
- `~/.local/share/news-brief/editions/`: the pages, the last 30 kept; `latest.html` points at the newest
- `~/.cache/news-brief/log`: what each run did; `state.json`: when the last edition was built and delivered

## Install

```
ln -s ~/.local/src/news-brief/news-brief ~/.local/bin/news-brief
cp systemd/news-brief.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now news-brief.timer
```

Clicking a Caelestia notification's body only runs its action if `"actionOnClick": true` is set under
`notifs` in `~/.config/caelestia/shell.json`. Without it, use the "Read the news" button.

Needs: python 3.11+, `claude` (Claude Code, logged in), `notify-send`, `xdg-open`.

## Tests

```
python3 -m unittest discover -s tests
```
