// ZYRO store settings. Everything in this file is PUBLIC (it is downloaded by every visitor).
// Only put the Supabase project URL and the "anon / public" key here.
// NEVER put the service_role key, a database password, or an email API key in this file.
window.ZYRO_CONFIG = {
  supabaseUrl: "",   // Step 4: for example https://abcdxyz.supabase.co
  anonKey: "",       // Step 4: the long key labelled "anon public"
  notifyUrl: "",     // Step 7 (order emails): your Formspree link, for example https://formspree.io/f/abcdwxyz
  notifyKey: "",     // only needed for Web3Forms (leave empty for Formspree)
  adminEmail: ""     // optional: pre-fills the email box on the admin login page
};
