export const AES_MODE = {
  CBC_128_PKCS7Padding: 'AES/CBC/PKCS7Padding',
  ECB_128_NoPadding: 'AES',
}
export const RSA_PADDING = {
  OAEPWithSHA1AndMGF1Padding: 'RSA/ECB/OAEPWithSHA1AndMGF1Padding',
  NoPadding: 'RSA/ECB/NoPadding',
}
// The legacy module calls these as (base64, key, iv, mode).
export const aesEncryptSync = (data, key, iv, mode) => globalThis.__sonar_aes_encrypt__(data, mode, key, iv)
export const aesDecryptSync = (data, key, iv, mode) => globalThis.__sonar_aes_decrypt__(data, mode, key, iv)
export const rsaEncryptSync = (data, key, padding) => globalThis.__sonar_rsa_encrypt__(
  data,
  key.replace('-----BEGIN PUBLIC KEY-----', '').replace('-----END PUBLIC KEY-----', '').replace(/\s/g, ''),
  padding,
)
