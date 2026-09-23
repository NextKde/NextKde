#!/usr/bin/env node

'use strict'

const crypto = require('crypto')
const http = require('http')
const https = require('https')
const readline = require('readline')
const zlib = require('zlib')
const vm = require('vm')
const { URL, URLSearchParams } = require('url')

const REQUEST_TIMEOUT_MS = 60000
const MAX_RESPONSE_BYTES = 8 * 1024 * 1024
const SUPPORTED_SOURCES = ['kw', 'kg', 'tx', 'wy', 'mg', 'local']
const SUPPORTED_QUALITIES = ['128k', '320k', 'flac', 'flac24bit']
const TRACE = process.env.KOS_MUSIC_SOURCE_TRACE === '1'

function trace(event, data) {
  if (TRACE)
    process.stderr.write(`[source-trace] ${event} ${JSON.stringify(data)}\n`)
}

let requestHandler = null
let context = null
let sourceCapabilities = null
let updateAlertSent = false
const activeRequests = new Map()

function reply(id, ok, result, error) {
  process.stdout.write(JSON.stringify(ok ? { id, ok, result } : { id, ok, error }) + '\n')
}

function safeError(error) {
  return error instanceof Error ? error : new Error(String(error ?? 'Unknown source error'))
}

function normalizeInitialization(data) {
  if (!data || typeof data !== 'object' || !data.sources
      || typeof data.sources !== 'object') {
    throw new Error('Source did not announce valid provider capabilities')
  }
  const sources = {}
  for (const source of SUPPORTED_SOURCES) {
    const candidate = data.sources[source]
    if (!candidate || candidate.type !== 'music')
      continue
    const actions = Array.isArray(candidate.actions) ? candidate.actions : []
    const declaredQualities = Array.isArray(candidate.qualitys) ? candidate.qualitys : []
    const qualitys = source === 'local'
      ? [] : SUPPORTED_QUALITIES.filter(quality => declaredQualities.includes(quality))
    sources[source] = {
      name: typeof candidate.name === 'string' ? candidate.name : source,
      type: 'music',
      actions: actions.filter(action =>
        source === 'local'
          ? ['musicUrl', 'lyric', 'pic'].includes(action)
          : action === 'musicUrl'),
      qualitys,
    }
  }
  if (Object.keys(sources).length === 0)
    throw new Error('Source does not support any recognized provider')
  return { ...data, sources }
}

function networkRequest(urlText, options = {}, callback, redirects = 0) {
  if (typeof callback !== 'function') return ''
  let url
  try {
    url = new URL(String(urlText))
    if (url.protocol !== 'http:' && url.protocol !== 'https:')
      throw new Error('URL is not allowed')
  } catch (error) {
    queueMicrotask(() => callback(safeError(error)))
    return ''
  }

  const id = crypto.randomUUID()
  const method = String(options.method || 'GET').toUpperCase()
  const headers = { ...(options.headers || {}) }
  if (!Object.keys(headers).some(name => name.toLowerCase() === 'user-agent'))
    headers['User-Agent'] = 'Mozilla/5.0 KOS-Music/1.0'
  let body = options.body
  if (body == null && options.form != null) {
    body = new URLSearchParams(options.form).toString()
    headers['Content-Type'] ||= 'application/x-www-form-urlencoded'
  } else if (body != null && typeof body !== 'string' && !Buffer.isBuffer(body)) {
    body = JSON.stringify(body)
  }
  if (typeof body === 'string') body = Buffer.from(body)
  if (body) headers['Content-Length'] = String(body.length)

  trace('request', { url: url.toString(), method })
  const transport = url.protocol === 'https:' ? https : http
  const request = transport.request(url, { method, headers }, response => {
    if ([301, 302, 303, 307, 308].includes(response.statusCode)
        && response.headers.location && redirects < 5) {
      response.resume()
      activeRequests.delete(id)
      networkRequest(new URL(response.headers.location, url).toString(), options,
                     callback, redirects + 1)
      return
    }
    const chunks = []
    let size = 0
    response.on('data', chunk => {
      size += chunk.length
      if (size > MAX_RESPONSE_BYTES) request.destroy(new Error('Response is too large'))
      else chunks.push(chunk)
    })
    response.on('end', () => {
      activeRequests.delete(id)
      let buffer = Buffer.concat(chunks)
      try {
        const encoding = String(response.headers['content-encoding'] || '').toLowerCase()
        if (encoding.includes('gzip'))
          buffer = zlib.gunzipSync(buffer)
        else if (encoding.includes('br'))
          buffer = zlib.brotliDecompressSync(buffer)
        else if (encoding.includes('deflate'))
          buffer = zlib.inflateSync(buffer)
      } catch (error) {
        callback(safeError(error))
        return
      }
      if (buffer.length > MAX_RESPONSE_BYTES) {
        callback(new Error('Response is too large'))
        return
      }
      const bodyText = buffer.toString('utf8')
      let responseBody = bodyText
      const trimmed = bodyText.trim()
      if (trimmed) {
        try { responseBody = JSON.parse(trimmed) }
        catch {}
      }
      trace('response', { url: url.toString(), statusCode: response.statusCode || 0, body: bodyText.slice(0, 512) })
      callback(null, {
        statusCode: response.statusCode || 0,
        statusMessage: response.statusMessage || '',
        headers: response.headers,
        bytes: buffer.length,
        raw: buffer,
        body: responseBody,
      }, responseBody)
    })
  })
  activeRequests.set(id, request)
  request.setTimeout(Math.min(REQUEST_TIMEOUT_MS, Math.max(1, Number(options.timeout) || REQUEST_TIMEOUT_MS)), () => {
    request.destroy(new Error('Request timed out'))
  })
  request.on('error', error => {
    activeRequests.delete(id)
    callback(safeError(error))
  })
  if (body) request.write(body)
  request.end()
  return () => {
    activeRequests.delete(id)
    if (!request.destroyed) request.destroy(new Error('Request cancelled'))
  }
}

async function loadSource(command) {
  requestHandler = null
  sourceCapabilities = null
  updateAlertSent = false
  let initializedData = null
  let initializedResolve
  const initialized = new Promise(resolve => { initializedResolve = resolve })
  const lx = {
    EVENT_NAMES: { request: 'request', inited: 'inited', updateAlert: 'updateAlert' },
    version: '2.0.0',
    env: 'desktop',
    currentScriptInfo: {
      ...(command.info || {}),
      rawScript: String(command.script || ''),
    },
    request: networkRequest,
    on(name, handler) {
      if (name !== 'request' || typeof handler !== 'function')
        return Promise.reject(new Error(`Unsupported event: ${name}`))
      requestHandler = handler
      return Promise.resolve()
    },
    send(name, data) {
      if (name === 'inited') {
        initializedData = data || {}
        initializedResolve()
        return Promise.resolve()
      }
      if (name === 'updateAlert') {
        if (updateAlertSent)
          return Promise.reject(new Error('The update alert can only be called once.'))
        updateAlertSent = true
        if (!data || typeof data !== 'object' || typeof data.log !== 'string')
          return Promise.reject(new Error('A source update alert requires a log string.'))
        const updateUrl = typeof data.updateUrl === 'string'
          && data.updateUrl.length <= 1024
          && /^https?:\/\//.test(data.updateUrl) ? data.updateUrl : undefined
        trace('updateAlert', { log: data.log.slice(0, 1024), updateUrl })
        return Promise.resolve()
      }
      return Promise.reject(new Error(`Unsupported event: ${name}`))
    },
    utils: {
      crypto: {
        aesEncrypt(buffer, mode, key, iv) {
          const cipher = crypto.createCipheriv(mode, key, iv)
          return Buffer.concat([cipher.update(buffer), cipher.final()])
        },
        rsaEncrypt(buffer, key) {
          const input = Buffer.from(buffer)
          const padded = Buffer.concat([Buffer.alloc(128 - input.length), input])
          return crypto.publicEncrypt(
            { key, padding: crypto.constants.RSA_NO_PADDING }, padded)
        },
        randomBytes(size) { return crypto.randomBytes(size) },
        md5(value) {
          const input = Buffer.isBuffer(value)
            ? value
            : Buffer.from(typeof value === 'string' ? value : JSON.stringify(value))
          return crypto.createHash('md5').update(input).digest('hex')
        },
      },
      buffer: {
        from(value, encoding) { return Buffer.from(value, encoding) },
        bufToString(value, encoding = 'utf8') { return Buffer.from(value).toString(encoding) },
      },
      zlib: {
        inflate(value) {
          return new Promise((resolve, reject) => {
            zlib.inflate(value, (error, data) =>
              error ? reject(new Error(error.message)) : resolve(data))
          })
        },
        deflate(value) {
          return new Promise((resolve, reject) => {
            zlib.deflate(value, (error, data) =>
              error ? reject(new Error(error.message)) : resolve(data))
          })
        },
      },
    },
  }
  const consoleOutput = (...args) => trace('console', args.map(value => {
    try { return typeof value === 'string' ? value : JSON.stringify(value) }
    catch { return String(value) }
  }).join(' '))
  const quietConsole = Object.freeze({
    log: consoleOutput, info: consoleOutput, warn: consoleOutput,
    error: consoleOutput, debug: consoleOutput, group: consoleOutput, groupEnd() {},
  })
  context = vm.createContext({
    lx,
    console: quietConsole,
    URL,
    URLSearchParams,
    TextEncoder: global.TextEncoder,
    TextDecoder: global.TextDecoder,
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval,
  }, { name: 'kos-lx-source' })
  context.globalThis = context
  context.window = context
  const script = new vm.Script(String(command.script || ''), {
    filename: String(command.info?.fileName || 'custom-source.js'),
  })
  script.runInContext(context, { timeout: 3000 })
  let initializationTimer
  const initializationTimeout = new Promise((_, reject) => {
    initializationTimer = setTimeout(
      () => reject(new Error('Source initialization timed out')), 15000)
  })
  try {
    await Promise.race([initialized, initializationTimeout])
  } finally {
    clearTimeout(initializationTimer)
  }
  if (!requestHandler)
    throw new Error('Source did not register a request handler')
  if (initializedData == null)
    throw new Error('Source did not announce its supported providers')
  sourceCapabilities = normalizeInitialization(initializedData)
  reply(command.id, true, sourceCapabilities)
}

async function resolveTrack(command) {
  if (!requestHandler) throw new Error('The source is not ready')
  const request = command.request || {}
  const capability = sourceCapabilities?.sources?.[request.source]
  if (!capability)
    throw new Error(`The active source does not support provider: ${request.source || 'unknown'}`)
  if (!capability.actions.includes(request.action))
    throw new Error(`The active source does not support action: ${request.action || 'unknown'}`)
  if (request.source !== 'local'
      && !capability.qualitys.includes(request.info?.type)) {
    throw new Error(`The active source does not support quality: ${request.info?.type || 'unknown'}`)
  }
  const value = await requestHandler(request)
  const urlText = typeof value === 'string' ? value : value?.url
  if (String(urlText || '').length > 2048)
    throw new Error('The source returned an audio URL that is too long')
  const url = new URL(String(urlText || ''))
  if (url.protocol !== 'http:' && url.protocol !== 'https:')
    throw new Error('The source returned an invalid audio URL')
  return { url: url.toString() }
}

const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity })
input.on('line', async line => {
  let command
  try {
    command = JSON.parse(line)
    if (!command.id) throw new Error('Invalid host command')
    if (command.op === 'load') {
      await loadSource(command)
    } else if (command.op === 'resolve') {
      reply(command.id, true, await resolveTrack(command))
    } else {
      throw new Error('Unknown host operation')
    }
  } catch (error) {
    reply(command?.id || '', false, undefined, safeError(error).message)
  }
})

process.on('SIGTERM', () => process.exit(0))
