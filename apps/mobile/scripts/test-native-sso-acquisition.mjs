import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import process from 'node:process'

// Compile and exercise the actual Foundation-only protocol from the iOS app.
// This verifies URL/context behavior without booting a simulator or launching a login.
const source = readFileSync(new URL('../ios/App/App/WebViewController.swift', import.meta.url), 'utf8')
const begin = source.indexOf('private struct NativeSsoRequest {')
const end = source.indexOf('// MARK: - 页面 JSAPI 分发与鉴权', begin)
assert(begin >= 0 && end > begin, 'Native SSO protocol section must exist')
const directory = mkdtempSync(join(tmpdir(), 'ylf-sso-swift-'))
const path = join(directory, 'main.swift')
const assertions = String.raw`
let touch: [String: Any] = [
  "capturedAt": 1000, "landingHost": "cook.yunle.fun",
  "landingPath": "/random?token=private#secret", "referrerHost": "www.baidu.com",
  "utmSource": "百度", "utmMedium": "organic", "utmCampaign": "",
]
let context: [String: Any] = ["version": 1, "firstTouch": touch, "registerTouch": touch, "unknown": "private"]
let input: [String: Any] = [
  "clientId": "cook-web", "codeChallenge": String(repeating: "c", count: 43),
  "nonce": String(repeating: "n", count: 43), "redirectUri": "https://cook.yunle.fun/auth/callback",
  "scope": ["identity:bootstrap"], "codeChallengeMethod": "S256", "acquisition": context,
]
private let request = NativeSsoProtocol.readRequest(input)!
let url = NativeSsoProtocol.authorizationURL(request: request, state: String(repeating: "s", count: 43))!
let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
let returned = try! JSONSerialization.jsonObject(with: Data(query["acquisition"]!.utf8)) as! [String: Any]
assert(returned["unknown"] == nil)
assert((returned["firstTouch"] as! [String: Any])["landingPath"] as! String == "/random")
assert((returned["firstTouch"] as! [String: Any])["utmSource"] as! String == "百度")
assert(query["code_challenge"] == String(repeating: "c", count: 43))
assert(query["nonce"] == String(repeating: "n", count: 43))
assert(query["redirect_uri"] == "https://cook.yunle.fun/auth/callback")
assert(query["prompt"] == "select_account")
assert(NativeSsoProtocol.readAcquisitionJSON(["version": true, "firstTouch": touch, "registerTouch": touch]) == nil)
var invalidTouch = touch
invalidTouch["landingHost"] = "user:password@example.com"
assert(NativeSsoProtocol.readAcquisitionJSON(["version": 1, "firstTouch": invalidTouch, "registerTouch": touch]) == nil)
var oversized = context
oversized["extra"] = String(repeating: "x", count: 4097)
assert(NativeSsoProtocol.readAcquisitionJSON(oversized) == nil)
var invalidInput = input
invalidInput["acquisition"] = ["version": 2]
private let stillValid = NativeSsoProtocol.readRequest(invalidInput)!
assert(stillValid.acquisitionJSON == nil)
assert(NativeSsoProtocol.authorizationURL(request: stillValid, state: String(repeating: "s", count: 43)) != nil)
print("iOS optional acquisition and unchanged PKCE binding passed")
`
try {
  writeFileSync(path, `import Foundation\nimport Security\n${source.slice(begin, end)}\n${assertions}`)
  const result = spawnSync('swift', [path], { stdio: 'inherit' })
  if (result.error)
    throw result.error
  process.exitCode = result.status ?? 1
}
finally {
  rmSync(directory, { recursive: true, force: true })
}
