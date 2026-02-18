import { createConsumer } from "@rails/actioncable"

const consumer = createConsumer()
const STORAGE_KEY = "mongo_explain_ui_events_v1"
const MIN_VISIBLE_MS = 5000
const DEDUPE_WINDOW_MS = 2500
const MAX_STORED_EVENTS = 200

class OverlayClient {
  constructor(element) {
    this.element = element
    this.stack = element.querySelector("[data-stack]")
    this.status = this.ensureStatusContainer(element)
    this.maxStack = this.safePositiveNumber(element.dataset.maxStack, 5)
    this.defaultTtlMs = this.safePositiveNumber(element.dataset.defaultTtlMs, 12000)
    this.levelStyles = this.parseLevelStyles(element.dataset.levelStyles)
    this.dismissTimers = new Map()
    this.subscription = null
    this.state = this.loadState()
    this.state.events = this.pruneExpired(this.state.events)
    this.state.recentByDedupeKey = this.pruneDedupe(this.state.recentByDedupeKey)
  }

  connect() {
    const channel = this.element.dataset.channel
    if (!channel || !this.stack) return

    this.subscription = consumer.subscriptions.create(
      { channel },
      { received: (payload) => this.received(payload) }
    )

    this.render()
  }

  disconnect() {
    if (this.subscription) {
      consumer.subscriptions.remove(this.subscription)
      this.subscription = null
    }
    this.dismissTimers.forEach((timerId) => clearTimeout(timerId))
    this.dismissTimers.clear()
  }

  received(payload) {
    if (!payload || typeof payload !== "object") return

    const event = this.buildEvent(payload)
    this.state.events = this.pruneExpired(this.state.events)
    const existingEvent = this.state.events.find((candidate) => candidate.merge_key === event.merge_key)

    if (existingEvent) {
      const mergedEvent = this.mergeEvent(existingEvent, event)
      this.state.events = [
        mergedEvent,
        ...this.state.events.filter((candidate) => candidate.id !== existingEvent.id)
      ].slice(0, MAX_STORED_EVENTS)
    } else {
      if (this.isDuplicate(payload)) return

      this.state.events = [
        event,
        ...this.state.events.filter((existingCandidate) => existingCandidate.id !== event.id)
      ].slice(0, MAX_STORED_EVENTS)
    }

    this.saveState()
    this.render()
  }

  isDuplicate(payload) {
    const dedupeKey = (payload.dedupe_key || "").toString().trim()
    if (!dedupeKey) return false

    const now = Date.now()
    const previous = this.state.recentByDedupeKey[dedupeKey]
    this.state.recentByDedupeKey[dedupeKey] = now
    this.state.recentByDedupeKey = this.pruneDedupe(this.state.recentByDedupeKey)
    this.saveState()

    return previous && (now - previous) < DEDUPE_WINDOW_MS
  }

  buildEvent(payload) {
    const now = Date.now()
    const ttlMs = this.effectiveTtl(payload.ttl_ms)

    return {
      ...payload,
      id: this.eventIdFor(payload),
      merge_key: this.mergeKeyFor(payload),
      category: this.eventCategoryFor(payload),
      count: 1,
      ttl_ms: ttlMs,
      expires_at: now + ttlMs
    }
  }

  mergeEvent(existingEvent, incomingEvent) {
    const existingCount = this.safePositiveNumber(existingEvent.count, 1)

    return {
      ...existingEvent,
      ...incomingEvent,
      id: existingEvent.id,
      merge_key: existingEvent.merge_key || incomingEvent.merge_key,
      category: existingEvent.category || incomingEvent.category || "other",
      count: existingCount + 1,
      expires_at: incomingEvent.expires_at
    }
  }

  render() {
    this.state.events = this.pruneExpired(this.state.events)
    this.saveState()

    this.stack.innerHTML = ""
    const visibleEvents = this.state.events.slice(0, this.maxStack)
    const activeEventIds = new Set(this.state.events.map((event) => event.id))

    visibleEvents.forEach((event) => {
      const card = this.buildCard(event)
      this.stack.appendChild(card)
    })

    this.state.events.forEach((event) => {
      this.scheduleAutoDismiss(event.id, event.expires_at)
    })

    this.dismissTimers.forEach((timerId, eventId) => {
      if (activeEventIds.has(eventId)) return

      clearTimeout(timerId)
      this.dismissTimers.delete(eventId)
    })

    this.renderStatusBar(this.state.events)
  }

  buildCard(event) {
    const wrapper = document.createElement("div")
    wrapper.className = `mongo-explain-ui-card ${this.levelClass(event)} ${this.categoryClass(event)}`
    wrapper.dataset.eventId = event.id

    const title = document.createElement("div")
    title.className = "mongo-explain-ui-card__title"
    title.textContent = this.titleText(event)
    wrapper.appendChild(title)

    const message = document.createElement("p")
    message.className = "mongo-explain-ui-card__message"
    message.textContent = (event.message || "").toString()
    wrapper.appendChild(message)

    const callsite = event?.meta?.callsite
    if (callsite) {
      const meta = document.createElement("p")
      meta.className = "mongo-explain-ui-card__meta"
      meta.textContent = `Callsite: ${callsite}`
      wrapper.appendChild(meta)
    }

    if (event.dismissible !== false) {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "mongo-explain-ui-card__dismiss"
      button.textContent = "×"
      button.addEventListener("click", () => this.dismissById(event.id))
      wrapper.appendChild(button)
    }

    return wrapper
  }

  scheduleAutoDismiss(eventId, expiresAt) {
    const remainingMs = Number(expiresAt) - Date.now()
    if (remainingMs <= 0) {
      this.dismissById(eventId)
      return
    }

    const existingTimer = this.dismissTimers.get(eventId)
    if (existingTimer) clearTimeout(existingTimer)

    const timerId = setTimeout(() => this.dismissById(eventId), remainingMs)
    this.dismissTimers.set(eventId, timerId)
  }

  dismissById(eventId) {
    if (!eventId) return
    const timerId = this.dismissTimers.get(eventId)
    if (timerId) {
      clearTimeout(timerId)
      this.dismissTimers.delete(eventId)
    }

    const beforeCount = this.state.events.length
    this.state.events = this.state.events.filter((event) => event.id !== eventId)
    if (this.state.events.length === beforeCount) return

    this.saveState()
    this.render()
  }

  renderStatusBar(events) {
    if (!this.status) return

    if (events.length <= this.maxStack) {
      this.status.innerHTML = ""
      this.status.classList.add("hidden")
      return
    }

    const counts = this.categoryCounts(events)
    this.status.innerHTML = ""

    const row = document.createElement("div")
    row.className = "mongo-explain-ui-status-bar"
    row.appendChild(this.buildStatusLabel("IXSCAN", counts.ixscan))
    row.appendChild(this.buildStatusSeparator())
    row.appendChild(this.buildStatusLink("COLLSCAN", counts.collscan, "collscan"))
    row.appendChild(this.buildStatusSeparator())
    row.appendChild(this.buildStatusLink("OTHER", counts.other, "other"))

    this.status.appendChild(row)
    this.status.classList.remove("hidden")
  }

  buildStatusLabel(label, count) {
    const span = document.createElement("span")
    span.className = "mongo-explain-ui-status-bar__label"
    span.textContent = `${label} (${count})`
    return span
  }

  buildStatusLink(label, count, category) {
    if (count <= 0) return this.buildStatusLabel(label, count)

    const button = document.createElement("button")
    button.type = "button"
    button.className = "mongo-explain-ui-status-bar__link"
    button.textContent = `${label} (${count})`
    button.addEventListener("click", () => this.inspectCategory(category))
    return button
  }

  buildStatusSeparator() {
    const separator = document.createElement("span")
    separator.className = "mongo-explain-ui-status-bar__separator"
    separator.textContent = "/"
    return separator
  }

  inspectCategory(category) {
    this.state.events = this.pruneExpired(this.state.events)
    const selectedEvents = this.state.events.filter((event) => event.category === category).slice(0, this.maxStack)
    if (selectedEvents.length === 0) return

    const now = Date.now()
    const selectedIds = new Set(selectedEvents.map((event) => event.id))
    const refreshedById = new Map(
      selectedEvents.map((event) => ([
        event.id,
        {
          ...event,
          expires_at: now + this.effectiveTtl(event.ttl_ms)
        }
      ]))
    )

    this.state.events = [
      ...selectedEvents.map((event) => refreshedById.get(event.id)),
      ...this.state.events.filter((event) => !selectedIds.has(event.id))
    ].slice(0, MAX_STORED_EVENTS)

    this.saveState()
    this.render()
  }

  categoryCounts(events) {
    return events.reduce((counts, event) => {
      const weight = this.safePositiveNumber(event.count, 1)
      const category = this.eventCategoryFor(event)
      counts[category] += weight
      return counts
    }, { ixscan: 0, collscan: 0, other: 0 })
  }

  eventIdFor(payload) {
    return (payload.id || `${Date.now()}-${Math.random()}`).toString()
  }

  mergeKeyFor(payload) {
    const dedupeKey = (payload.dedupe_key || "").toString().trim()
    if (dedupeKey) return `dedupe:${dedupeKey}`

    const title = (payload.title || "").toString().trim()
    const operation = (payload?.meta?.operation || "").toString().trim()
    const namespace = (payload?.meta?.namespace || "").toString().trim()
    const callsite = (payload?.meta?.callsite || "").toString().trim()

    if (title || operation || namespace || callsite) {
      return `fallback:${title}:${operation}:${namespace}:${callsite}`
    }

    return `id:${this.eventIdFor(payload)}`
  }

  eventCategoryFor(payload) {
    const level = (payload.level || "").toString().trim().toLowerCase()
    if (level === "collscan") return "collscan"

    const plan = this.planFromPayload(payload)
    if (plan.includes("COLLSCAN")) return "collscan"
    if (plan.includes("IXSCAN")) return "ixscan"
    return "other"
  }

  planFromPayload(payload) {
    const planMeta = (payload?.meta?.plan || "").toString().trim().toUpperCase()
    if (planMeta) return planMeta

    const message = (payload?.message || "").toString()
    const matchedPlan = message.match(/\bplan\s+([A-Z_]+)/i)
    return matchedPlan ? matchedPlan[1].toUpperCase() : ""
  }

  titleText(event) {
    const title = (event.title || "MongoExplain").toString()
    const count = this.safePositiveNumber(event.count, 1)
    return count > 1 ? `${title} (${count})` : title
  }

  levelClass(payload) {
    const level = (payload.level || "info").toString()
    return this.levelStyles[level] || "mongo-explain-ui-card--info"
  }

  categoryClass(event) {
    if (event.category === "other") return "mongo-explain-ui-card--other"
    return ""
  }

  effectiveTtl(rawTtl) {
    const configuredTtl = this.safePositiveNumber(rawTtl, this.defaultTtlMs)
    return Math.max(configuredTtl, MIN_VISIBLE_MS)
  }

  pruneExpired(events) {
    const now = Date.now()
    return events.filter((event) => Number(event.expires_at) > now)
  }

  pruneDedupe(recentByDedupeKey) {
    const now = Date.now()
    const entries = Object.entries(recentByDedupeKey || {})
    const pruned = {}

    entries.forEach(([key, value]) => {
      const numericValue = Number(value)
      if (!Number.isFinite(numericValue)) return
      if ((now - numericValue) >= DEDUPE_WINDOW_MS) return

      pruned[key] = numericValue
    })

    return pruned
  }

  loadState() {
    const defaultState = { events: [], recentByDedupeKey: {} }

    try {
      const raw = sessionStorage.getItem(STORAGE_KEY)
      if (!raw) return defaultState

      const parsed = JSON.parse(raw)
      if (typeof parsed !== "object" || parsed === null) return defaultState

      const events = Array.isArray(parsed.events) ? parsed.events : []
      const recentByDedupeKey = (
        typeof parsed.recentByDedupeKey === "object" && parsed.recentByDedupeKey !== null
      ) ? parsed.recentByDedupeKey : {}

      const normalizedEvents = events
        .map((event) => this.normalizeLoadedEvent(event))
        .filter(Boolean)

      const normalizedDedupe = this.pruneDedupe(recentByDedupeKey)
      return {
        events: normalizedEvents,
        recentByDedupeKey: normalizedDedupe
      }
    } catch (_error) {
      return defaultState
    }
  }

  saveState() {
    try {
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify(this.state))
    } catch (_error) {
      // best-effort persistence only
    }
  }

  safePositiveNumber(value, fallback) {
    const parsed = Number(value)
    if (!Number.isFinite(parsed) || parsed <= 0) {
      return fallback
    }

    return parsed
  }

  normalizeLoadedEvent(event) {
    if (typeof event !== "object" || event === null) return null

    const ttlMs = this.effectiveTtl(event.ttl_ms)
    const expiresAt = Number(event.expires_at)
    const normalizedExpiresAt = Number.isFinite(expiresAt) ? expiresAt : Date.now() + ttlMs

    return {
      ...event,
      id: this.eventIdFor(event),
      merge_key: this.mergeKeyFor(event),
      category: this.eventCategoryFor(event),
      count: this.safePositiveNumber(event.count, 1),
      ttl_ms: ttlMs,
      expires_at: normalizedExpiresAt
    }
  }

  parseLevelStyles(value) {
    if (!value) return {}

    try {
      const parsed = JSON.parse(value)
      return typeof parsed === "object" && parsed !== null ? parsed : {}
    } catch (_error) {
      return {}
    }
  }

  ensureStatusContainer(element) {
    const existing = element.querySelector("[data-status]")
    if (existing) return existing

    const created = document.createElement("div")
    created.dataset.status = ""
    created.className = "mongo-explain-ui-overlay__status hidden"
    element.appendChild(created)
    return created
  }
}

const clients = new WeakMap()

function connectOverlays() {
  document.querySelectorAll("[data-mongo-explain-ui-overlay]").forEach((element) => {
    if (clients.has(element)) return

    const client = new OverlayClient(element)
    client.connect()
    clients.set(element, client)
  })
}

function disconnectOverlays() {
  document.querySelectorAll("[data-mongo-explain-ui-overlay]").forEach((element) => {
    const client = clients.get(element)
    if (!client) return

    client.disconnect()
    clients.delete(element)
  })
}

document.addEventListener("turbo:before-cache", disconnectOverlays)
document.addEventListener("turbo:load", connectOverlays)
connectOverlays()
