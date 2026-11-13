const assert = require('node:assert/strict')
const model = require('../Model.js')

const modern = model.parsePalette('accent = "#a4a7ff"\nred     = "#de92d8"\ngreen   = "#c4b347"\nblue    = "#32c3ea"\ncolor1 = "#111111"\n')
assert.equal(model.profileColor('power-saver', modern), '#c4b347')
assert.equal(model.profileColor('balanced', modern), '#32c3ea')
assert.equal(model.profileColor('performance', modern), '#de92d8')

const legacy = model.parsePalette("color1 = '#aa0000'\ncolor2 = '#00aa00'\ncolor4 = '#0000aa'\n")
assert.equal(model.profileColor('power-saver', legacy), '#00aa00')
assert.equal(model.profileColor('balanced', legacy), '#0000aa')
assert.equal(model.profileColor('performance', legacy), '#aa0000')

assert.equal(model.profileColor('balanced', {}), '')
assert.equal(model.profileColor('custom', modern), '')
assert.deepEqual(model.parsePalette(null), {})
console.log('Profile palette colors: OK')
