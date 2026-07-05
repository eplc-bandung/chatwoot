import { computed } from 'vue';

/**
 * Composable for handling dark mode.
 * The widget is light-mode only.
 * @returns {Object} An object containing computed properties for dark mode.
 */
export function useDarkMode() {
  const darkMode = computed(() => 'light');
  const prefersDarkMode = computed(() => false);

  return {
    darkMode,
    prefersDarkMode,
  };
}
