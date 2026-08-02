<sso>
Sign in with your Cloudron account. Every Cloudron user you allow in the app's Access
Control list shares ONE workspace: the same saved connections, the same stored credentials.
Grant access accordingly.
</sso>

<nosso>
This install runs without Cloudron single sign-on. A local administrator login was generated
on first run:

* Username: `admin`
* Password: stored in `/app/data/.secrets/admin-credentials` (read it with the dashboard
  File Manager, or `cat` it from the Web Terminal)

Change or extend logins by setting `LOGIN_PASSWORD_<name>` values in
`/app/data/env` and restarting the app.
</nosso>

First useful step: open Connections, add your first database using the credentials shown in
another app's Cloudron dashboard (Addons section), and keep it read-only if you only need to
look. Backups of this app include the whole workspace, saved connections and the encryption
key that protects stored passwords.
