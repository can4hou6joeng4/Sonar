import { NativeModules } from 'react-native'

const CryptoModule = NativeModules.CryptoModule as undefined | {
  generateRsaKey: () => Promise<{ publicKey: string, privateKey: string }>
  rsaEncrypt: (text: string, key: string, padding: RSA_PADDING) => Promise<string>
  rsaDecrypt: (text: string, key: string, padding: RSA_PADDING) => Promise<string>
  rsaEncryptSync: (text: string, key: string, padding: RSA_PADDING) => string
  rsaDecryptSync: (text: string, key: string, padding: RSA_PADDING) => string
  aesEncrypt: (text: string, key: string, vi: string, mode: AES_MODE) => Promise<string>
  aesDecrypt: (text: string, key: string, vi: string, mode: AES_MODE) => Promise<string>
  aesEncryptSync: (text: string, key: string, vi: string, mode: AES_MODE) => string
  aesDecryptSync: (text: string, key: string, vi: string, mode: AES_MODE) => string
}

const getCryptoModule = () => {
  if (!CryptoModule) throw new Error('CryptoModule is not available on current platform')
  return CryptoModule
}

enum KEY_PREFIX {
  publicKeyStart = '-----BEGIN PUBLIC KEY-----',
  publicKeyEnd = '-----END PUBLIC KEY-----',
  privateKeyStart = '-----BEGIN PRIVATE KEY-----',
  privateKeyEnd = '-----END PRIVATE KEY-----',
}

export enum RSA_PADDING {
  OAEPWithSHA1AndMGF1Padding = 'RSA/ECB/OAEPWithSHA1AndMGF1Padding',
  NoPadding = 'RSA/ECB/NoPadding',
}

export enum AES_MODE {
  CBC_128_PKCS7Padding = 'AES/CBC/PKCS7Padding',
  ECB_128_NoPadding = 'AES',
}

export const generateRsaKey = async() => {
  const key = await getCryptoModule().generateRsaKey() as { publicKey: string, privateKey: string }
  return {
    publicKey: `${KEY_PREFIX.publicKeyStart}\n${key.publicKey}${KEY_PREFIX.publicKeyEnd}`,
    privateKey: `${KEY_PREFIX.privateKeyStart}\n${key.privateKey}${KEY_PREFIX.privateKeyEnd}`,
  }
}

export const rsaEncrypt = async(text: string, key: string, padding: RSA_PADDING): Promise<string> => {
  return getCryptoModule().rsaEncrypt(text, key
    .replace(KEY_PREFIX.publicKeyStart, '')
    .replace(KEY_PREFIX.publicKeyEnd, ''),
  padding)
}

export const rsaDecrypt = async(text: string, key: string, padding: RSA_PADDING): Promise<string> => {
  return getCryptoModule().rsaDecrypt(text, key
    .replace(KEY_PREFIX.privateKeyStart, '')
    .replace(KEY_PREFIX.privateKeyEnd, ''),
  padding)
}

export const rsaEncryptSync = (text: string, key: string, padding: RSA_PADDING): string => {
  return getCryptoModule().rsaEncryptSync(text, key
    .replace(KEY_PREFIX.publicKeyStart, '')
    .replace(KEY_PREFIX.publicKeyEnd, ''),
  padding)
}

export const rsaDecryptSync = (text: string, key: string, padding: RSA_PADDING): string => {
  return getCryptoModule().rsaDecryptSync(text, key
    .replace(KEY_PREFIX.privateKeyStart, '')
    .replace(KEY_PREFIX.privateKeyEnd, ''),
  padding)
}


export const aesEncrypt = async(text: string, key: string, vi: string, mode: AES_MODE): Promise<string> => {
  return getCryptoModule().aesEncrypt(text, key, vi, mode)
}

export const aesDecrypt = async(text: string, key: string, vi: string, mode: AES_MODE): Promise<string> => {
  return getCryptoModule().aesDecrypt(text, key, vi, mode)
}

export const aesEncryptSync = (text: string, key: string, vi: string, mode: AES_MODE): string => {
  return getCryptoModule().aesEncryptSync(text, key, vi, mode)
}

export const aesDecryptSync = (text: string, key: string, vi: string, mode: AES_MODE): string => {
  return getCryptoModule().aesDecryptSync(text, key, vi, mode)
}
