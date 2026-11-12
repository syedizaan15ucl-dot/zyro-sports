# ZYRO on GitHub Pages: setup

Files to upload to your GitHub Pages repository (same folder, nothing else needed):
`index.html`, `admin.html`, `config.js`.

The `supabase` folder and `dev` folder are NOT uploaded. `supabase/setup.sql` is used once in Step 2.

How it works: the website (GitHub Pages) talks to a free Supabase project that stores products,
orders and photos. The admin password is a real Supabase account; it is never in any file.
The only thing in `config.js` is the public project address and the public "anon" key. That key is
designed to be public. The database rules in `setup.sql` are what protect your data:
- anyone can read the catalogue, nobody except you can change it;
- customers can only place orders through a function that prices the order itself;
- only your admin account can read orders, change status, edit products and upload photos.

## Step 1. Create the Supabase project
1. Go to supabase.com and sign up (free).
2. New project. Name: `zyro`. Choose a database password and save it somewhere private. Do not put it in any file.
3. Region: pick the closest one to Pakistan. Wait until the project says it is ready.

## Step 2. Create the tables and rules
1. In Supabase, open **SQL Editor** > **New query**.
2. Open `supabase/setup.sql`, copy everything, paste it, press **Run**. It should say "Success".
(The file makes khawajaizaanahmad@gmail.com the administrator. Change that email near the top of the file if your admin account uses another one.)

## Step 3. Create your admin login
1. **Authentication** > **Users** > **Add user** > **Create new user**.
2. Email: your admin email. Password: a long password only you know. Tick "Auto Confirm User". Create.
3. **Authentication** > **Sign In / Providers** (or Settings): turn OFF "Allow new users to sign up".

## Step 4. Connect the website
1. In Supabase open **Project Settings** > **API** (or "API Keys").
2. Copy the **Project URL** into `supabaseUrl` in `config.js`.
3. Copy the key named **anon public** into `anonKey`. Do NOT copy the `service_role` key.

## Step 5. Put the files on GitHub Pages
Upload `index.html`, `admin.html` and `config.js` to your repository, replacing the old ones.
Wait a minute, then open `https://YOUR-NAME.github.io/YOUR-REPO/`.
The admin portal is at `https://YOUR-NAME.github.io/YOUR-REPO/admin.html`.

## Step 6. First sign in (important)
Open `admin.html`, sign in with the admin email and password from Step 3.
The first sign in saves all existing ZYRO products, clubs and photos to Supabase (about a minute).
Customers can only order after this step.

## Step 7. Get order emails
1. Go to formspree.io, sign up with your Gmail, create a form.
2. Copy the form link (looks like `https://formspree.io/f/abcdwxyz`) into `notifyUrl` in `config.js` and upload the file again.
3. Confirm the first email Formspree sends you.
Each order, message and custom design then emails you. Orders always appear in the Admin Portal too.

Stronger option (optional): `supabase/optional-email-function.ts` is a Supabase Edge Function that sends
the email from the server using a key stored in Supabase secrets (never in a file). Only use it if you want that.

## Step 8. Test
Place a test order on the website. Check: the confirmation and reference number, your email,
and the Orders tab in the Admin Portal. Change its status to Confirmed, Shipped or Delivered.

## Notes
- A free Supabase project pauses after a week without use. Open the dashboard and press Restore if that happens.
- Orders you receive are only readable after admin login. Sign out on shared computers.
- If you ever leak the `service_role` key, regenerate it in Supabase immediately.
