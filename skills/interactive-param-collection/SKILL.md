---
name: interactive-param-collection
description: >
  Implement interactive parameter collection for bot commands and CLI tools.
  Use this skill when a command handler is missing required parameters and you want
  to prompt the user interactively instead of returning a plain error — particularly
  for Telegram bots (force_reply), console scripts (readline prompt), Slack/Discord bots,
  or any system where you need multi-step input WITHOUT storing session state.
  Trigger this skill when you see patterns like: "ask user for missing param",
  "interactive command", "prompt and wait for input", "force reply", "collect params
  step by step", or when a command handler silently fails due to missing arguments.
---

# Interactive Parameter Collection

A stateless pattern for collecting missing command parameters through a prompt→reply loop.
Works in Telegram, console CLIs, Discord, Slack, or any request/response system.

## Core Idea

Instead of failing with a plain error when a required param is missing:

```
User: /query
Bot:  "Vui lòng cung cấp label."   ← dead end, user must retype the whole command
```

Emit a **prompt with a routing marker**, intercept the reply, and call the same handler:

```
User: /query
Bot:  "[PARAM:/query] Nhập label:"  ← force_reply UI appears
User: (replies) bl
Bot:  (keyboard with VPN options)   ← same result as /query bl
```

No session storage needed — the routing marker lives in the prompt text itself.

## The Three-Part Pattern

### 1. Extract core handler logic

Before adding interactivity, split each command handler into two functions:

```typescript
// Entry point — parses input, handles missing params
async function handleQuery(c: AppContext, tgCtx: TelegramContext): Promise<void> {
    const label = (tgCtx.getMessage()?.text ?? '').split(/\s+/)[1];
    if (!label) {
        await promptForParam(bot, chatId, '/query', 'Nhập label:', 'Ví dụ: bl',
            tgCtx.getMessage()?.message_id);  // ← pass original msg ID
        return;
    }
    await handleQueryByLabel(c, chatId, label);  // ← extracted core
}

// Core logic — called from BOTH the command path and the reply path
async function handleQueryByLabel(c: AppContext, chatId: number, label: string): Promise<void> {
    // actual business logic here, no parsing
}
```

This separation is what makes the reply path possible without duplicating logic.

### 2. Send a routable prompt

```typescript
async function promptForParam(
    bot: BotClient,
    chatId: number,
    cmd: string,          // e.g. '/query' — used as routing key
    prompt: string,       // human-readable text shown to user
    placeholder?: string, // hint inside the input field
    replyToMessageId?: number,  // REQUIRED for group chats (see below)
): Promise<void> {
    await bot.sendMessage({
        chat_id: chatId,
        text: `[PARAM:${cmd}] ${prompt}`,
        reply_to_message_id: replyToMessageId,   // makes selective force_reply work
        reply_markup: JSON.stringify({
            force_reply: true,
            selective: true,
            ...(placeholder ? { input_field_placeholder: placeholder } : {}),
        }),
    });
}
```

The `[PARAM:/cmd]` prefix in the text is the stateless routing marker — it travels with the
message and comes back in `reply_to_message.text` when the user replies.

### 3. Intercept replies and route

Place this check **at the top of your message router**, before any command parsing:

```typescript
async function routeMessage(ctx): Promise<void> {
    const msg = ctx.getMessage();

    // Check for param-collection replies first
    if (msg.reply_to_message && 'text' in msg.reply_to_message) {
        if (await routeParamReply(ctx, msg.reply_to_message.text ?? '')) return;
    }

    // ... rest of normal command routing
}

async function routeParamReply(ctx, promptText: string): Promise<boolean> {
    const match = promptText.match(/^\[PARAM:([^\]]+)\]/);
    if (!match) return false;

    const cmd = match[1].toLowerCase();
    const input = ctx.getMessage()?.text?.trim() ?? '';
    if (!input) { /* re-prompt or error */ return true; }

    switch (cmd) {
        case '/query': await handleQueryByLabel(ctx, chatId, input); break;
        case '/fetch': await handleFetchForLabel(ctx, chatId, input, 'VN', 1); break;
        case '/delete': await handleDeleteInput(ctx, chatId, input); break;
        case '/ask':    await runAgent(ctx, chatId, AskAgent, input); break;
        default: return false;
    }
    return true;
}
```

## Critical: `replyToMessageId` in Group Chats

`selective: true` means force_reply only targets specific users. Telegram determines the target from:
- users @mentioned in the bot's message, OR
- the sender of the message the bot is **replying to**

If you don't pass `reply_to_message_id`, Telegram doesn't know which user to prompt →
force_reply UI never appears → user sends a bare message → interceptor misses it.

**Always pass the original command's `message_id` when calling `promptForParam` in a group context.**

In private chats, `selective: true` doesn't matter (there's only one user), but it's harmless.

## Generalizing Beyond Telegram

The same pattern applies anywhere you have a request/response or message loop:

### Console / CLI
```python
def handle_query(args):
    label = args[1] if len(args) > 1 else None
    if not label:
        label = input("[PARAM:/query] Enter label: ").strip()
        # In a CLI, you read the reply synchronously — no interceptor needed
    query_by_label(label)
```

### Slack / Discord
```typescript
// Slack: post an ephemeral message asking for param, store state in message metadata
// Discord: use a Modal (built-in multi-field input) or an awaited message collector
// Both platforms have first-class "collect input from user" primitives
```

### Web API (stateless sessions)
```
POST /command { cmd: "/query" }
→ 200 { status: "need_param", prompt: "Enter label:", token: "PARAM:/query:sessionId" }

POST /command/reply { token: "PARAM:/query:sessionId", input: "bl" }
→ 200 { result: [...VPN list...] }
```
The token plays the same role as the `[PARAM:...]` marker — it encodes what to do with the reply.

## When to Apply This Pattern

Apply it when ALL of these are true:
1. A command/action has required parameters
2. Users often invoke it without providing those parameters
3. The missing-param case currently returns a plain error or usage hint
4. The UX would benefit from guided step-by-step input

Don't apply it when:
- The command always needs the param inline (e.g., inline queries, keyboard actions)
- There are multiple required params that can't be collected one at a time sensibly
- The platform has a native modal/form input (prefer that instead — it's more ergonomic)

## Checklist When Adding a New Interactive Command

- [ ] Extract core logic into a separate function (e.g., `handleXByParam`)
- [ ] Call `promptForParam(...)` with the original `message_id` in the missing-param branch
- [ ] Add a `case '/x':` in `routeParamReply` that calls the core function
- [ ] Verify the interceptor check runs **before** the main switch in the router
- [ ] Test in group chat (not just private) — that's where selective force_reply matters
