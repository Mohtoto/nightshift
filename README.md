# NIGHTSHIFT

NIGHTSHIFT is a native iOS app for local car culture. The map is the front door: a dark city, neon meet markers, and a sheet for the event under your finger. Behind it are garages, a chronological feed, and driver profiles.

The app is built with SwiftUI, MapKit, and Core Location. Accounts, photos, meets, and social actions go through one repository interface. With an empty `SupabaseConfig.plist` the app stores that data on the iPhone so you can run it immediately. When you add a Supabase URL and anon key, the same screens talk to Postgres, Auth, Storage, and Realtime.

## Connect Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. In the SQL editor, run `supabase/migrations/20261123000000_init.sql`.
3. In Authentication, turn off “Confirm email” while you are developing, or use the confirmation message in the app.
4. Enable Sign in with Apple and add the bundle id `com.nightshift.app`.
5. Copy `Nightshift/SupabaseConfig.example.plist` over `Nightshift/SupabaseConfig.plist` if you have not already, then set:

```xml
<key>url</key>
<string>https://YOUR_PROJECT.supabase.co</string>
<key>anonKey</key>
<string>YOUR_ANON_KEY</string>
```

Use the anon key only. Do not put the service role key in the app.

6. Open `Nightshift.xcodeproj` and run the Nightshift scheme on an iPhone simulator or device. The first build resolves the Supabase Swift package.

Settings shows whether the signed-in session is “On this iPhone” or “Supabase”.

### Authorization

Row Level Security is on for every table. People can change only their own profile, cars, posts, comments, and meets. Private meets are unlisted: they are readable by id (a share link) and by the host and attendees, and they stay out of discovery. Blocks hide posts, garages, and meets in both directions. Reports are visible only to the person who filed them.

Hiding reported content is a moderator action, not something any member can do:

```sql
update public.posts set hidden = true where id = '<post uuid>';
```

Run that with the service role in the SQL editor. The same `hidden` column exists on `comments` and `vehicle_comments`. Account deletion calls `public.delete_own_account()`, which removes the auth user and cascades their rows.

Live meet changes use the `supabase_realtime` publication on `events`.

### Storage

The migration creates public buckets `avatars`, `covers`, `vehicle-photos`, `event-covers`, and `post-images`. Object paths start with the user id, so people can only write inside their own folder. Image URLs are unguessable. The app uploads a full JPEG and a `_thumb` sibling.

## On-device mode

Leave the URL and anon key empty. Sign-up, garage photos, meets, joins, posts, likes, comments, follows, blocks, reports, and account deletion all persist in Application Support. Password reset on device sets a new password directly because there is no mail server. Location is still requested only when you open the map or nearby meets, and a declined permission leaves city search working.

`-UITesting` wipes a separate on-device store and shows “Use test photo” / “Use test location” controls. `-SeedDemo` fills a sample driver, car, meet, and post through the same repository API.

## Project layout

- `Nightshift/Design` — color, type, and shared controls
- `Nightshift/Features` — map, meets, garage, feed, profile, auth
- `Nightshift/Services` — repository, local store, Supabase client, images, location
- `supabase/migrations` — schema, policies, storage, triggers

The tab bar is the system tab bar, styled dark with a purple selection, so it can move beside the content on iPhone Duo. Map controls read safe area and reserved regions so they stay off the fold and cameras.

## Checks

```bash
xcodegen generate
xcodebuild -scheme Nightshift -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Use whichever iPhone simulator is installed if that name differs.
