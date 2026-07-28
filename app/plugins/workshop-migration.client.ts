export default defineNuxtPlugin(() => {
  localStorage.removeItem('ylf:market-sources')
  localStorage.removeItem('ylf:active-market')
})
