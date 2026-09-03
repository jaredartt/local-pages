# Local Pages · Liahona

Production tracker for the Liahona Local Pages editions — months, editions,
phases, steps, progress sliders, dates, comments and a change log, shared live
between everyone who is signed in.

## What's here

| file | what it is |
|---|---|
| `index.html` | the whole app — one file, no build step |
| `manifest.json`, `icon*.png`, `favicon.svg` | so it installs to the dock as an app |
| `schema.sql` | the database: tables, permissions, live updates, starting contents |

## Putting it online

1. Create a repository on GitHub called `local-pages`, **Public**.
2. **Add file → Upload files**, drag everything in this folder in, **Commit**.
3. **Settings → Pages → Source: Deploy from a branch → `main` / `(root)` → Save.**
4. A minute later it's live at `https://<your-username>.github.io/local-pages/`.

To update it later, upload the changed file the same way — it redeploys itself.

## Installing it as a Mac app

Open the site in Chrome → the ⋮ menu → **Cast, save and share → Install page as
app**. It gets a dock icon and its own window, with no browser chrome.

## The database

Supabase project `local-pages`. `index.html` holds the project URL and the
publishable key — both are meant to be public. Nothing can be read or written
without signing in, and only allow-listed accounts can change anything; that is
enforced by row-level security in Postgres, not by the page.

To approve a colleague, add their address to `allowed_emails` (Table Editor)
before they sign up, or tick `is_admin` on their row in `profiles` afterwards.

## Rules worth knowing

- Signed in + approved → can change anything, including the structure.
- Signed in, not approved → read only.
- Not signed in → nothing at all.
- Nobody can promote themselves; that's blocked by a database trigger.
- The first account ever created is always an admin, so you can't lock yourself out.
