# Contributing to Konevo

Konevo is source-available software maintained by Filip Paučo. Product feedback,
bug reports, documentation corrections, and carefully scoped feature ideas are
welcome.

## Before opening an issue

- Search existing issues first.
- Describe the current behavior, expected behavior, and safe reproduction steps.
- Include version or commit, browser/operating system where relevant, and logs
  with credentials, personal data, and tokens removed.
- Do not report security vulnerabilities publicly; use [SECURITY.md](SECURITY.md).

## Pull requests

Anyone may fork Konevo and open a pull request. Product improvements, bug
fixes, documentation updates, and tests are welcome.

- Do not assume a pull request will be reviewed or merged.
- Do not copy code or assets that you cannot license for this project.
- Keep changes focused, tested, and documented.
- For a substantial contribution that is accepted, the maintainer may request a
  separate written contributor agreement before merging so Konevo can continue
  to offer separate commercial permissions.

Opening an issue does not transfer ownership of your idea or grant rights to
Konevo source code.

## Becoming a regular contributor or maintainer

If you would like to contribute to Konevo regularly, say so in a pull request,
issue, or email. Regular involvement is welcome; contributors who consistently
make constructive, high-quality contributions can be invited to take on more
responsibility over time.

That can grow from contributing through forks, to Write access and code review,
to a defined core-maintainer or product-maintainer role. These roles can include
shared product decisions and authority over an agreed area of the application;
they are not merely advisory roles. Legal ownership and GitHub administrator
access are separate decisions.

Read [GOVERNANCE.md](GOVERNANCE.md) for the current roles, decision-making
process, and path to greater responsibility.

## Contribution workflow

Fork the repository first if you do not have Write access. Contributors with
Write access may create their branch directly in this repository.

1. Sync your fork with `main`, then create a short-lived branch:

   ```shell
   git switch main
   git pull --ff-only
   git switch -c feat/short-description
   ```

   Use `feat/...` for new functionality, `fix/...` for bug fixes, and
   `docs/...` for documentation-only work. Never commit directly to `main`.

2. Prepare the application locally. Copy `.env.example` to `.env`, set the
   required local values, then run:

   ```shell
   mix setup
   lefthook install
   ```

   Install Lefthook first if needed:

   ```shell
   # Windows (Scoop)
   scoop install lefthook

   # macOS (Homebrew)
   brew install lefthook

   # Debian/Ubuntu Linux
   curl -1sLf 'https://dl.cloudsmith.io/public/evilmartians/lefthook/setup.deb.sh' | sudo -E bash
   sudo apt install lefthook
   ```

3. Make focused changes and include tests. Before committing, run:

   ```shell
   mix precommit
   ```

   Never commit `.env`, credentials, real customer data, uploads, or database
   backups.

4. Use a Conventional Commit message:

   ```text
   feat: add contact timeline filter
   fix: preserve calendar date when changing view
   docs: clarify local setup
   ```

5. Push your branch to your fork (or directly to the repository if you have
   Write access), then open a pull request against `main`. Explain the change,
   testing performed, and any deployment or migration considerations.

6. The pull request must pass CI and receive the required CODEOWNERS review
   before it can merge. Do not try to bypass checks or force-push `main`.

   Merging an application change to `main` creates a release and may deploy
   production automatically. Documentation-only changes do not create a
   release or deployment.

## Contact

For collaboration, product feedback, licensing, or contribution discussion, email
[filip.pauco08@gmail.com](mailto:filip.pauco08@gmail.com).

For permissions outside the published license, read
[COMMERCIAL-LICENSING.md](COMMERCIAL-LICENSING.md).
