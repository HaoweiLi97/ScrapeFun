# AI connections and configuration

[简体中文](ai-settings.md) · [English](ai-settings.en.md)

2026-11-03

<a id="start"></a>

## Entry points and requirements

Checked against the current development version marked 0.5.1; released builds may have different locations or capabilities. Administrators manage text, voice, and image services under Server Settings → AI Configuration. Metadata translation bindings and behavior are under Scraping & Matching. Check the instance version if an option is absent.

Text AI uses a Chat Completions-compatible service. Obtain the endpoint, model ID, and key from your provider; an endpoint implementing another protocol cannot be used directly. Cloud usage and quotas are managed by the provider. External AI authoring extensions against the [scraper contract](scrapers.en.md) does not require configuring built-in text AI first.

<a id="text"></a>

## Add a text AI connection

1. Add a connection in the text AI area of AI Configuration.
2. Enter its name, endpoint, API key, and model; enable as needed.
3. Retrieve models, select or enter a real model ID, then test the connection.
4. Save, select the connection in the relevant feature, and verify one real request.

| Setting | What to enter |
| --- | --- |
| Name | A recognizable connection label; create separate connections for separate services |
| Endpoint URL | The API base, such as synthetic `https://ai.example/v1`, or the full `/chat/completions` endpoint |
| API key | The AI provider key, distinct from a ScrapeFun session token; text connection tests require a nonempty key |
| Model | A model ID available from that provider and accessible to your key; preserve its exact name and case |
| Enabled | Must be enabled for bound features to use it |

Do not enter a chat webpage URL or embed credentials in the URL. Preserve the version path required by the provider rather than guessing `/v1` for every service. Local compatible services must implement the same request protocol. Use a nonempty placeholder key for an unauthenticated service only if that service explicitly accepts it.

Connections originate from Server. In Docker, localhost means the container itself; host accessibility does not prove container accessibility. Use an address reachable from Server and expose ports only to the required network. Use HTTPS remotely.

Retrieving models proves only that the directory request was accepted, not that the selected model can run. Some providers omit a directory or use aliases; enter the model ID directly and test it. Retest after changing the endpoint, key, or model. Testing does not automatically save an unsaved form.

<a id="translation"></a>

## Bind metadata translation

Under Scraping & Matching → Metadata translation, select an enabled text AI connection, then configure scope, title cleaning, prompt, and automatic translation during scraping. Saving a connection and binding a feature are separate steps. An unbound or disabled connection can leave the feature unavailable.

Translate one test item first and check titles, summaries, years, and volume/episode numbers before enabling automatic translation. Changing scope does not establish that all existing media has been translated again. Custom prompts should preserve source facts, IDs, and numbers. Never put keys or account information into prompts.

Translation sends the relevant text to the selected provider. Confirm that this data is appropriate to share with that service. Text and voice AI connections are managed separately; a successful text test does not validate audio features.

<a id="voice"></a>

## Voice AI and audiobooks

Add a voice connection in AI Configuration, select the protocol matching the service, and fill in these fields. Current options include Audio Speech and Chat Completions Audio. A working text model does not necessarily produce audio.

| Setting | Purpose |
| --- | --- |
| Protocol and endpoint | Audio Speech uses `/audio/speech`; Chat Completions Audio uses an audio-capable `/chat/completions` service; enter a base or full endpoint as required |
| Model and API key | An audio model and credentials supporting the selected protocol; some local Audio Speech services allow an empty key, subject to UI validation |
| Preferred voice ID | An actual provider voice ID, not its display label |
| Voice list URL and catalog | Retrieve from a provider voice endpoint or maintain manually; there is no universal voice directory across all services |
| Narration guidance | Optional speaking-style instructions; support depends on the model and protocol |
| Enabled | Save and enable, then select the corresponding voice in the reader's audiobook controls |

Test a short passage for successful generation, playback, and voice selection before narrating a long book. Models, voices, and response formats from different protocols are not interchangeable. Consider privacy before sending book text to a remote voice provider.

<a id="images"></a>

## Image enhancement

Select enhancement engines and models in AI Configuration. Device, tile, thread, and output parameters are in Advanced settings. Choose from the capabilities and model list shown by your instance; availability varies with platform, hardware, and model.

Image enhancement does not use a text connection's key or model. Test a few comic pages for quality, latency, and resource usage; repeat after changing models. Features requiring product entitlements follow the instance UI.

<a id="api"></a>

## Connection test API

These endpoints require an [administrator Bearer session](api.en.md#authentication) and your own Server address. Both use the submitted values without saving settings. They contact the specified AI provider, and model tests may incur usage.

| Endpoint | Request and response |
| --- | --- |
| `POST /api/settings/ai/text/models` | `{url,key}`; success returns `{models:[modelId,...],keyStatus:"valid"}` |
| `POST /api/settings/ai/text/test` | `{url,key,model}`; success returns `{success:true,keyStatus:"valid",latencyMs,model}` |

```json
{"url":"https://ai.example/v1","key":"YOUR_AI_PROVIDER_KEY","model":"YOUR_MODEL_ID"}
```

This test request uses placeholder domains and credentials. The Server Authorization header takes the ScrapeFun session token; the body key takes the AI provider key. They are not interchangeable.

```bash
jq -n '{url:env.AI_BASE_URL,key:env.AI_API_KEY,model:env.AI_MODEL}' |
curl --fail-with-body --silent --show-error --max-time 60 \
  --request POST "$SCRAPEFUN_URL/api/settings/ai/text/test" \
  --header "Authorization: Bearer $SCRAPEFUN_TOKEN" \
  --header 'Content-Type: application/json' --data-binary @-
```

Set these environment variables locally without printing them publicly. After a successful test, save and bind the connection in Settings. Failures may use HTTP 400, 403, 502, or 504. Read error, code, keyStatus, and solution when present; not every 502 means an invalid key.

<a id="troubleshooting"></a>

## Troubleshooting

| Symptom or error | Check |
| --- | --- |
| `AI_API_KEY_MISSING` | Enter the provider key; text tests reject empty values |
| `AI_AUTH_FAILED`, `AI_ACCESS_DENIED` | Key expiration, permissions, and provider restrictions |
| `AI_MODEL_NOT_LISTED` | Directory IDs; verify aliases through a real model test |
| `AI_REQUEST_REJECTED` | Protocol, endpoint path, model, and request compatibility |
| `AI_BALANCE_INSUFFICIENT`, `AI_RATE_LIMITED` | Provider balance, quota, and request rate; avoid retry loops |
| DNS, connection, or timeout errors | Address and network from Server's environment; these failures do not prove the key invalid |
| `AI_EMPTY_RESPONSE` | The request was accepted without usable text; inspect model and response format |
| Test succeeds but feature fails | Saving, enabled state, binding, and required model capabilities |

Remove keys, session tokens, private service addresses, and personal information before sharing screenshots or logs. See the [settings guide](settings.en.md) for common locations and verification steps.
