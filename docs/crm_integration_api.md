# CRM Integration API

A read-only JSON API that exposes Chatwoot conversations in a lead-shaped payload for
external CRM systems (e.g. `crm.eplcapps.id`). It includes first-touch attribution for
leads that arrived via a Meta "Click to WhatsApp" (CTWA) ad.

All endpoints live under:

```
/api/v1/accounts/:account_id/crm/...
```

`:account_id` is your Chatwoot account ID (visible in the dashboard URL).

---

## Credentials

You need two values from Chatwoot, obtained once when setting up the integration:

| Value | Where to get it | Where it's used |
|---|---|---|
| `account_id` | The number in the dashboard URL, e.g. `.../app/accounts/**1**/dashboard` | URL path: `/api/v1/accounts/1/crm/...` |
| access token | A dedicated Chatwoot admin user's **Profile Settings → Access Token** | HTTP header: `api_access_token` |

**What's fixed vs. what's your choice:** the HTTP header name `api_access_token` and the
`account_id` URL segment are dictated by Chatwoot's server code and cannot be renamed —
every request must use exactly those. How you *store* the two values inside the CRM
codebase (env var names, config keys, secrets manager entry names, etc.) is entirely up to
your own conventions; Chatwoot has no opinion on that. If you want a suggested convention
for your own `.env`, something like this works fine and isn't required to match anything:

```
CHATWOOT_BASE_URL=https://<your-chatwoot-domain>
CHATWOOT_ACCOUNT_ID=1
CHATWOOT_API_ACCESS_TOKEN=<token from Profile Settings>
```

Then when your backend actually makes the request, it must look like this regardless of
what you named the variables above:

```
GET {CHATWOOT_BASE_URL}/api/v1/accounts/{CHATWOOT_ACCOUNT_ID}/crm/conversations
api_access_token: {CHATWOOT_API_ACCESS_TOKEN}
```

- Missing or invalid token → `401 Unauthorized`.
- An **administrator** token sees every conversation in the account.
- A non-administrator (agent) token only sees conversations in inboxes that user belongs
  to. Use an administrator token for the CRM integration so it has full account visibility.
- The token's owning user must belong to the account in the URL (`:account_id`) and that
  account must be active, or you'll get `401 Unauthorized` / `You are not authorized to
  access this account`.

### Architecture: call this from your backend, not the browser

**Do not call this API directly from CRM frontend JavaScript.** Two reasons:

1. **Security** — `api_access_token` is a bearer credential. Anyone who opens browser dev
   tools could read it out of a network request and query your Chatwoot data directly.
2. **CORS** — in Chatwoot's production environment, `/api/*` is only CORS-enabled if the
   Chatwoot server has `ENABLE_API_CORS=true` set. Without it, direct browser requests
   from `crm.eplcapps.id` will fail with a CORS error even with a valid token. (CORS is
   wide open in Chatwoot's `development` environment only — don't rely on dev behavior
   matching prod.)

The correct shape: your **CRM backend** holds the access token and calls this API
server-to-server (no CORS involved), then serves the result to your CRM frontend however
you like. If you'd rather enable direct-from-browser calls anyway, ask whoever manages the
Chatwoot deployment to set `ENABLE_API_CORS=true` — but the token-exposure problem remains,
so server-to-server is still the better default.

---

## Meta ad attribution — what's available

Chatwoot captures Meta's Click-to-WhatsApp (CTWA) referral payload on the first inbound
message of a conversation. This API denormalises it onto the conversation as `meta_ads`:

```json
"meta_ads": {
  "source": "meta_ads",
  "ad_id": "52558118838064",
  "ctwa_clid": "AfhcQdP2E4A8wWpeb1FqUzUi",
  "headline": "Diana Digital",
  "source_url": "https://fb.me/3TYpooaRT",
  "captured_at": "2026-06-16T09:12:03Z"
}
```

`meta_ads` is `null` for organic (non-ad) conversations.

**Important limitation:** Meta only sends the **ad ID**, not the campaign or ad-set name.
There is no `campaign_name` field. To report by campaign, group leads by `ad_id` in the
CRM and map ad IDs to campaign names in Meta Ads Manager (or build a separate enrichment
job against the Meta Marketing API — out of scope for this API).

Attribution is **first-touch**: it's set from the first inbound message that carries a
referral and never overwritten by a later ad click on the same conversation.

---

## Endpoints

### `GET /crm/metadata`

Everything needed to build filter dropdowns in one call: inboxes (with their channel),
labels, agents, teams, valid statuses/priorities, and the distinct Meta ads observed on
the account.

```json
{
  "channels": ["whatsapp", "instagram", "facebook", "website", "email", "sms", "telegram", "line", "twitter", "tiktok", "api"],
  "statuses": ["open", "resolved", "pending", "snoozed"],
  "priorities": ["low", "medium", "high", "urgent"],
  "inboxes": [{ "id": 3, "name": "EPLC WhatsApp", "channel": "whatsapp" }],
  "labels": [{ "id": 5, "title": "hot", "color": "#1f93ff" }],
  "agents": [{ "id": 7, "name": "Rina", "email": "rina@eplcapps.id" }],
  "teams": [{ "id": 2, "name": "Sales" }],
  "meta_ads": [{ "ad_id": "52558118838064", "headline": "Diana Digital" }]
}
```

### `GET /crm/conversations`

Paginated, filterable list of leads.

**Query parameters** (all optional, combined with AND):

| Param | Type | Notes |
|---|---|---|
| `status` | string or comma-list | `open`, `pending`, `resolved`, `snoozed` |
| `inbox_id` | integer or comma-list | |
| `channel` | string or comma-list | slug from `/crm/metadata` → `channels` (e.g. `whatsapp`, `instagram`) |
| `labels` | string or comma-list | matches conversations with **any** of the given labels |
| `assignee_id` | integer or comma-list | |
| `unassigned` | `true` | overrides `assignee_id` if both given |
| `team_id` | integer or comma-list | |
| `priority` | string or comma-list | `low`, `medium`, `high`, `urgent` |
| `source` | string | `meta_ads`, `meta_organic`, or `organic` (no Meta referral at all) |
| `ad_id` | string | exact match against `meta_ads.ad_id` |
| `ctwa_clid` | string | exact match against `meta_ads.ctwa_clid` |
| `created_after` / `created_before` | ISO8601 | filters on conversation creation time |
| `updated_since` | ISO8601 | filters on `last_activity_at` — use this for incremental sync |
| `q` | string | case-insensitive match on lead name, phone number, or email |
| `sort` | string | `last_activity_at` (default, newest first) or `created_at`; prefix with `-` for descending, e.g. `sort=-created_at` |
| `page` | integer | default `1` |
| `per_page` | integer | default `25`, max `100` |

List and comma-list params accept either a comma-separated string (`status=open,pending`)
or repeated array params (`status[]=open&status[]=pending`).

An unrecognised value for `status`, `channel`, `priority`, `source`, or `sort`, or an
unparsable date, returns `422 Unprocessable Entity`:

```json
{ "error": "invalid status: bogus" }
```

**Example — leads from Meta ads on WhatsApp, newest first:**

```
GET /api/v1/accounts/1/crm/conversations?channel=whatsapp&source=meta_ads&per_page=50
```

**Response:**

```json
{
  "data": [
    {
      "id": 1042,
      "uuid": "34986fd9-9b99-4488-b077-5a25b6cf9740",
      "status": "open",
      "priority": "high",
      "lead": {
        "id": 55,
        "name": "Budi Santoso",
        "phone_number": "+6281234567890",
        "email": null,
        "thumbnail": "https://.../avatar.png"
      },
      "channel": "whatsapp",
      "inbox": { "id": 3, "name": "EPLC WhatsApp" },
      "labels": ["hot", "follow-up"],
      "assignee": { "id": 7, "name": "Rina" },
      "team": null,
      "last_message": {
        "id": 90211,
        "content": "Halo, saya tertarik dengan promo Agustus",
        "direction": "incoming",
        "content_type": "text",
        "created_at": "2026-08-12T04:16:06Z"
      },
      "unread_count": 2,
      "created_at": "2026-08-12T04:15:40Z",
      "last_activity_at": "2026-08-12T04:16:06Z",
      "first_reply_created_at": null,
      "meta_ads": {
        "source": "meta_ads",
        "ad_id": "52558118838064",
        "ctwa_clid": "AfhcQdP2E4A8wWpeb1FqUzUi",
        "headline": "Diana Digital",
        "source_url": "https://fb.me/3TYpooaRT",
        "captured_at": "2026-08-12T04:15:40Z"
      }
    }
  ],
  "meta": { "page": 1, "per_page": 50, "total_count": 431, "total_pages": 9 }
}
```

### `GET /crm/conversations/:id`

A single conversation, same shape as one item in the `data` array above. `:id` is the
conversation's `id` (its display ID, as returned by the list endpoint) — not the internal
UUID.

`404 Not Found` if it doesn't exist, or if it belongs to an inbox your token can't access.

### `GET /crm/conversations/:conversation_id/messages`

Paginated message transcript for one conversation, newest first.

```
GET /api/v1/accounts/1/crm/conversations/1042/messages?per_page=20
```

```json
{
  "data": [
    {
      "id": 90211,
      "content": "Halo, saya tertarik dengan promo Agustus",
      "direction": "incoming",
      "content_type": "text",
      "private": false,
      "status": "sent",
      "sender": { "id": 55, "name": "Budi Santoso", "type": "Contact" },
      "content_attributes": {
        "referral": { "source_id": "52558118838064", "source_type": "ad", "ctwa_clid": "AfhcQdP2E4A8wWpeb1FqUzUi", "headline": "Diana Digital" }
      },
      "created_at": "2026-08-12T04:16:06Z"
    }
  ],
  "meta": { "page": 1, "per_page": 20, "total_count": 6, "total_pages": 1 }
}
```

`content_attributes.referral` is the raw Meta payload on that specific message — useful if
you need multi-touch attribution (every ad click on the conversation), not just the
first-touch `meta_ads` object on the conversation.

---

## Keeping the CRM in sync

Use both of these together:

**1. Polling with `updated_since` (backfill + reconciliation)**

Poll on an interval (e.g. every 1–5 minutes) using the timestamp of your last successful
sync:

```
GET /crm/conversations?updated_since=2026-08-12T04:00:00Z&sort=last_activity_at&per_page=100
```

Page through with `page`/`per_page` until `page >= total_pages`, then store the latest
`last_activity_at` you saw as the cursor for the next poll.

**2. Account webhooks (near-real-time)**

In the Chatwoot dashboard, go to **Settings → Integrations → Webhooks** and register your
CRM's endpoint (e.g. `https://crm.eplcapps.id/webhooks/chatwoot`) subscribed to
`conversation_created`, `conversation_updated`, and `message_created`. Chatwoot signs
webhook payloads with an HMAC secret shown at registration time — verify it before trusting
the payload. The webhook body already includes `additional_attributes` (which contains
`ctwa_referral`, source of the `meta_ads` object above), so you don't need to call this API
again just to get ad attribution for a webhook event — though you may still want to call
`GET /crm/conversations/:id` to get the full lead-shaped record.

Webhooks can be missed (deploys, downtime), so treat them as a low-latency signal and rely
on the `updated_since` poll as the source of truth for reconciliation.

---

## Notes

- Timestamps are ISO8601 UTC strings, not Unix epoch seconds.
- `per_page` is capped at 100; use pagination for larger result sets.
- This API is read-only — creating or updating conversations is out of scope. If the CRM
  needs to reply to a lead, that must go through Chatwoot's dashboard/agent workflow.
