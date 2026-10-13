export default defineEventHandler(async (event) => {
  await setUserSession(event, {
    user: {
      id: 1,
      login: 'yunyoujun',
      nickname: '云游君',
      avatar: 'https://avatars.githubusercontent.com/u/20711902',
    },
    // secure: {},
    loggedInAt: Date.now(),
  })
})
