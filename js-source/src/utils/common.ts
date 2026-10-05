// Sonar adaptation of lx-music-mobile for the JavaScriptCore WY/TX runtime.
// Modified distribution; see repository-root THIRD_PARTY_NOTICES.md and LICENSES/.
// 非业务工具方法

/**
 * 获取两个数之间的随机整数，大于等于min，小于max
 * @param {*} min
 * @param {*} max
 */
export const getRandom = (min: number, max: number): number => Math.floor(Math.random() * (max - min)) + min


export const sizeFormate = (size: number): string => {
  // Sonar implementation: keep the music SDK's binary scale and display labels.
  if (!Number.isFinite(size) || size <= 0) return '0 B'
  const labels = ['B', 'KB', 'MB', 'GB', 'TB']
  let amount = size
  let unit = 0
  while (amount >= 1024 && unit < labels.length - 1) {
    amount /= 1024
    unit += 1
  }
  return `${amount.toFixed(2)} ${labels[unit]}`
}

/**
 * 将字符串、时间戳等格式转成时间对象
 * @param date 时间
 * @returns 时间对象或空字符串
 */
export const toDateObj = (date?: number | string | Date): Date | '' => {
  // console.log(date)
  if (!date) return ''
  switch (typeof date) {
    case 'string':
      if (!date.includes('T')) date = date.split('.')[0].replace(/-/g, '/')
    // eslint-disable-next-line no-fallthrough
    case 'number':
      date = new Date(date)
    // eslint-disable-next-line no-fallthrough
    case 'object':
      break
    default: return ''
  }
  return date
}

const numFix = (n: number): string => n < 10 ? (`0${n}`) : n.toString()
/**
 * 时间格式化
 * @param _date 时间
 * @param format Y-M-D h:m:s Y年 M月 D日 h时 m分 s秒
 */
export const dateFormat = (_date: number | string | Date, format = 'Y-M-D h:m:s') => {
  // console.log(date)
  const date = toDateObj(_date)
  if (!date) return ''
  return format
    .replace('Y', date.getFullYear().toString())
    .replace('M', numFix(date.getMonth() + 1))
    .replace('D', numFix(date.getDate()))
    .replace('h', numFix(date.getHours()))
    .replace('m', numFix(date.getMinutes()))
    .replace('s', numFix(date.getSeconds()))
}


export const formatPlayTime = (time: number) => {
  let m = Math.trunc(time / 60)
  let s = Math.trunc(time % 60)
  return m == 0 && s == 0 ? '--/--' : numFix(m) + ':' + numFix(s)
}

export const formatPlayTime2 = (time: number) => {
  let m = Math.trunc(time / 60)
  let s = Math.trunc(time % 60)
  return numFix(m) + ':' + numFix(s)
}



export const isUrl = (path: string) => /https?:\/\//.test(path)

// 解析URL参数为对象
export const parseUrlParams = (str: string): Record<string, string> => {
  const params: Record<string, string> = {}
  if (typeof str !== 'string') return params
  const paramsArr = str.split('&')
  for (const param of paramsArr) {
    let [key, value] = param.split('=')
    params[key] = value
  }
  return params
}

/**
 * 生成节流函数
 * @param fn 回调
 * @param delay 延迟
 * @returns
 */
export function throttle<Args extends any[]>(fn: (...args: Args) => void | Promise<void>, delay = 100) {
  let timer: NodeJS.Timeout | null = null
  let _args: Args
  return (...args: Args) => {
    _args = args
    if (timer) return
    timer = setTimeout(() => {
      timer = null
      void fn(..._args)
    }, delay)
  }
}

/**
 * 生成防抖函数
 * @param fn 回调
 * @param delay 延迟
 * @returns
 */
export function debounce<Args extends any[]>(fn: (...args: Args) => void | Promise<void>, delay = 100) {
  let timer: NodeJS.Timeout | null = null
  let _args: Args
  return (...args: Args) => {
    _args = args
    if (timer) clearTimeout(timer)
    timer = setTimeout(() => {
      timer = null
      void fn(..._args)
    }, delay)
  }
}

const fileNameRxp = /[\\/:*?#"<>|]/g
export const filterFileName = (name: string): string => name.replace(fileNameRxp, '')


/**
 * 排序字符串
 * @param arr
 * @param data
 */
export const sortInsert = <T>(arr: Array<{ num: number, data: T }>, data: { num: number, data: T }) => {
  let key = data.num
  let left = 0
  let right = arr.length - 1

  while (left <= right) {
    let middle = Math.trunc((left + right) / 2)
    if (key == arr[middle].num) {
      left = middle
      break
    } else if (key < arr[middle].num) {
      right = middle - 1
    } else {
      left = middle + 1
    }
  }
  while (left > 0) {
    if (arr[left - 1].num != key) break
    left--
  }

  arr.splice(left, 0, data)
}


export const arrPush = <T>(list: T[], newList: T[]) => {
  for (let i = 0; i * 1000 < newList.length; i++) {
    list.push(...newList.slice(i * 1000, (i + 1) * 1000))
  }
  return list
}

export const arrUnshift = <T>(list: T[], newList: T[]) => {
  for (let i = 0; i * 1000 < newList.length; i++) {
    list.splice(i * 1000, 0, ...newList.slice(i * 1000, (i + 1) * 1000))
  }
  return list
}

export const arrPushByPosition = <T>(list: T[], newList: T[], position: number) => {
  for (let i = 0; i * 1000 < newList.length; i++) {
    list.splice(position + i * 1000, 0, ...newList.slice(i * 1000, (i + 1) * 1000))
  }
  return list
}


// export const freezeListItem = <T extends any[]>(list: T): MakeArrayItemReadOnly<T> => {
//   for (let i = 0; i < list.length; i++) {
//     Object.freeze(list[i])
//   }
//   return list
// }

export const b64DecodeUnicode = (str: string) => {
  // Going backwards: from bytestream, to percent-encoding, to original string.
  return Buffer.from(str, 'base64').toString()
}
