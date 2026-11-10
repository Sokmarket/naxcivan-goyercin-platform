# V3 Live Social Integration — Test Checklist

Use a dedicated test Supabase project and three test accounts (A, B, C).

## Authentication and profile
- [ ] A and B can register with distinct emails.
- [ ] Email confirmation behaves according to Supabase Auth settings.
- [ ] A and B receive separate `profiles` rows.
- [ ] A can update A's profile; B cannot update A's profile.
- [ ] Duplicate usernames are rejected by the unique constraint.
- [ ] Signing out clears the active private profile view.

## Posts and media
- [ ] A creates a public post; B can read it from a separate browser/session.
- [ ] A uploads an allowed image/video into `public-media`.
- [ ] A cannot upload into B's storage folder.
- [ ] A cannot create a post with another user's `author_id`.
- [ ] New post events refresh the feed for connected clients.
- [ ] A visitor without an account can read only public posts.

## Messaging
- [ ] A starts a conversation with B by username.
- [ ] A and B can read and send messages.
- [ ] C cannot select the conversation, members or messages.
- [ ] A cannot insert a message with B's `sender_id`.
- [ ] Realtime message events appear in the open conversation.
- [ ] Message identity fields remain immutable after insert.
- [ ] No message body or attachment is written to public-media.

## Release
- [ ] Foundation migration is applied before Realtime migration.
- [ ] All RLS acceptance tests pass.
- [ ] Browser console has no uncaught integration errors.
- [ ] Android Chrome, Samsung Internet, Firefox and desktop browser smoke tests pass.
- [ ] No service_role / sb_secret key is present in the repository.
