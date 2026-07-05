// The app is light-mode only.
export const setColorTheme = () => {
  document.body.classList.remove('dark');
  document.documentElement.style.setProperty('color-scheme', 'light');
};
