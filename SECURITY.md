# Security Policy

## Please read first: use with caution

**Git Commit Watcher is provided "as is", without warranty of any kind, and you use it entirely at your own
risk.** It runs `git` and `ssh` on your computer, can use your SSH private keys and HTTPS access tokens, and
shows content of your repositories on your screen.

**The creator is not responsible for how you use your keys** — SSH keys, passphrases, HTTPS token files —
**or for anything that happens to your accounts, repositories, servers or data** while you use this software.
You are responsible for the keys and tokens you give it and for the repositories you point it at. This notice
supplements the no-warranty terms of the [GNU General Public License v3.0](LICENSE) (sections 15 and 16).

If you are not comfortable with the points below, do not use SSH keys or tokens with this widget.

## Supported versions

Only the latest release receives fixes.

| Version | Supported |
| --- | --- |
| 1.0 (latest) | yes |

## Reporting a vulnerability

Please report security problems **privately**, not in a public issue:

- Use GitHub's **"Report a vulnerability"** button on the
  [Security tab](https://github.com/vit-lab/git-commit-watcher-plasmoid/security/advisories/new) of the
  repository, or
- write to **vitalyle@protonmail.com** with "Git Commit Watcher security" in the subject.

Please include the version (`grep Version ~/.local/share/plasma/plasmoids/local.gitcommitwatcher/metadata.json`),
what you did, what you expected and what happened. **Never send private keys, passphrases or tokens.**
This is a hobby project: I answer on a best-effort basis and cannot promise response times or fixes.

## What the widget does (and does not do)

- It only reads from repositories: `git fetch`, `git log`, `git show`, `git rev-parse` and `git cat-file`
  (plus `git init --bare` for its own cache folder). It never commits, pushes, merges, checks out or changes your working tree, branches or index.
- `git fetch` in a **local clone** updates the clone's remote-tracking branches and object database inside
  `.git`, exactly as if you ran `git fetch` yourself.
- For **remote URLs** it keeps its own small shallow bare repository in `~/.cache/gitcommitwatcher/`.
- It runs shell helper scripts through Plasma's `executable` data engine. Values such as paths, branch names
  and commit ids are single-quoted or validated, and commit ids are checked to be hexadecimal.
- It opens web links and files with your default applications (see *Open File* below).
- It does not send any data anywhere except to the git remotes you configured and to the browser when you
  open a link. There is no telemetry.

## Risks you take on when you use SSH keys

- **Use a dedicated, read-only key.** Prefer a separate key (for example a repository *deploy key* with read
  access only) instead of your main key that can push everywhere. If something goes wrong, the damage is
  limited to what that key can do.
- **Protect the key with a passphrase.** The widget supports this: it asks for the passphrase in a KDE dialog
  and passes it directly to `ssh-add`; the passphrase is never stored by the widget, never written to its
  settings and never put on a command line.
- **A key loaded into the widget's private `ssh-agent` can be used by any program running as your user**
  (that is how every `ssh-agent` works) until you press **Lock**, the optional lifetime expires, or you log
  out. The agent socket is `$XDG_RUNTIME_DIR/gcw-agent-<uid>.sock`.
- **Host keys:** SSH connections use `StrictHostKeyChecking=accept-new`: the host key of a server you have
  never connected to is accepted automatically the first time (and checked on later connections). If you need
  stricter behavior, connect once yourself (`ssh -T git@host`) and verify the fingerprint before adding the
  repository.
- The widget stores only the **path** of the key file, not the key. Keep key files at `chmod 600`.
- Anyone who can read your private key (and its passphrase) can act as you. Do not share screenshots, logs or
  settings exports without checking them first.

## Risks you take on when you use HTTPS token files

- Use a **fine-grained or read-only token** with the smallest scope and, if possible, an expiry date.
- Keep the token file readable only by you (`chmod 600`). The widget reads the first line of the file.
- The token is sent as an HTTP `Authorization` header to the host of the repository URL. Use `https://` URLs
  only; over plain `http://` the token would be sent unencrypted. Do not use a token for a host you do not
  trust.
- The token is passed to `git` through environment variables (so it does not appear in the process list
  arguments), but other processes of your user may be able to read the environment of a running process.
- The widget stores only the **path** of the token file, not the token.

## Other things to be careful about

- **Only add repositories you trust.** The widget runs `git` inside the local clones you add, so the
  repository's own git configuration applies, just as when you run `git` there yourself. A hostile
  repository can contain configuration that makes git run programs.
- **Open File** opens a file from a commit with your default application. Files from repositories can be
  malicious (documents with macros, scripts, installers, …). Open only files you trust. The copy is saved
  without execute permission (read-only) in `~/.cache/gitcommitwatcher/files/` and removed after a week.
- **Private data on disk and on screen.** The cache folder `~/.cache/gitcommitwatcher/` contains copies of
  commits from private repositories you watch by URL (and files opened with *Open File*). Notifications and the
  popup show author names and commit messages — take care when you share your screen. Delete the cache folder to
  remove the data.
- **Settings.** The repository list, the paths of key and token files and the last seen commits are stored in
  your Plasma configuration (`~/.config/plasma-org.kde.plasma.desktop-appletsrc`). They are not encrypted.
- **Commit messages and file names are untrusted text.** The widget escapes them for display and notifications,
  but treat their content (links, instructions) with the same care as anywhere else.

## Recommended setup

1. Create a **read-only deploy key or token** for each repository you want to watch.
2. Protect SSH keys with a **passphrase** and use a short unlock lifetime in the widget settings.
3. Keep key and token files at `chmod 600`.
4. Watch only repositories you trust.
5. Update to the latest release and read the [CHANGELOG](CHANGELOG.md).

## No warranty

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHOR BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
YOU USE THE SOFTWARE ENTIRELY AT YOUR OWN RISK.
