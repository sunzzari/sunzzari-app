const apn = require('@parse/node-apn')

// Validate required env vars at cold start
const requiredEnv = ['APNS_KEY', 'APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_BUNDLE_ID', 'PUSH_SECRET']
for (const key of requiredEnv) {
  if (!process.env[key]) console.warn(`[push] Missing env var: ${key}`)
}

let provider = null

function getProvider() {
  if (provider) return provider
  // APNS_KEY_BASE64 stores the .p8 file base64-encoded (avoids Vercel newline issues)
  const rawKey = Buffer.from(process.env.APNS_KEY_BASE64 || '', 'base64').toString('utf8')
  provider = new apn.Provider({
    token: {
      key: Buffer.from(rawKey, 'utf8'),
      keyId: process.env.APNS_KEY_ID,
      teamId: process.env.APNS_TEAM_ID,
    },
    production: process.env.APNS_PRODUCTION === 'true',
  })
  return provider
}

module.exports = async function handler(req, res) {
  // Only POST
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' })
  }

  // Auth check
  const secret = req.headers['x-sunzzari-secret']
  if (!secret || secret !== process.env.PUSH_SECRET) {
    return res.status(401).json({ error: 'Unauthorized' })
  }

  const { title, body, deviceToken } = req.body ?? {}

  if (!title || !body || !deviceToken) {
    return res.status(400).json({ error: 'Missing title, body, or deviceToken' })
  }

  const note = new apn.Notification()
  note.expiry = Math.floor(Date.now() / 1000) + 3600 // expire in 1 hour
  note.sound = 'default'
  note.alert = { title, body }
  note.topic = process.env.APNS_BUNDLE_ID

  try {
    const p = getProvider()
    const result = await p.send(note, deviceToken)

    if (result.failed.length > 0) {
      const err = result.failed[0].error ?? result.failed[0].response
      console.error('[push] APNs failure:', JSON.stringify(err))
      return res.status(502).json({ error: 'APNs delivery failed', detail: err })
    }

    return res.status(200).json({ ok: true, sent: result.sent.length })
  } catch (err) {
    console.error('[push] Exception:', err)
    return res.status(500).json({ error: err.message })
  }
}
