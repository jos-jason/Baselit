# Syncing Baselit through PocketBase

Every Baselit app (iPhone, iPad, Mac, Android, Linux) can keep the same
inventory, photos included, by syncing with your own
[PocketBase](https://pocketbase.io) server (version 0.23 or newer).

## Set up the server once

1. Copy `pb_migrations/1762905600_baselit_records.js` into your server's
   `pb_migrations` folder (next to `pb_data`) and restart PocketBase. It creates
   one collection, `baselit_records`, whose rows only their owner can see.
2. In the PocketBase dashboard, open the `users` collection and add a user with
   an email and password. That's the account every Baselit app signs in with.

## Sign in on each device

In Baselit, open Settings (the gear on the Search tab), then **PocketBase Sync**,
and enter the server address (like `https://pb.example.com`), the email, and
the password. Changes sync a few seconds after you make them, every minute
while the app is open, and when you come back to it.

Sign in on the device with your full inventory first. When a second device that
already has data signs in, it asks whether to **Use Server's** inventory
(replace what's on that device) or **Merge** both. Pick Use Server's if that
device was set up from a backup of the same inventory, or you'll get duplicates.

Servers on your home network work over plain `http://` (for example
`http://192.168.1.20:8090`); anywhere else, use `https://`.

## How it works

Each house, location, container, item, photo, and home location is one row,
keyed by the record's permanent ID, holding the same JSON as a Baselit backup.
Photos are stored as protected PocketBase files. Deleting something marks its
row `deleted` so other devices remove it too. If two devices change the same
record before syncing, the most recent change wins.
