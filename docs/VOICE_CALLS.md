# نظام الاتصال الصوتي — design

> ## ⚠ SUPERSEDED IN ITS CENTRAL CLAIM — read this box first
>
> This document argued that the association needed a **LiveKit account** and
> a **Supabase Edge Function**, and that a group call was impossible without
> an SFU. Both stages were then built without either, because the association
> set a constraint this document had not been written under: **nothing may be
> asked of it except running a SQL file.**
>
> What is actually shipped, in `PATCH_20260821d` and `PATCH_20260821e`:
>
> | this document says | what was built |
> |---|---|
> | LiveKit Cloud (SFU + TURN) | **peer-to-peer mesh**, no account |
> | an Edge Function to mint tokens | **nothing** — there is no token |
> | a group call needs an SFU | **a capped mesh**, `call_max_participants` = 6 |
> | ICE servers configured per environment | `association_settings.ice_servers`, editable by SQL |
>
> ⚠ **AND THE SFU CLAIM WAS WRONG ABOUT VOICE, not merely inconvenient.**
> Opus is ≈32 kbps, so five in a mesh is 128 kbps up — a phone carries that.
> Video is roughly twenty times those figures, and that is where the argument
> for an SFU actually comes from. This document did not separate the two.
>
> ⚠ **What remains TRUE below** and is worth keeping: why Realtime cannot
> carry the signalling (`x-device-id` is a request header and a websocket
> carries none), why TURN matters on Libyan carrier NAT, and why a call log
> does not belong in the audit trail. The LiveKit design is kept as the
> **upgrade path**: if the mesh breaks up at six, this is the shape to move
> to — and the one thing it would then need from the association is the
> account named at the end.

---
## 1. What a voice call actually needs

Three separate problems, and they are usually confused with each other:

| | The problem | Who solves it |
|---|---|---|
| **Media** | carrying the audio itself | WebRTC, on both handsets |
| **Signalling** | «I want to call you» + the SDP/ICE handshake | the app, over something both sides can reach |
| **NAT traversal** | two phones on mobile data cannot address each other | STUN, and — here — **TURN** |

An app can be written that solves the first and forgets the third. It works
perfectly on the developer's wifi and fails on the road, which is the worst
possible way to find out.

---

## 2. Why the obvious answers do not work in THIS app

### ⚠ Supabase Realtime for signalling fails for exactly the people it is for

The reflex is a Realtime channel: both sides subscribe, offers and answers fly
across, done.

`my_adeel_id()` reads the **`x-device-id` REQUEST HEADER**, and a websocket
carries no headers. So a Realtime subscription evaluated for a portal member
matches no policy and delivers him nothing. **Staff would be able to call each
other while no عديل could be reached at all** — and it would look perfect to
anyone testing with a staff account.

This is not a new discovery. It is the same reason `features/chat/` polls
instead of subscribing, and it is written up in
`chat/presentation/providers.dart`. Any call design that reaches for Realtime is
repeating a mistake this codebase already paid for.

**So signalling goes the same way the chat goes: a table, and the poll that is
already running.**

### ⚠ Peer-to-peer mesh cannot do a group call on these networks

For two people, WebRTC peer-to-peer is right and costs nothing.

For eight, a mesh means **every phone encodes and uploads seven separate
streams**. Opus at 32 kbps each is ~224 kbps of upload plus seven encoders
running at once. On a Libyan mobile connection that is not a call, it is a
stutter — and the battery drain is severe. Mesh is fine at two, tolerable at
three, and dead at five.

A group call needs an **SFU**: every phone sends ONE stream up and receives a
mixed set down. An SFU is a media server. **There is no version of this that
runs only on the handsets.**

### ⚠ Without TURN, a large share of calls simply never connect

Libyan carriers put subscribers behind carrier-grade NAT. Two phones both on
mobile data usually cannot open a direct path to each other whatever STUN says.
TURN is a relay that both can reach, and it carries the audio — which is why
TURN costs bandwidth and is never free at scale.

Public STUN (Google's) is free and helps on wifi. **It is not a substitute.**

---

## 3. The architecture

```
   handset A                                            handset B
      │                                                     │
      │ 1. start_call()  ──────►  Supabase (postgres)  ◄──── polls, sees the call
      │                              calls table
      │                                 │
      │ 2. POST /functions/v1/call-token
      │    (user's own JWT + x-device-id)
      │                                 │
      │                            Edge Function
      │                     ├─ asks POSTGRES «may he be in this room?»
      │                     └─ signs a LiveKit token with the secret
      │                                 │
      │ 3. connect(token) ────────►  LiveKit Cloud  ◄──────── connect(token)
      │                            SFU + TURN
      └──────────────────── audio ──────┴──────── audio ─────┘
```

### The pieces, and why each is that piece

**LiveKit Cloud** — solves the SFU and the TURN in one service, has a
maintained Flutter SDK (`livekit_client`, which resolves against this project's
constraints — checked), and its free tier is far larger than eight members will
ever use. Self-hosting the same thing (LiveKit or Janus or mediasoup) means a
server the association has to keep alive, which is the one thing this project
has deliberately never had.

**A Supabase Edge Function to mint the token** — and this is the part that
matters most.

> ⚠ **THE LIVEKIT API SECRET MUST NEVER SHIP IN THE APK.** The Supabase anon key
> is public *by design*; a LiveKit secret is the opposite. Anyone who extracted
> it from the APK — and the APK is handed to eight people and the repository is
> public — could mint a token for any room and **sit silently inside the
> association's private call**. There is no RLS in front of LiveKit; the token
> IS the authorisation.
>
> An Edge Function is server-side code inside the Supabase project we already
> have. The secret lives in Supabase secrets and never leaves it.

**The room name IS the chat room.** `hall` for المجلس, `thread-<adeelId>` for a
private thread.

> ⚠ **THE EDGE FUNCTION MUST NOT DECIDE PERMISSION ITSELF.** It should call the
> same database function the chat already goes through, with the caller's own
> JWT and `x-device-id` forwarded. Then «who may join this call» is literally
> «who may read this room» — a rule that is already written, already tested in
> `supabase/tests/46_chat.sql`, and cannot drift away from the chat's rule
> because it is not a second copy of it.
>
> A permission check written in TypeScript inside the function would be a second
> implementation of `read_chat`, free to disagree with the one that decides
> everything else.

---

## 4. The schema

One table and two RPCs, in the shape everything else in this app takes.

```sql
create table public.calls (
  id            bigint generated always as identity primary key,
  thread_adeel_id bigint references public.adeels(id) on delete cascade,
  room          text not null,          -- 'hall' | 'thread-<id>', GENERATED, not client-set
  started_by    uuid not null references auth.users(id),
  starter_name  text not null,          -- SNAPSHOT, for the same reason chat_messages snapshots it
  started_at    timestamptz not null default now(),
  ended_at      timestamptz,
  status        text not null default 'جارية'   -- جارية | انتهت | فائتة
);
```

- **`thread_adeel_id` NULL is المجلس**, an id is that man's thread — the same
  discriminator `chat_messages` uses, so «which room» is one concept in this
  schema rather than two.
- **`starter_name` is snapshot onto the row**, for the reason
  `chat_messages.author_name` is: `v_calls` is SECURITY INVOKER and an عديل's
  RLS on `profiles` shows him his own row only, so a join would give him his own
  name beside every call and NULL beside everyone else's.
- **`started_at` is stamped by a BEFORE INSERT trigger**, never accepted from
  the client — the rule `disb_stamp_time()` and `pay_stamp_time()` already
  enforce, for the same reason.

**RLS**: `read_calls` is `read_chat`'s policy, verbatim in structure — staff by
`my_role()`, a member by `my_adeel_id()`, through `in_association()`. If a man
may not read the room he may not see that it is ringing.

**RPCs**: `start_call(p_thread_adeel_id)` and `end_call(p_id)`. Writes go
through `SECURITY DEFINER` functions like every other write in this app, and
both must be added to the allow-list in
`20260811091200_function_lockdown.sql` — a function created without being listed
there is unreachable, and the migration asserts the list is EXACT.

⚠ **`calls` belongs in `purge_all_data` and NOT in `purge_financial_data`** —
and that is forced rather than chosen: it references `adeels`, and Postgres
refuses to TRUNCATE a table a survivor points at. Exactly the constraint
`chat_messages` is under.

---

## 5. Ringing, and the limit that does not go away

The chat already polls every second while a room is live and four seconds
otherwise. **The call notice rides that same poll** — `calls` where
`status = 'جارية'` and the room is one this account may read. No new clock, no
new timer, and it behaves identically for a staff account and a portal one.

The ringtone reuses `ChatChime`'s shape: an asset, played on a rise, silent
while you are already on the call screen.

> ⚠ **IT STILL ONLY RINGS WHILE THE APP IS OPEN.** This is the same wall the
> message chime hit and it is not a Dart problem: waking a closed app needs a
> push service (Firebase Cloud Messaging), a project, a server key, and
> something server-side that fires on the insert. The Edge Function this design
> already introduces COULD be that sender — so if the association later wants a
> phone in a pocket to ring, the piece that makes it possible is being built
> here anyway. It is a separate stage and should be named as one, not implied.

---

## 6. In Dart

```
features/call/
  data/call_repository.dart      read via v_calls, write via the two RPCs
  domain/models.dart
  presentation/
    providers.dart               the active-call poll, riding the chat's
    call_screen.dart             the in-call screen
    incoming_call_sheet.dart     «فلان يتصل» — accept / decline
    call_button.dart             the handset icon in the chat app bar
```

- `livekit_client` for the media, `permission_handler` for the microphone.
- The button lives in the **chat app bar**, one per room — so «اتصال» is where
  the conversation already is, which is what «من داخل المحادثات» means.
- ⚠ **The microphone permission must be asked at the moment of the call**, not
  at first launch. A permission dialog on a screen that is not asking for
  anything is the one people refuse.
- ⚠ `refreshAll` must list every new provider — `test/refresh_coverage_test.dart`
  fails the build otherwise, and a call provider serving a stale answer would
  show a call that ended twenty minutes ago as still ringing.

---

## 7. Cost, honestly

| | |
|---|---|
| LiveKit Cloud free tier | far beyond eight members; voice-only is a fraction of what video costs |
| Data on the member's phone | Opus voice ≈ **0.5 MB per minute** each way |
| Battery | a call is a call — comparable to WhatsApp |
| Supabase | one row per call, and the poll that is already running |

If the free tier is ever exceeded, the fallback is not «pay» but **restrict
group calls to المجلس and keep one-to-one peer-to-peer**, which uses no SFU at
all.

---

## 8. Staging

**Stage 1 — one-to-one, in a private thread.** Proves the entire chain: token
minting, permission, connection, TURN on real Libyan mobile data. If TURN is
going to fail, it fails here, on the simplest case, where it can be diagnosed.

**Stage 2 — the group call in المجلس.** Same chain; only the room changes. The
UI gains a participant list and a who-is-speaking indicator.

**Stage 3 — ringing while the app is closed.** Push notifications. A separate
project, named separately, and worth doing only after stages 1 and 2 are in real
use.

⚠ **Stage 1 is not a prototype to be thrown away.** It is the same code path the
group call uses, with one participant on the other side instead of six.

---

## What is needed from the association

**One thing: a LiveKit Cloud account.** Free, and it takes a few minutes at
`livekit.io` — it produces an **API key** and an **API secret**.

- The **secret** goes into Supabase secrets, from the Supabase dashboard. It
  never appears in this repository, never in the APK, and never in a message.
- The **key** and the project URL are not secret and may be committed.

Once that exists, stage 1 is buildable end to end.

---

## What this design deliberately does NOT do

- **No video.** The association asked for صوتي. Video is the same pipe with a
  different track, and can be added later without changing anything above — but
  it multiplies the bandwidth by roughly twenty and would be the thing that
  breaks the free tier.
- **No call recording.** It would be a new class of data — the most private this
  system would ever hold — and nobody asked for it.
- **No call history as a ledger.** The `calls` table records that a call
  happened so the room can show «مكالمة فائتة». It is not money and it does not
  belong in the audit trail; rule 12 exists so a FIGURE can be reconstructed,
  and a log of conversations would bury it.
