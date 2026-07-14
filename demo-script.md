# 60-Second Sales Call Demo Script — Private LLM Stack

> **Goal:** Show the prospect they can have a private, secure, ChatGPT-quality LLM running in under 20 minutes — with zero data leaving their infrastructure.

---

## The Script (read this aloud)

**(0:00 — Hook)**
> "What if I told you your team could have a private ChatGPT — running on your own infrastructure, with your data never leaving your network — in about 20 minutes? Let me show you."

**(0:10 — The Problem)**
> "You're probably using ChatGPT or Claude today. Every prompt, every document you paste, every question your engineers ask — that data goes to OpenAI. For internal docs, customer data, source code... that's a compliance risk. And you're paying $20/user/month with rate limits."

**(0:25 — The Solution)**
> "What I deploy is a private LLM stack. It runs on a single AWS instance — GPU-accelerated — with three components: Ollama serves the model, Open WebUI gives you a ChatGPT-style interface, and Caddy handles TLS and authentication. Your team accesses it at a URL like `llm.yourcompany.com` — behind a login."

**(0:40 — The Demo)**
> *[Open the access URL in browser — show the Open WebUI chat interface]*
>
> "This is Llama 3.1 — Meta's latest open model. Same quality as GPT-4 for most tasks. Let me ask it something..."
>
> *[Type a prompt relevant to their business: "Summarize the key points of a software license agreement" or "Write a Python function to validate an email address"]*
>
> "Notice — that response came from a model running on hardware you control. No API calls, no per-token charges, no data leaving your VPC."

**(0:55 — The Close)**
> "Here's the deal: I set this up for you, manage the infrastructure, and you get unlimited prompts for your whole team. Starter tier is $250/month — that's cheaper than 12 ChatGPT Plus subscriptions, and there's no rate limit. You own the data. Shall we get you onboarded?"

---

## Quick Reference: Cost Tiers

| Tier          | Your Cost  | Client Price | Margin    | Best For                          |
|---------------|------------|-------------|-----------|-----------------------------------|
| Starter       | ~$40/mo    | $250/mo     | $210/mo   | Small teams, 8B model, CPU        |
| Professional  | ~$570/mo   | $750/mo     | $180/mo   | Medium teams, 70B model, GPU      |
| Enterprise    | ~$1,140/mo | $2,000/mo   | $860/mo   | Large teams, HA, 70B+, priority   |

## Objection Handling

**"Is it as good as GPT-4?"**
> "For 90% of business use cases — summarization, Q&A, code generation, document analysis — Llama 3.1 70B is comparable. You also get zero rate limits and zero per-token costs. For the 10% where GPT-4 is better, you can run both side by side."

**"What about data security?"**
> "The model runs entirely on your AWS infrastructure. No data is sent to any third-party API. The Ollama API binds to localhost only. You control access via CIDR restrictions and basic auth. For enterprise, we add VPN/WAF."

**"What if the model goes down?"**
> "The stack auto-restarts via systemd health checks. Docker containers use `--restart unless-stopped`. Enterprise tier includes HA with a load balancer and failover."

**"Can we use different models?"**
> "Yes — any model in the Ollama library. Llama, Mistral, CodeLlama, Phi, Gemma. Switch with one config change and a `terraform apply`."

**"How fast is onboarding?"**
> "20 minutes from `terraform apply` to a working chat interface. The model download takes 5-40 minutes depending on size, but the UI is live immediately."
