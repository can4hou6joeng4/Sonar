export default {
  setTimeout(callback, delay) {
    return globalThis.setTimeout(callback, delay)
  },
  clearTimeout(id) {
    return globalThis.clearTimeout(id)
  },
}
