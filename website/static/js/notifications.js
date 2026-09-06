(() => {
  const phrases = [...document.querySelectorAll(".notification-message > span")];
  if (phrases.length < 2) return;

  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  let current = 0;
  let timer;

  function updateRotation() {
    window.clearInterval(timer);
    if (reducedMotion.matches || document.hidden) return;

    timer = window.setInterval(() => {
      phrases[current].classList.remove("is-visible");
      current = (current + 1) % phrases.length;
      phrases[current].classList.add("is-visible");
    }, 6000);
  }

  reducedMotion.addEventListener("change", updateRotation);
  document.addEventListener("visibilitychange", updateRotation);
  updateRotation();
})();
