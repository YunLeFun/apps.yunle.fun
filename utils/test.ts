interface Test {
  a: string
  b: number[]
  c: string[]
}

// type A = Pick<Test, 'b'>

// 动态获取 Test 中不为 number 的属性
// type B = {
//   [K in keyof Test as Test[K] extends number ? never : K]: Test[K]
// }

type B<T> = {
  [K in keyof T as (T[K] extends any[] ?  K: never)]: T[K]
}

// infer
// type B1<T> = {}

type C = B<Test>
