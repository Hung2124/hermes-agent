// Offline integrity check for an .asar archive — no external tooling required.
//
// Used by apply-desktop-update.cmd before swapping app.asar so a truncated or
// corrupt build is never copied over a working install. This replaces a
// network-dependent `npx asar list`: an .asar begins with a 16-byte pickle
// preamble whose last UInt32LE is the byte length of a JSON header describing
// every packed file. If that header parses and lists files, the archive is
// structurally sound.
//
// Usage: node validate-asar.mjs <path-to-asar> [minBytes]
// Exit:  0 = valid, 1 = invalid/corrupt/too small, 2 = bad usage / unreadable

import { closeSync, fstatSync, openSync, readSync } from 'node:fs'

const archivePath = process.argv[2]
const minBytes = Number(process.argv[3] || 10_000_000)

if (!archivePath) {
  console.error('validate-asar: missing archive path')
  process.exit(2)
}

let fd
try {
  fd = openSync(archivePath, 'r')
} catch (err) {
  console.error(`validate-asar: cannot open ${archivePath}: ${err.message}`)
  process.exit(2)
}

let code = 0
let detail = ''
try {
  const { size } = fstatSync(fd)
  if (size < minBytes) {
    throw new Error(`archive too small (${size} < ${minBytes} bytes) — likely truncated`)
  }

  const preamble = Buffer.alloc(16)
  if (readSync(fd, preamble, 0, 16, 0) < 16) {
    throw new Error('archive shorter than asar header preamble')
  }

  // Bytes 12..16 hold the UInt32LE length of the JSON header, which starts at offset 16.
  const jsonSize = preamble.readUInt32LE(12)
  if (jsonSize <= 0 || jsonSize + 16 > size) {
    throw new Error(`implausible header size (${jsonSize})`)
  }

  const headerBuf = Buffer.alloc(jsonSize)
  if (readSync(fd, headerBuf, 0, jsonSize, 16) < jsonSize) {
    throw new Error('header truncated')
  }

  const header = JSON.parse(headerBuf.toString('utf8'))
  const fileCount = header && header.files ? Object.keys(header.files).length : 0
  if (fileCount === 0) {
    throw new Error('header lists zero files')
  }

  detail = `OK — ${size} bytes, ${fileCount} top-level entries`
} catch (err) {
  code = 1
  detail = err instanceof SyntaxError ? `header is not valid JSON: ${err.message}` : err.message
} finally {
  closeSync(fd)
}

if (code === 0) {
  console.log(`validate-asar: ${detail}`)
} else {
  console.error(`validate-asar: ${detail}`)
}

process.exit(code)
